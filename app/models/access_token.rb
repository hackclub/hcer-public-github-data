class AccessToken < ApplicationRecord
  # Validations
  validates :gh_id, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true
  validates :access_token, presence: true

  # Scopes for finding available tokens
  scope :active, -> { where(revoked_at: nil) }
  scope :with_core_capacity, -> { active.where('core_rate_limit_remaining > ? OR core_rate_limit_reset_at < ?', 0, Time.current) }
  scope :with_search_capacity, -> { active.where('search_rate_limit_remaining > ? OR search_rate_limit_reset_at < ?', 0, Time.current) }
  scope :with_graphql_capacity, -> { active.where('graphql_rate_limit_remaining > ? OR graphql_rate_limit_reset_at < ?', 0, Time.current) }
  
  # Find a token with available capacity for the given API type
  def self.find_available_token(api_type = :core)
    case api_type
    when :core
      with_core_capacity.order('core_rate_limit_remaining DESC NULLS LAST, last_used_at ASC NULLS FIRST').first
    when :search
      with_search_capacity.order('search_rate_limit_remaining DESC NULLS LAST, last_used_at ASC NULLS FIRST').first
    when :graphql
      with_graphql_capacity.order('graphql_rate_limit_remaining DESC NULLS LAST, last_used_at ASC NULLS FIRST').first
    end
  end

  # Fetch and assign rate limits from GitHub API response (does not save to database)
  def assign_rate_limits_from_api
    rest_limits = client.get('/rate_limit')
    
    rate_limits = {
      core_rate_limit_remaining: rest_limits.resources.core&.remaining,
      core_rate_limit_reset_at: rest_limits.resources.core&.reset && Time.at(rest_limits.resources.core.reset),
      search_rate_limit_remaining: rest_limits.resources.search&.remaining, 
      search_rate_limit_reset_at: rest_limits.resources.search&.reset && Time.at(rest_limits.resources.search.reset),
      graphql_rate_limit_remaining: rest_limits.resources.graphql&.remaining,
      graphql_rate_limit_reset_at: rest_limits.resources.graphql&.reset && Time.at(rest_limits.resources.graphql.reset)
    }

    assign_attributes(rate_limits)
    rate_limits
  end

  # Create an Octokit client with this token
  def client
    raise Error, "Cannot use revoked token" if revoked?
    self.last_used_at = Time.current
    @client ||= Octokit::Client.new(access_token: access_token)
  end

  # Check if the token has capacity for a given API type
  def has_capacity?(api_type = :core)
    return false if revoked?

    case api_type
    when :core
      core_rate_limit_remaining.to_i > 0 || (core_rate_limit_reset_at && core_rate_limit_reset_at < Time.current)
    when :search
      search_rate_limit_remaining.to_i > 0 || (search_rate_limit_reset_at && search_rate_limit_reset_at < Time.current)
    when :graphql
      graphql_rate_limit_remaining.to_i > 0 || (graphql_rate_limit_reset_at && graphql_rate_limit_reset_at < Time.current)
    end
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
