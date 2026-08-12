# The final step of a brand-new OAuth sign-up: the provider (Google/
# Facebook) already gave us a verified email and real name, sitting in
# session[:pending_oauth] since OmniauthCallbacksController. All that's
# left is picking a username -- the only thing this app ever shows to
# other players (see User#name) -- so it can't be skipped or
# auto-generated silently.
class OmniauthRegistrationsController < ApplicationController
  before_action :require_pending_oauth

  def new
    @user = User.new(pending_oauth_attributes)
  end

  def create
    @user = User.new(pending_oauth_attributes.merge(username: params[:user][:username]))

    if @user.save(context: :signup)
      session.delete(:pending_oauth)
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Welcome, #{@user.name}!"
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def require_pending_oauth
    redirect_to signup_path, alert: "Start with Google or Facebook sign-in first." unless session[:pending_oauth]
  end

  def pending_oauth_attributes
    session[:pending_oauth].symbolize_keys
  end
end
