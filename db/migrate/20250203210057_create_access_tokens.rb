class CreateAccessTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :access_tokens do |t|
      t.bigint :ghId, null: false
      t.string :username, null: false
      t.string :accessToken, null: false
      t.datetime :lastUsedAt
      t.integer :coreRateLimitRemaining
      t.datetime :coreRateLimitResetAt
      t.integer :searchRateLimitRemaining
      t.datetime :searchRateLimitResetAt
      t.integer :graphqlRateLimitRemaining
      t.datetime :graphqlRateLimitResetAt

      t.timestamps
    end

    add_index :access_tokens, :ghId, unique: true
    add_index :access_tokens, :username, unique: true
    add_index :access_tokens, :lastUsedAt
    add_index :access_tokens, [:coreRateLimitRemaining, :coreRateLimitResetAt]
    add_index :access_tokens, [:searchRateLimitRemaining, :searchRateLimitResetAt]
    add_index :access_tokens, [:graphqlRateLimitRemaining, :graphqlRateLimitResetAt]
  end
end
