# Allow both GET and POST for auth callback
OmniAuth.config.allowed_request_methods = [:post, :get]

Rails.application.config.after_initialize do
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :github,
      Rails.application.credentials.github.client_id,
      Rails.application.credentials.github.client_secret,
      scope: 'repo,read:org,read:user'
  end
end 