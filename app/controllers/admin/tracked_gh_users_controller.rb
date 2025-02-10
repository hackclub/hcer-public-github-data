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

    def scrape
      @tracked_user = TrackedGhUser.find(params[:id])
      
      # Update timestamp first
      @tracked_user.update!(scrape_last_requested_at: Time.current)
      
      # Then enqueue the job
      ScrapeGithubUserJob.perform_later(@tracked_user.id)

      # Refresh the tracked users list with the updated timestamp
      @tracked_users = TrackedGhUser.order(scrape_last_requested_at: :desc)

      respond_to do |format|
        format.turbo_stream { 
          flash.now[:notice] = "Started scraping data for #{@tracked_user.username}"
          render turbo_stream: [
            turbo_stream.update("flash", partial: "shared/flash"),
            turbo_stream.update("tracked_users_table", partial: "table", locals: { tracked_users: @tracked_users })
          ]
        }
        format.html { 
          flash[:notice] = "Started scraping data for #{@tracked_user.username}"
          redirect_to admin_tracked_gh_users_path
        }
      end
    end

    def scrape_all
      # Update timestamps first
      TrackedGhUser.update_all(scrape_last_requested_at: Time.current)
      
      # Then enqueue jobs for all users
      TrackedGhUser.find_each do |user|
        ScrapeGithubUserJob.perform_later(user.id)
      end

      # Refresh the tracked users list with updated timestamps
      @tracked_users = TrackedGhUser.order(scrape_last_requested_at: :desc)

      respond_to do |format|
        format.turbo_stream { 
          flash.now[:notice] = "Started scraping data for all users"
          render turbo_stream: [
            turbo_stream.update("flash", partial: "shared/flash"),
            turbo_stream.update("tracked_users_table", partial: "table", locals: { tracked_users: @tracked_users })
          ]
        }
        format.html { 
          flash[:notice] = "Started scraping data for all users"
          redirect_to admin_tracked_gh_users_path
        }
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