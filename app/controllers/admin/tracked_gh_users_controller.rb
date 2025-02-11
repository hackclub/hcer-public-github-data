module Admin
  class TrackedGhUsersController < BaseController
    include ActionView::RecordIdentifier
    include ActionView::Helpers::TagHelper
    helper_method :scrape_status_badge, :recently_requested?

    def index
      @tracked_users = TrackedGhUser
        .order(scrape_last_requested_at: :desc)
    end

    def new
      @tracked_gh_user = TrackedGhUser.new
      @known_tags = TrackedGhUser.pluck(:tags).compact.flatten.uniq.sort
    end

    def create
      usernames = params[:usernames].to_s.split("\n").map(&:strip).reject(&:blank?)
      checked_tags = Array(params[:tags])
      new_tags = params[:new_tags].to_s.split(",").map(&:strip).reject(&:blank?)
      all_tags = (checked_tags + new_tags).uniq

      if usernames.any?
        # Enqueue the job to process users
        AddTrackedUsersJob.perform_later(usernames, all_tags)
        
        flash[:notice] = "Processing #{usernames.count} usernames in the background. Check back soon to see the results."
        redirect_to admin_tracked_gh_users_path
      else
        flash.now[:alert] = "Please enter at least one username"
        @tracked_gh_user = TrackedGhUser.new
        render :new
      end
    end

    private

    def scrape_status_badge(user)
      if user.scrape_last_completed_at.nil?
        tag.span "Never Scraped", class: "status-badge warning"
      elsif user.scrape_last_completed_at < 24.hours.ago
        tag.span "Needs Update", class: "status-badge error"
      else
        tag.span "Up to Date", class: "status-badge success"
      end
    end

    def recently_requested?(user)
      user.scrape_last_requested_at && user.scrape_last_requested_at > 5.minutes.ago
    end
  end
end 