module Admin
  class TrackedGhUsersController < BaseController
    def index
      @tracked_users = TrackedGhUser
        .order(scrape_last_requested_at: :desc)
    end

    def new
      @tracked_gh_user = TrackedGhUser.new
    end

    def create
      usernames = params[:usernames].to_s.split("\n").map(&:strip).reject(&:blank?)
      tags = params[:tags].to_s.split(",").map(&:strip).reject(&:blank?)
      
      results = { success: [], error: [], updated: [] }
      
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
            # Fetch user data from GitHub for new user
            user_data = GhScraper::Base.get("users/#{username}")
            
            # Create tracked user
            tracked_user = TrackedGhUser.create!(
              username: username,
              gh_id: user_data['id'],
              tags: tags,
              scrape_last_requested_at: Time.current
            )
            
            results[:success] << username
          end
        rescue GhScraper::NotFoundError
          results[:error] << "#{username} - User not found"
        rescue => e
          results[:error] << "#{username} - #{e.message}"
        end
      end
      
      flash_messages = []
      flash_messages << "Added #{results[:success].count} new users" if results[:success].any?
      flash_messages << "Updated tags for #{results[:updated].count} existing users" if results[:updated].any?
      flash_messages << "Errors for #{results[:error].count} users: #{results[:error].join(', ')}" if results[:error].any?
      
      if results[:success].any? || results[:updated].any?
        flash[:notice] = flash_messages.join(". ")
        redirect_to admin_tracked_gh_users_path
      else
        flash.now[:alert] = flash_messages.join(". ")
        @tracked_gh_user = TrackedGhUser.new
        render :new
      end
    end
  end
end 