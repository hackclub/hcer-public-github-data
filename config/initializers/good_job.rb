GoodJob::Engine.middleware.use(Rack::Auth::Basic) do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(Rails.application.credentials.proxy_api_key, password)
end