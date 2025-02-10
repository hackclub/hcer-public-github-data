class RenameCommitToGhCommit < ActiveRecord::Migration[8.0]
  def change
    # Remove existing foreign keys first
    remove_foreign_key :commits_gh_repos, :commits
    remove_foreign_key :commits_gh_repos, :gh_repos
    
    # Rename the main table
    rename_table :commits, :gh_commits
    
    # Rename the join table
    rename_table :commits_gh_repos, :gh_commits_gh_repos
    
    # Rename the column in the join table
    rename_column :gh_commits_gh_repos, :commit_id, :gh_commit_id
    
    # Add back the foreign keys with new names
    add_foreign_key :gh_commits_gh_repos, :gh_commits, primary_key: :sha
    add_foreign_key :gh_commits_gh_repos, :gh_repos
  end
end
