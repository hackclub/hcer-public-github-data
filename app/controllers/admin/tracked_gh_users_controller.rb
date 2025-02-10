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
      
      results = { success: [], error: [] }
      
      usernames.each do |username|
        begin
          # Fetch user data from GitHub
          user_data = GhScraper::Base.get("users/#{username}")
          
          # Create tracked user
          tracked_user = TrackedGhUser.create!(
            username: username,
            gh_id: user_data['id'],
            tags: tags,
            scrape_last_requested_at: Time.current
          )
          
          results[:success] << username
        rescue GhScraper::NotFoundError
          results[:error] << "#{username} - User not found"
        rescue => e
          results[:error] << "#{username} - #{e.message}"
        end
      end
      
      if results[:error].any?
        flash.now[:alert] = "Some users could not be added: #{results[:error].join(', ')}"
      end
      
      if results[:success].any?
        flash[:notice] = "Successfully added #{results[:success].count} users"
        redirect_to admin_tracked_gh_users_path
      else
        @tracked_gh_user = TrackedGhUser.new
        render :new
      end
    end
  end
end 