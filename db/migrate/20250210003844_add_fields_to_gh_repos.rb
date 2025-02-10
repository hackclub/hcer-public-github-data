class AddFieldsToGhRepos < ActiveRecord::Migration[8.0]
  def change
    change_table :gh_repos do |t|
      # Basic Info
      t.text :description
      t.string :homepage
      t.string :language
      t.datetime :repo_created_at
      t.datetime :repo_updated_at
      t.datetime :pushed_at

      # Stats/Metrics
      t.integer :stargazers_count, default: 0
      t.integer :forks_count, default: 0
      t.integer :watchers_count, default: 0
      t.integer :open_issues_count, default: 0
      t.integer :size, default: 0

      # Repository Status
      t.boolean :private, default: false
      t.boolean :archived, default: false
      t.boolean :disabled, default: false
      t.boolean :fork, default: false

      # Additional Features
      t.string :topics, array: true, default: []
      t.string :default_branch
      t.boolean :has_issues, default: true
      t.boolean :has_wiki, default: true
      t.boolean :has_discussions, default: false
    end

    # Add indexes for commonly queried fields
    add_index :gh_repos, :language
    add_index :gh_repos, :fork
    add_index :gh_repos, :archived
    add_index :gh_repos, :private
    add_index :gh_repos, :topics, using: 'gin'
    add_index :gh_repos, :stargazers_count
    add_index :gh_repos, :forks_count
  end
end
