class UsersController < ApplicationController
  before_action :require_login

  # PATCH /demo_mode
  #
  # Toggles demo-mode on/off for the CURRENT user. This is a user-level
  # preference (not tied to any one game session) so switching it off --
  # whether from the checkbox during play or from the "turn it off"
  # button on the post-demo congrats screen -- sticks for every future
  # solo run, not just the one in progress. Called via fetch from
  # demo_controller.js; responds with the new state so the client never
  # has to guess whether the write actually landed.
  def update_demo_mode
    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    current_user.update!(demo_mode_enabled: enabled)
    render json: { demo_mode_enabled: current_user.demo_mode_enabled }
  end

  # PATCH /claim_name
  #
  # Lets a guest (see GuestPlayController) swap their auto-generated
  # placeholder name for one they actually chose, and optionally leave
  # an email -- prompted via a modal right after their game ends (see
  # grid_controller.js#celebrateCompletion), not before it starts, so
  # playing a first round never has any form in the way. Only ever
  # relevant for guest accounts; a real signed-up user already has a
  # name from signup and this endpoint refuses them outright rather
  # than silently letting anyone rename any account.
  def claim_name
    unless current_user.guest?
      return render json: { success: false, errors: ["not a guest account"] }, status: :forbidden
    end

    if current_user.update(username: params[:username], email: params[:email].presence, name_claimed: true)
      render json: { success: true, username: current_user.username }
    else
      render json: { success: false, errors: current_user.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
