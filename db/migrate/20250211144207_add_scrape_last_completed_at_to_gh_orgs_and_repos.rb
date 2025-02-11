class AddScrapeLastCompletedAtToGhOrgsAndRepos < ActiveRecord::Migration[7.1]
  def change
    add_column :gh_orgs, :scrape_last_completed_at, :datetime
    add_column :gh_repos, :scrape_last_completed_at, :datetime
  end
end
