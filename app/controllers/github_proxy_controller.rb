class GithubProxyController < ApplicationController
  before_action :authenticate_request
  rescue_from StandardError, with: :handle_error

  def proxy
    path = request.path.sub('/gh/', '')
    query_string = request.query_string.present? ? "?#{request.query_string}" : ''
    full_path = "#{path}#{query_string}"
    
    api_type = if path.start_with?('search')
                 :search
               elsif path.start_with?('graphql')
                 :graphql
               else
                 :core
               end

    token = AccessToken.find_available_token(api_type)
    raise 'No available tokens' unless token

    response = token.with_lock do
      resp = token.client.get(full_path)
      token.assign_rate_limits_from_api
      token.save!
      resp.to_hash
    rescue Octokit::Error => e
      token.assign_rate_limits_from_api
      token.save!
      raise 
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
end 