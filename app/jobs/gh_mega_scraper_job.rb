module GhMegaScraperJob
  class Scrape < ApplicationJob
    queue_with_priority 5

    THREADS = ENV.fetch('MEGA_SCRAPER_THREAD_COUNT', 1).to_i
    BATCH_SIZE = 500

    def perform(usernames = [], rescrape_interval = 16.hours)
      Rails.logger.info "Starting GhMegaScraper with usernames: \\#{usernames.join(', ')} and rescrape_interval: \\#{rescrape_interval}"
      
      tracked_gh_users_to_process = if usernames.present?
        TrackedGhUser.where(username: usernames)
      else
        TrackedGhUser.all
      end
      
      # Step 1: Upsert all users
      upsert_users(tracked_gh_users_to_process)
      
      # Step 2: Upsert all orgs for these users
      upsert_orgs(tracked_gh_users_to_process)
      
      # # Step 4: Upsert all repos for users and orgs
      upsert_repos(tracked_gh_users_to_process)
      
      # # Step 5: Process commits for repos that need updating
      upsert_commits(tracked_gh_users_to_process, rescrape_interval)
      
      # # Step 6: Process profile readmes
      # process_profile_readmes(users)
      
      Rails.logger.info "Finished GhMegaScraper"
    end

    private
    
    def upsert_users(tracked_gh_users_to_process)
      Rails.logger.info "Starting upsert_users with \\#{tracked_gh_users_to_process.size} users"
      
      tracked_gh_users_to_process.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        Rails.logger.info "Processing batch of \\#{batch.size} users"
        
        data = Parallel.map(batch, in_threads: THREADS) do |tracked_gh_user|
          begin
            user_data = GhApi::Client.request("/users/#{tracked_gh_user.username}")

            {
              gh_id: user_data[:id],
              username: user_data[:login],
              name: user_data[:name],
              email: user_data[:email],
              bio: user_data[:bio],
              location: user_data[:location],
              company: user_data[:company],
              blog: user_data[:blog],
              twitter_username: user_data[:twitter_username],
              avatar_url: user_data[:avatar_url],
              public_repos_count: user_data[:public_repos],
              public_gists_count: user_data[:public_gists],
              followers_count: user_data[:followers],
              following_count: user_data[:following],
              gh_created_at: user_data[:created_at],
              gh_updated_at: user_data[:updated_at]
            }
          rescue GhApi::NotFoundError => e
            Rails.logger.warn "Could not find GitHub user: #{tracked_gh_user.username}"
            nil
          rescue GhApi::Error => e
            Rails.logger.error "Error fetching user #{tracked_gh_user.username}: #{e.message}"
            nil
          end
        end.compact

        # dedup by gh_id
        data = data.uniq { |user| user[:gh_id] }

        GhUser.upsert_all(data, unique_by: :gh_id)
        
        Rails.logger.info "Finished processing batch of users"
      end
      
      Rails.logger.info "Finished upsert_users"
    end

    def upsert_orgs(tracked_gh_users_to_process)
      Rails.logger.info "Starting upsert_orgs"
      
      tracked_gh_users_to_process.includes(:gh_user).find_in_batches(batch_size: BATCH_SIZE) do |batch|
        Rails.logger.info "Processing batch of \\#{batch.size} users for orgs"
        
        associations = []
        data = Parallel.flat_map(batch, in_threads: THREADS) do |tracked_gh_user|
          begin
            o = GhApi::Client.request_paginated("users/#{tracked_gh_user.username}/orgs") rescue []

            o.map do |o|
              Rails.logger.info "Processing org #{o[:login]} for user #{tracked_gh_user.username}"
              associations << {
                gh_user_id: tracked_gh_user.gh_user.id,
                gh_org_gh_id: o[:id]
              }

              {
                gh_id: o[:id],
                name: o[:login]
              }
            end
          rescue GhApi::Error => e
            Rails.logger.error "Error fetching orgs for user #{tracked_gh_user.username}: #{e.message}"
            nil
          end
        end.compact

        # dedup
        data = data.uniq { |org| org[:gh_id] }

        GhOrg.upsert_all(data, unique_by: :gh_id)

        # create a hash of gh_id => id for the gh_orgs
        gh_org_ids = GhOrg.where(gh_id: associations.pluck(:gh_org_gh_id)).pluck(:gh_id, :id).to_h

        # Map the associations to use actual gh_org_id instead of gh_id
        associations_to_insert = associations.map do |assoc|
          {
            gh_user_id: assoc[:gh_user_id],
            gh_org_id: gh_org_ids[assoc[:gh_org_gh_id]]
          }
        end

        # Use raw SQL to insert the associations
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO gh_orgs_users (gh_user_id, gh_org_id)
          VALUES #{associations_to_insert.map { |r| "(#{r[:gh_user_id]}, #{r[:gh_org_id]})" }.join(", ")}
          ON CONFLICT (gh_user_id, gh_org_id) DO NOTHING
        SQL
        
        Rails.logger.info "Finished processing batch of orgs"
      end
      
      Rails.logger.info "Finished upsert_orgs"
    end

    def upsert_repos(tracked_gh_users_to_process)
      Rails.logger.info "Starting upsert_repos"
      
      def repo_attrs(repo_resp)
        {
          gh_id: repo_resp[:id],
          name: repo_resp[:name],
          description: repo_resp[:description],
          homepage: repo_resp[:homepage],
          language: repo_resp[:language],
          repo_created_at: repo_resp[:created_at],
          repo_updated_at: repo_resp[:updated_at],
          pushed_at: repo_resp[:pushed_at],
          stargazers_count: repo_resp[:stargazers_count],
          forks_count: repo_resp[:forks_count],
          watchers_count: repo_resp[:watchers_count],
          open_issues_count: repo_resp[:open_issues_count],
          size: repo_resp[:size],
          private: repo_resp[:private],
          archived: repo_resp[:archived],
          disabled: repo_resp[:disabled],
          fork: repo_resp[:fork],
          topics: repo_resp[:topics],
          default_branch: repo_resp[:default_branch],
          has_issues: repo_resp[:has_issues],
          has_wiki: repo_resp[:has_wiki],
          has_discussions: repo_resp[:has_discussions]
        }
      end

      tracked_gh_users_to_process.includes(:gh_user).find_in_batches(batch_size: BATCH_SIZE) do |batch|
        Rails.logger.info "Processing batch of \\#{batch.size} users for repos"
        
        data = Parallel.flat_map(batch, in_threads: THREADS) do |tracked_gh_user|
          begin
            repos = GhApi::Client.request_paginated("users/#{tracked_gh_user.username}/repos") rescue []

            repos.map do |repo|
              attrs = repo_attrs(repo)
              attrs[:gh_user_id] = tracked_gh_user.gh_user.id
              attrs
            end.reject { |repo| repo[:fork] } # Skip forks
          rescue GhApi::Error => e
            Rails.logger.error "Error fetching repos for user #{tracked_gh_user.username}: #{e.message}"
            nil
          end
        end.compact

        GhRepo.upsert_all(data, unique_by: :gh_id)
        
        Rails.logger.info "Finished processing batch of repos"
      end

      GhOrg.joins(:gh_users).where(gh_users: GhUser.where(gh_id: tracked_gh_users_to_process.select(:gh_id))).find_in_batches(batch_size: BATCH_SIZE) do |batch|
        data = Parallel.flat_map(batch, in_threads: THREADS) do |gh_org|
          begin
            repos = GhApi::Client.request_paginated("users/#{gh_org.name}/repos") rescue []

            repos.map do |repo|
              attrs = repo_attrs(repo)
              attrs[:gh_org_id] = gh_org.id
              attrs
            end.reject { |repo| repo[:fork] } # Skip forks
          rescue GhApi::Error => e
            Rails.logger.error "Error fetching repos for org #{gh_org.name}: #{e.message}"
            nil
          end
        end.compact

        GhRepo.upsert_all(data, unique_by: :gh_id)
      end
      
      Rails.logger.info "Finished upsert_repos"
    end

    def upsert_commits(tracked_gh_users_to_process, rescrape_interval)
      Rails.logger.info "Starting upsert_commits"

      # Determine which repos need commits
      repos = GhRepo
        .where(gh_user_id: tracked_gh_users_to_process
          .joins(:gh_user)
          .select('gh_users.id'))
        .or(
          GhRepo.where(gh_org_id: GhOrg
            .joins(:gh_users)
            .merge(GhUser.where(gh_id: tracked_gh_users_to_process.select(:gh_id)))
            .select(:id))
        )
        .where(commits_scrape_last_completed_at: [nil, ..rescrape_interval.ago])

      # Create a GoodJob batch for concurrency
      batch = GoodJob::Batch.new
      batch.description = "GhMegaScraperJob::UpsertCommitsForRepo"
      repos.find_in_batches(batch_size: BATCH_SIZE) do |repo_batch|
        batch.add do
          repo_batch.each do |repo|
            GhMegaScraperJob::UpsertCommitsForRepo.perform_later(repo.id, rescrape_interval)
          end
        end
      end
      batch.enqueue

      Rails.logger.info "Enqueued UpsertCommitsForRepo for concurrency"
      Rails.logger.info "Finished upsert_commits"
    end
  end

  class UpsertCommitsForRepo < ApplicationJob
    def perform(gh_repo_id, rescrape_interval)
      repo = GhRepo.find(gh_repo_id)

      Rails.logger.info "Processing commits for repo #{repo.name} (ID=#{repo.id})"

      # Fetch commits from GitHub
      commits_response = GhApi::Client.request_paginated("repos/#{repo.owner_gh_username}/#{repo.name}/commits") rescue []
      data = commits_response.map do |commit|
        next unless commit[:author]&.dig(:id)

        {
          sha: commit[:sha],
          committed_at: commit[:commit][:author][:date],
          message: commit[:commit][:message],
          tmp_author: {
            login: commit[:author][:login],
            gh_id: commit[:author][:id],
            avatar_url: commit[:author][:avatar_url]
          },
          tmp_gh_repo_id: repo.id
        }
      end.compact

      # Extract unique authors from commits and upsert
      authors = data.map { |c| c[:tmp_author] }.uniq { |a| a[:gh_id] }
      author_records = authors.map do |author|
        {
          gh_id: author[:gh_id],
          username: author[:login],
          avatar_url: author[:avatar_url]
        }
      end
      GhUser.upsert_all(author_records, unique_by: :gh_id) if author_records.any?

      # Build map of gh_id -> gh_user.id
      gh_id_map = GhUser.where(gh_id: authors.map { |a| a[:gh_id] }).pluck(:gh_id, :id).to_h

      # Prepare commits for upsert
      commit_records = data.map do |commit|
        {
          sha: commit[:sha],
          committed_at: commit[:committed_at],
          message: commit[:message],
          gh_user_id: gh_id_map[commit[:tmp_author][:gh_id]]
        }
      end.uniq { |c| c[:sha] }

      GhCommit.upsert_all(commit_records, unique_by: :sha) if commit_records.any?

      # Link commits to the repo (via gh_commits_repos join)
      commit_repo_records = data.map do |commit|
        "(#{ActiveRecord::Base.connection.quote(commit[:sha])}, #{commit[:tmp_gh_repo_id]})"
      end

      if commit_repo_records.any?
        sql = <<~SQL
          INSERT INTO gh_commits_repos (gh_commit_id, gh_repo_id)
          VALUES #{commit_repo_records.join(", ")}
          ON CONFLICT (gh_commit_id, gh_repo_id) DO NOTHING
        SQL
        ActiveRecord::Base.connection.execute(sql)
      end

      # Update the repo's scrape timestamp
      repo.update!(commits_scrape_last_completed_at: Time.current)

      Rails.logger.info "Finished processing commits for repo #{repo.name}"
    end
  end
end
