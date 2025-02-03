Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github, Rails.application.credentials.github.client_id, Rails.application.credentials.github.client_secret,
    scope: 'repo,read:org,read:user',
    provider_ignores_state: true
end

# Disable SSL verification in development
OmniAuth.config.allowed_request_methods = [:post, :get] if Rails.env.development? 