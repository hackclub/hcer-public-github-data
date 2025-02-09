class CreateCommits < ActiveRecord::Migration[8.0]
  def change
    create_table :commits, id: :string, primary_key: :sha do |t|
      t.references :gh_user, null: false, foreign_key: true
      t.datetime :committed_at, null: false
      t.text :message, null: false

      t.timestamps
    end
  end
end
