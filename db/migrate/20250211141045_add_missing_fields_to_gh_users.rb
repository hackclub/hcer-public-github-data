class AddMissingFieldsToGhUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :gh_users, :name, :string
    add_column :gh_users, :email, :string
    add_column :gh_users, :bio, :text
    add_column :gh_users, :location, :string
    add_column :gh_users, :company, :string
    add_column :gh_users, :blog, :string
    add_column :gh_users, :twitter_username, :string
    add_column :gh_users, :avatar_url, :string
    add_column :gh_users, :public_repos_count, :integer, default: 0
    add_column :gh_users, :public_gists_count, :integer, default: 0
    add_column :gh_users, :followers_count, :integer, default: 0
    add_column :gh_users, :following_count, :integer, default: 0
    add_column :gh_users, :gh_created_at, :datetime
    add_column :gh_users, :gh_updated_at, :datetime
  end
end
