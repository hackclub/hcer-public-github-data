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

      repo.update!(name: repo_data['name'])

      # Fetch commits for the repository
      Rails.logger.info "Scraping commits for repository: #{owner}/#{name}"
      commits = get_paginated("repos/#{owner}/#{name}/commits")
      commits.each do |commit_data|
        next unless commit_data['author'] # Skip commits without author data
        
        # Create basic user record for the author
        author = ensure_user(commit_data['author'])

        # Create or update commit
        commit = Commit.find_or_initialize_by(sha: commit_data['sha'])
        commit.update!(
          gh_user: author,
          message: commit_data['commit']['message'],
          committed_at: commit_data['commit']['author']['date']
        )

        # Associate commit with repo if not already associated
        repo.commits << commit unless repo.commit_ids.include?(commit.sha)
      end

      repo
    end
  end
end 