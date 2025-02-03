class ConvertAccessTokenFieldsToSnakeCase < ActiveRecord::Migration[8.0]
  def change
    rename_column :access_tokens, :ghId, :gh_id
    rename_column :access_tokens, :accessToken, :access_token
    rename_column :access_tokens, :lastUsedAt, :last_used_at
    rename_column :access_tokens, :coreRateLimitRemaining, :core_rate_limit_remaining
    rename_column :access_tokens, :coreRateLimitResetAt, :core_rate_limit_reset_at
    rename_column :access_tokens, :searchRateLimitRemaining, :search_rate_limit_remaining
    rename_column :access_tokens, :searchRateLimitResetAt, :search_rate_limit_reset_at
    rename_column :access_tokens, :graphqlRateLimitRemaining, :graphql_rate_limit_remaining
    rename_column :access_tokens, :graphqlRateLimitResetAt, :graphql_rate_limit_reset_at
  end
end
