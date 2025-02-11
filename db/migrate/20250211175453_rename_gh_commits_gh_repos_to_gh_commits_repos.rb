class RenameGhCommitsGhReposToGhCommitsRepos < ActiveRecord::Migration[8.0]
  def change
    rename_table :gh_commits_gh_repos, :gh_commits_repos
  end
end
