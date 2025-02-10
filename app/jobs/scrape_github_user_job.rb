class ScrapeGithubUserJob < ApplicationJob
  queue_as :default

  def perform(tracked_gh_user_id)
    tracked_user = TrackedGhUser.find(tracked_gh_user_id)

    begin
      GhScraper::User.scrape(tracked_user.username)
    rescue GhScraper::Error => e
      Rails.logger.error "Failed to scrape user #{tracked_user.username}: #{e.message}"
      raise # Re-raise to mark job as failed
    end
  end
end
