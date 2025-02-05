class GithubProxyController < ApplicationController
  before_action :authenticate_request
  rescue_from StandardError, with: :handle_error

  CACHE_VERSION = 'v1'
  CACHE_EXPIRATION = 1.day

  def proxy
    path = request.path.sub('/gh/', '')
    query_string = request.query_string.present? ? "?#{request.query_string}" : ''
    full_path = "#{path}#{query_string}"
    
    api_type = determine_api_type(path)
    cache_key = generate_cache_key(full_path, api_type)
    
    response = Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRATION) do
      token = AccessToken.find_available_token(api_type)
      raise 'No available tokens' unless token

      token.with_lock do
        resp = token.client.get(full_path)
        update_token_rate_limits(token, api_type)
        resp.to_hash
      rescue Octokit::Error => e
        token.assign_rate_limits_from_api
        token.save!
        raise 
      end
    end

    render json: response
  end

  private

  def authenticate_request
    api_key = request.headers['X-Proxy-API-Key']
    unless api_key && ActiveSupport::SecurityUtils.secure_compare(api_key, Rails.application.credentials.proxy_api_key)
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end

  def handle_error(error)
    error_response = {
      error: error.message,
      status: error.is_a?(Octokit::Error) ? error.response_status : 500
    }
    render json: error_response, status: error_response[:status]
  end

  def determine_api_type(path)
    if path.start_with?('search')
      :search
    elsif path.start_with?('graphql')
      :graphql
    else
      :core
    end
  end

  def generate_cache_key(full_path, api_type)
    key_parts = [
      'github_proxy',
      CACHE_VERSION,
      api_type,
      Digest::SHA256.hexdigest(full_path)
    ]
    key_parts.join('/')
  end

  def update_token_rate_limits(token, api_type)
    token.assign_attributes(
      "#{api_type}_rate_limit_remaining" => token.client.rate_limit.remaining,
      "#{api_type}_rate_limit_reset_at" => token.client.rate_limit.resets_at
    )
    token.save!
  end
end 