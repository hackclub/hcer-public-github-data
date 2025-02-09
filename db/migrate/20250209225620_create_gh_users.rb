class CreateGhUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :gh_users do |t|
      t.bigint :gh_id, null: false
      t.string :username, null: false

      t.timestamps
    end
    add_index :gh_users, :gh_id, unique: true
    add_index :gh_users, :username, unique: true
  end
end
