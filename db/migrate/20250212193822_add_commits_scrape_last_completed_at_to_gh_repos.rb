class AddCommitsScrapeLastCompletedAtToGhRepos < ActiveRecord::Migration[8.0]
  def change
    add_column :gh_repos, :commits_scrape_last_completed_at, :datetime
  end
end
