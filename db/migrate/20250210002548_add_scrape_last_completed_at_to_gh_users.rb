class AddScrapeLastCompletedAtToGhUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :gh_users, :scrape_last_completed_at, :datetime
  end
end
