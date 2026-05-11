class GithubProxyController < ApplicationController
  before_action :authenticate_request
  rescue_from StandardError, with: :handle_error

  def proxy
    path = request.path.sub("/gh/", "")
    response = GhApi::Client.request(path, request.query_parameters)
    render json: response
  end

  private

  def authenticate_request
    proxy_api_key = ENV["PROXY_API_KEY"].presence || Rails.application.credentials.proxy_api_key
    api_key = request.headers["X-Proxy-API-Key"]
    unless proxy_api_key.present? && api_key.present? && ActiveSupport::SecurityUtils.secure_compare(api_key, proxy_api_key)
      render json: { error: "Unauthorized" }, status: :unauthorized
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
