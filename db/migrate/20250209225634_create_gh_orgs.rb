class CreateGhOrgs < ActiveRecord::Migration[8.0]
  def change
    create_table :gh_orgs do |t|
      t.bigint :gh_id, null: false
      t.string :name, null: false

      t.timestamps
    end
    add_index :gh_orgs, :gh_id, unique: true
    add_index :gh_orgs, :name, unique: true
  end
end
