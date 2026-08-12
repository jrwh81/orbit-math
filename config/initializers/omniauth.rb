# Google/Facebook sign-in. Requires real credentials from each
# provider's developer console -- see OAUTH.md for the full external
# setup walkthrough. Locally these read from .env (via dotenv-rails,
# already in the Gemfile); in production, set them with `heroku config:set`.
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           ENV["GOOGLE_CLIENT_ID"],
           ENV["GOOGLE_CLIENT_SECRET"],
           scope: "email,profile",
           prompt: "select_account"

  provider :facebook,
           ENV["FACEBOOK_APP_ID"],
           ENV["FACEBOOK_APP_SECRET"],
           scope: "email"
end

# omniauth-rails_csrf_protection (in the Gemfile) makes the request
# phase (/auth/:provider) POST-only for CSRF safety -- the sign-in
# buttons must be button_to/forms, not plain links. This just documents
# that requirement; the gem enforces it automatically once loaded.

OmniAuth.config.logger = Rails.logger

# Don't let a provider outage/misconfiguration raise a raw 500 -- send
# the user to the friendly failure route instead (see routes.rb).
OmniAuth.config.on_failure = proc do |env|
  OmniauthCallbacksController.action(:failure).call(env)
end
