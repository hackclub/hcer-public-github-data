class GhMegaScraperJob < ApplicationJob
  queue_as :default

  def perform(usernames = [], rescrape_interval = 1.day)
    Rails.logger.info "Starting GhMegaScraperJob with usernames: #{usernames} and rescrape_interval: #{rescrape_interval}"
    GhMegaScraper::Scrape.begin(usernames, rescrape_interval)
    Rails.logger.info "Completed GhMegaScraperJob"
  end
end 