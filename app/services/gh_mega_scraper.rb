# overview
#
# go through all users and upsert records
# for each user get all orgs and upsert them
# for each user and org, get all repos and upsert them
# for each repo with a most recent push that's more recent than the rescrape interval, scrape the repo's commits
# if there is a repo with a user profile readme, scrape the readme and save it to the corresponding user record
module GhMegaScraper
  THREADS = 16
  BATCH_SIZE = 100

  class Scrape
    def self.begin(usernames = [], rescrape_interval = 1.day)
      tracked_gh_users_to_process = if usernames.present?
        TrackedGhUser.where(username: usernames)
      else
        TrackedGhUser.all
      end
      
      # Step 1: Upsert all users
      upsert_users(tracked_gh_users_to_process)
      
      # Step 2: Upsert all orgs for these users
      upsert_orgs(tracked_gh_users_to_process)
      
      # # Step 3: Associate users with their orgs
      # associate_users_with_orgs(users, orgs)
      
      # # Step 4: Upsert all repos for users and orgs
      # repos = upsert_repos(users + orgs)
      
      # # Step 5: Process commits for repos that need updating
      # process_commits(repos, rescrape_interval)
      
      # # Step 6: Process profile readmes
      # process_profile_readmes(users)
    end

    private
    
    def self.upsert_users(tracked_gh_users_to_process)
      tracked_gh_users_to_process.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        data = Parallel.map(batch, in_threads: THREADS) do |tracked_gh_user|
          begin
            user_data =GhApi::Client.request("/users/#{tracked_gh_user.username}")

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

        GhUser.upsert_all(data, unique_by: :gh_id)
      end
    end

    def self.upsert_orgs(tracked_gh_users_to_process)
      tracked_gh_users_to_process.includes(:gh_user).find_in_batches(batch_size: BATCH_SIZE) do |batch|
        associations = []
        data = Parallel.flat_map(batch, in_threads: THREADS) do |tracked_gh_user|
          begin
            o = GhApi::Client.request_paginated("users/#{tracked_gh_user.username}/orgs") rescue []

            o.map do |o|
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
      end
    end
  end
end
