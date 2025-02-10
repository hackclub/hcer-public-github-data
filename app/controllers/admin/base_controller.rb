module Admin
  class BaseController < ApplicationController
    before_action :authenticate

    private

    def authenticate
      authenticate_or_request_with_http_basic do |username, password|
        # Username can be anything, password must match proxy_api_key
        password == Rails.application.credentials.proxy_api_key
      end
    end
  end
end 