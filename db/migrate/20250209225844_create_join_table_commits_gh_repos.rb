class CreateJoinTableCommitsGhRepos < ActiveRecord::Migration[8.0]
  def change
    create_join_table :commits, :gh_repos do |t|
      t.index [:commit_id, :gh_repo_id]
      t.index [:gh_repo_id, :commit_id]
    end
  end
end
