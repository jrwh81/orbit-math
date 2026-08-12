# Handles the redirect back from Google/Facebook after the user
# approves sign-in. OmniAuth's middleware does all the actual OAuth
# protocol work (token exchange, fetching profile info) and hands us
# the result as request.env["omniauth.auth"] -- this controller's only
# job is deciding what to do with it.
class OmniauthCallbacksController < ApplicationController
  def create
    auth = request.env["omniauth.auth"]
    user = User.from_omniauth(auth)

    if user
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome back, #{user.name}!"
    else
      # No existing account matched (by linked identity or by email) --
      # this is a genuinely new sign-in. This app's whole design keeps
      # the username as the one thing ever shown to other players (see
      # User#name), so we can't just auto-generate one from an email
      # address and call it done -- the person needs to actually choose
      # it. Stash the verified provider data in the session (never
      # trust a hidden form field for this -- it's already been through
      # OAuth, no need to re-verify anything except the username) and
      # send them to a one-field "pick a username" form.
      session[:pending_oauth] = {
        provider: auth.provider,
        uid: auth.uid,
        email: auth.info&.email,
        first_name: auth.info&.first_name.presence || auth.info&.name.to_s.split.first,
        last_name: auth.info&.last_name.presence || auth.info&.name.to_s.split[1..].to_a.join(" ")
      }
      redirect_to finish_oauth_signup_path
    end
  end

  def failure
    redirect_to login_path, alert: "That sign-in didn't work (#{params[:message].presence || "unknown error"}). Try again, or use a username and password instead."
  end
end
