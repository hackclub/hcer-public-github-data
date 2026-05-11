module Admin
  class BaseController < ApplicationController
    before_action :authenticate

    private

    def authenticate
      proxy_api_key = ENV["PROXY_API_KEY"].presence || Rails.application.credentials.proxy_api_key

      authenticate_or_request_with_http_basic do |username, password|
        # Username can be anything, password must match proxy_api_key
        proxy_api_key.present? && ActiveSupport::SecurityUtils.secure_compare(password, proxy_api_key)
      end
    end
  end
end
