class ApplicationController < ActionController::Base
  helper_method :current_user, :logged_in?
  before_action :set_game_branding

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    return if logged_in?

    redirect_to login_path, alert: "Please log in to play."
  end

  def set_game_branding
    @game = Rails.application.config.x.game
  end
end
