class FixCommitsGhReposJoinTable < ActiveRecord::Migration[8.0]
  def up
    # Drop the existing table and its indices
    drop_table :commits_gh_repos

    # Recreate with correct column types
    create_table :commits_gh_repos, id: false do |t|
      t.string :commit_id, null: false
      t.bigint :gh_repo_id, null: false
      t.index [:commit_id, :gh_repo_id], unique: true
      t.index [:gh_repo_id, :commit_id]
    end

    add_foreign_key :commits_gh_repos, :commits, column: :commit_id, primary_key: :sha
    add_foreign_key :commits_gh_repos, :gh_repos
  end

  def down
    drop_table :commits_gh_repos

    create_join_table :commits, :gh_repos do |t|
      t.index [:commit_id, :gh_repo_id]
      t.index [:gh_repo_id, :commit_id]
    end
  end
end
