Rails.application.routes.draw do
  namespace :admin do
    resources :tracked_gh_users, only: [:index, :new, :create]
    root to: 'home#index'
  end

  # API routes
  namespace :api do
    get 'users/:username/days_with_commits_in_range', to: 'users#days_with_commits_in_range'
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # OAuth routes
  match '/auth/:provider/callback', to: 'sessions#create', via: [:get, :post]
  get '/auth/failure', to: 'sessions#failure'
  get '/auth/github', as: :github_login

  # GitHub API proxy route
  get '/gh/*path', to: 'github_proxy#proxy'

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"

  # Mount Good Job dashboard
  mount GoodJob::Engine => 'good_job'
end
