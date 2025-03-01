module Api
  class UsersController < ApplicationController
    before_action :find_tracked_user, only: [:days_with_commits_in_range]
    
    def days_with_commits_in_range
      start_date = parse_date(params[:start])
      end_date = parse_date(params[:end])
      
      unless start_date && end_date
        return render plain: "Invalid date format. Use YYYY-MM-DD.", status: :bad_request
      end
      
      if start_date > end_date
        return render plain: "Start date must be before end date.", status: :bad_request
      end
      
      unless @tracked_user.gh_user.present?
        return render plain: "No GitHub data available for this user.", status: :not_found
      end
      
      # Count distinct days with commits within the date range
      days_count = @tracked_user.gh_user.gh_commits
                     .where(committed_at: start_date.beginning_of_day..end_date.end_of_day)
                     .select("DATE(committed_at)")
                     .distinct
                     .count
      
      render plain: days_count.to_s
    end
    
    private
    
    def find_tracked_user
      # Find a GhUser by username that is associated with a TrackedGhUser
      gh_user = GhUser.where("LOWER(username) = LOWER(?)", params[:username]).first
      @tracked_user = TrackedGhUser.find_by(gh_id: gh_user&.gh_id) if gh_user
      
      unless @tracked_user
        render plain: "User not found", status: :not_found
      end
    end
    
    def parse_date(date_string)
      Date.parse(date_string)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
