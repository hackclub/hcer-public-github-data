class CreateGhRepos < ActiveRecord::Migration[8.0]
  def change
    create_table :gh_repos do |t|
      t.bigint :gh_id, null: false
      t.string :name, null: false
      t.references :gh_user, null: true, foreign_key: true
      t.references :gh_org, null: true, foreign_key: true

      t.timestamps
    end
    add_index :gh_repos, :gh_id, unique: true
    add_index :gh_repos, :name
  end
end
