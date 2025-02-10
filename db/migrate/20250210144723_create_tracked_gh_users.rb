class CreateTrackedGhUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :tracked_gh_users do |t|
      t.bigint :gh_id
      t.string :username
      t.jsonb :tags
      t.datetime :scrape_last_requested_at

      t.timestamps
    end
  end
end
