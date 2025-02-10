module Admin
  class HomeController < BaseController
    def index
      @tracked_users_count = TrackedGhUser.count
      @tracked_users_with_data = TrackedGhUser.joins(:gh_user).count
      @tracked_users_needing_scrape = TrackedGhUser
        .joins(:gh_user)
        .where(gh_users: { scrape_last_completed_at: [nil, ..24.hours.ago] })
        .count
    end
  end
end 