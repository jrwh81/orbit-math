Rails.application.routes.draw do
  root "home#index"

  # No-signup quick play -- see GuestPlayController. One GET, no form:
  # clicking "Play a Game" drops you straight into a round.
  get "play", to: "guest_play#new"

  get  "signup", to: "registrations#new"
  post "signup", to: "registrations#create"
  get  "login",  to: "sessions#new"
  post "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  # OmniAuth: GET here is the request phase (redirects to Google/Facebook),
  # handled entirely by the omniauth gem's middleware -- no controller
  # action needed for it. This route just gives Rails' router (and
  # button_to in the views) a named path to point at.
  get "/auth/:provider/callback", to: "omniauth_callbacks#create"
  get "/auth/failure", to: "omniauth_callbacks#failure"

  # After a brand-new OAuth sign-in with no existing account to match,
  # the user picks a username here before an account is actually created
  # -- see OmniauthCallbacksController for why this step can't be skipped.
  get  "signup/finish", to: "omniauth_registrations#new", as: :finish_oauth_signup
  post "signup/finish", to: "omniauth_registrations#create"

  # Single player
  resources :solo_games, only: [:new, :create, :show] do
    member do
      post :finish
      get :demo_path
    end
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

  # Demo-mode is a per-USER preference (persists across every future solo
  # run, not just this one) -- see UsersController.
  patch "demo_mode", to: "users#update_demo_mode"
  # Guest post-game "claim your name for the leaderboard" prompt -- see
  # UsersController#claim_name.
  patch "claim_name", to: "users#claim_name"

  namespace :admin do
    root to: "dashboard#index"
    resources :users, only: [:index, :show]
    resources :game_sessions, only: [:index, :show]
  end

  # Health check for load balancers / app store review environments
  get "up" => "rails/health#show", as: :rails_health_check

  mount ActionCable.server => "/cable"
end
