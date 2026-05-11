GoodJob::Engine.middleware.use(Rack::Auth::Basic) do |username, password|
  proxy_api_key = ENV["PROXY_API_KEY"].presence || Rails.application.credentials.proxy_api_key
  proxy_api_key.present? && ActiveSupport::SecurityUtils.secure_compare(proxy_api_key, password)
end
