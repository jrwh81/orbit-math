Rails.application.routes.draw do
  root "home#index"

  get  "signup", to: "registrations#new"
  post "signup", to: "registrations#create"
  get  "login",  to: "sessions#new"
  post "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  # Single player
  resources :solo_games, only: [:new, :create, :show] do
    member { post :finish }
    resources :moves, only: [:create], controller: "moves", defaults: { mode: "solo" }
  end

  # Multiplayer lobby (host / join) + live game
  resources :multiplayer_games, only: [:index, :create, :show], path: "multiplayer" do
    member do
      post :start
      post :finish
    end
    resources :moves, only: [:create], controller: "moves", defaults: { mode: "multiplayer" }
  end
  post "multiplayer/join", to: "multiplayer_games#join", as: :join_multiplayer_game

  get "leaderboard", to: "leaderboard#index"

  namespace :admin do
    root to: "dashboard#index"
    resources :users, only: [:index, :show]
    resources :game_sessions, only: [:index, :show]
  end

  # Health check for load balancers / app store review environments
  get "up" => "rails/health#show", as: :rails_health_check

  mount ActionCable.server => "/cable"
end
