module GhScraper
  class Error < StandardError; end
  class RateLimitError < Error; end
  class NotFoundError < Error; end
  class EmptyRepoError < Error; end

  class Base
    private

    def self.get(path, params = {})
      query = params.empty? ? '' : "?#{params.to_query}"
      response = Faraday.get(
        "#{Rails.application.config.github_proxy_url}/gh/#{path}#{query}",
        nil,
        { 'X-Proxy-API-Key' => Rails.application.credentials.proxy_api_key }
      )

      case response.status
      when 200
        JSON.parse(response.body)
      when 404
        raise NotFoundError, "GitHub resource not found: #{path}"
      when 409
        if path.include?('/commits')
          # Return empty array for empty repositories
          []
        else
          raise Error, "GitHub API error (409): #{response.body}"
        end
      when 403
        if response.body.include?('rate limit')
          raise RateLimitError, "Rate limit exceeded for path: #{path}"
        else
          raise Error, "GitHub API error: #{response.body}"
        end
      else
        raise Error, "GitHub API error (#{response.status}): #{response.body}"
      end
    end

    def self.get_paginated(path, params = {})
      results = []
      page = 1

      loop do
        page_params = params.merge(page: page, per_page: 100)
        page_data = get(path, page_params)
        
        break if page_data.empty?
        
        results.concat(page_data)
        break if page_data.length < 100
        
        page += 1
      end

      results
    end

    def self.get_all_pages?(default = true)
      Rails.env.production? ? default : false
    end

    def self.ensure_user(user_data)
      user = GhUser.find_or_initialize_by(gh_id: user_data['id'])
      user.update!(username: user_data['login'])
      user
    end
  end

  class User < Base
    def self.scrape(username)
      Rails.logger.info "Scraping user: #{username}"
      
      # Fetch user data
      user_data = get("users/#{username}")
      user = ensure_user(user_data)

      # Fetch and store repositories
      Rails.logger.info "Scraping repositories for user: #{username}"
      repos = get_paginated("users/#{username}/repos")
      repos.each do |repo_data|
        next if repo_data['fork'] # Skip forks for now
        
        # Use the Repo scraper to get full repo data including commits
        Repo.scrape(username, repo_data['name'])
      end

      # Fetch organizations and scrape their repos
      Rails.logger.info "Scraping organizations for user: #{username}"
      orgs = get_paginated("users/#{username}/orgs")
      orgs.each do |org_data|
        # Create basic org record and associate with user
        org = GhOrg.find_or_initialize_by(gh_id: org_data['id'])
        org.update!(name: org_data['login'])
        user.gh_orgs << org unless user.gh_org_ids.include?(org.id)

        # Scrape all repos for this org
        Org.scrape_repos(org_data['login'])
      end

      # Update the last completed timestamp
      user.update!(scrape_last_completed_at: Time.current)

      user
    end
  end

  class Org < Base
    def self.scrape_repos(org_name)
      Rails.logger.info "Scraping repositories for organization: #{org_name}"
      
      # Fetch and store repositories
      repos = get_paginated("orgs/#{org_name}/repos")
      repos.each do |repo_data|
        next if repo_data['fork'] # Skip forks for now
        
        # Use the Repo scraper to get full repo data including commits
        Repo.scrape(org_name, repo_data['name'])
      end
    end
  end

  class Repo < Base
    def self.scrape(owner, name)
      Rails.logger.info "Scraping repository: #{owner}/#{name}"
      
      # Fetch repo data
      repo_data = get("repos/#{owner}/#{name}")
      
      # Create or update repo record
      repo = GhRepo.find_or_initialize_by(gh_id: repo_data['id'])

      # Determine and set owner (user or org)
      owner_type = repo_data['owner']['type']
      if owner_type == 'User'
        user = ensure_user(repo_data['owner'])
        repo.gh_user = user
        repo.gh_org = nil
      else # Organization
        org = GhOrg.find_or_initialize_by(gh_id: repo_data['owner']['id'])
        org.update!(name: repo_data['owner']['login'])
        repo.gh_org = org
        repo.gh_user = nil
      end

      # Update all repository fields
      repo.update!(
        name: repo_data['name'],
        description: repo_data['description'],
        homepage: repo_data['homepage'],
        language: repo_data['language'],
        repo_created_at: repo_data['created_at'],
        repo_updated_at: repo_data['updated_at'],
        pushed_at: repo_data['pushed_at'],
        stargazers_count: repo_data['stargazers_count'],
        forks_count: repo_data['forks_count'],
        watchers_count: repo_data['watchers_count'],
        open_issues_count: repo_data['open_issues_count'],
        size: repo_data['size'],
        private: repo_data['private'],
        archived: repo_data['archived'],
        disabled: repo_data['disabled'],
        fork: repo_data['fork'],
        topics: repo_data['topics'] || [],
        default_branch: repo_data['default_branch'],
        has_issues: repo_data['has_issues'],
        has_wiki: repo_data['has_wiki'],
        has_discussions: repo_data['has_discussions']
      )

      # Fetch commits for the repository
      Rails.logger.info "Scraping commits for repository: #{owner}/#{name}"
      commits = get_paginated("repos/#{owner}/#{name}/commits")
      
      # Skip if no commits
      return repo if commits.empty?

      # Collect all commit authors first
      author_data = commits.map { |c| c['author'] }
                         .compact
                         .select { |a| a['id'].present? && a['login'].present? }
                         .uniq { |a| a['id'] }
      author_records = author_data.map do |author|
        {
          gh_id: author['id'],
          username: author['login'],
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      # Only proceed with bulk operations if we have valid authors
      return repo if author_records.empty?

      # Bulk upsert authors
      GhUser.upsert_all(
        author_records,
        unique_by: :gh_id,
        returning: false
      )

      # Map author gh_ids to primary keys
      authors_by_gh_id = GhUser.where(gh_id: author_data.map { |a| a['id'] })
                               .index_by(&:gh_id)

      # Prepare commit records
      commit_records = commits.map do |commit_data|
        author = commit_data['author']
        next unless author && author['id'].present? && authors_by_gh_id[author['id']]
        
        {
          sha: commit_data['sha'],
          gh_user_id: authors_by_gh_id[author['id']].id,
          message: commit_data.dig('commit', 'message'),
          committed_at: commit_data['commit']['author']['date'],
          created_at: Time.current,
          updated_at: Time.current
        }
      end.compact

      # Bulk upsert commits
      Commit.upsert_all(
        commit_records,
        unique_by: :sha,
        returning: false
      )

      # Prepare commit-repo associations
      commit_repo_records = commit_records.map do |commit|
        {
          commit_id: commit[:sha],
          gh_repo_id: repo.id
        }
      end

      # Bulk upsert commit-repo associations if we have any records
      if commit_repo_records.any?
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO commits_gh_repos (commit_id, gh_repo_id)
          VALUES #{commit_repo_records.map { |r| "(#{ActiveRecord::Base.connection.quote(r[:commit_id])}, #{r[:gh_repo_id]})" }.join(", ")}
          ON CONFLICT (commit_id, gh_repo_id) DO NOTHING
        SQL
      end

      repo
    end
  end
end 