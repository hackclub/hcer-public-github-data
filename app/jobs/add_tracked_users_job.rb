class AddTrackedUsersJob < ApplicationJob
  queue_as :high_priority

  def perform(usernames, tags)
    results = { success: [], error: [], updated: [], skipped_orgs: [] }
    
    usernames.each do |username|
      begin
        # Try to find existing user first
        tracked_user = TrackedGhUser.find_by(username: username)
        
        if tracked_user
          # Update existing user's tags
          existing_tags = tracked_user.tags || []
          new_tags = (existing_tags + tags).uniq
          tracked_user.update!(tags: new_tags)
          results[:updated] << username
        else
          # Fetch user data from GitHub to check if it's a user (not an org)
          user_data = GhApi::Client.request("users/#{username}")
          
          # Skip if this is an organization
          if user_data[:type] == 'Organization'
            results[:skipped_orgs] << username
            next
          end
          
          # Create tracked user
          tracked_user = TrackedGhUser.create!(
            username: username,
            gh_id: user_data[:id],
            tags: tags
          )
          
          results[:success] << username
        end
      rescue GhApi::NotFoundError
        results[:error] << "#{username} - User not found"
      rescue GhApi::RateLimitError
        results[:error] << "#{username} - Rate limit exceeded, try again later"
      rescue GhApi::NoAvailableTokensError
        results[:error] << "#{username} - No available GitHub tokens"
      rescue => e
        results[:error] << "#{username} - #{e.message}"
      end
    end
    
    # Return results for potential future use (e.g., notifications)
    results
  end
end 