class AccessToken < ApplicationRecord
  # Validations
  validates :gh_id, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true
  validates :access_token, presence: true

  # Scopes for finding available tokens
  scope :with_core_capacity, -> { where('core_rate_limit_remaining > ? OR core_rate_limit_reset_at < ?', 0, Time.current) }
  scope :with_search_capacity, -> { where('search_rate_limit_remaining > ? OR search_rate_limit_reset_at < ?', 0, Time.current) }
  scope :with_graphql_capacity, -> { where('graphql_rate_limit_remaining > ? OR graphql_rate_limit_reset_at < ?', 0, Time.current) }
  
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

  # Update rate limits after using the token
  def update_rate_limits(core: nil, search: nil, graphql: nil)
    updates = {}
    
    if core
      updates.merge!(
        core_rate_limit_remaining: core[:remaining],
        core_rate_limit_reset_at: Time.at(core[:reset])
      )
    end

    if search
      updates.merge!(
        search_rate_limit_remaining: search[:remaining],
        search_rate_limit_reset_at: Time.at(search[:reset])
      )
    end

    if graphql
      updates.merge!(
        graphql_rate_limit_remaining: graphql[:remaining],
        graphql_rate_limit_reset_at: Time.at(graphql[:reset])
      )
    end

    updates[:last_used_at] = Time.current
    update!(updates)
  end

  # Create an Octokit client with this token
  def client
    @client ||= Octokit::Client.new(access_token: access_token)
  end

  # Check if the token has capacity for a given API type
  def has_capacity?(api_type = :core)
    case api_type
    when :core
      core_rate_limit_remaining.to_i > 0 || (core_rate_limit_reset_at && core_rate_limit_reset_at < Time.current)
    when :search
      search_rate_limit_remaining.to_i > 0 || (search_rate_limit_reset_at && search_rate_limit_reset_at < Time.current)
    when :graphql
      graphql_rate_limit_remaining.to_i > 0 || (graphql_rate_limit_reset_at && graphql_rate_limit_reset_at < Time.current)
    end
  end
end
