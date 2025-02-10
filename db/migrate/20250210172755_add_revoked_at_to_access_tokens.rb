class AddRevokedAtToAccessTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :access_tokens, :revoked_at, :datetime
    add_index :access_tokens, :revoked_at
  end
end 