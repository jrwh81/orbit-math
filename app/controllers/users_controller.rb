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
  # placeholder name for one they actually chose, optionally leave an
  # email, and optionally set a real password -- prompted via a modal
  # right after their game ends (see grid_controller.js#celebrateCompletion),
  # not before it starts, so playing a first round never has any form in
  # the way. Only ever relevant for guest accounts; a real signed-up
  # user already has a name (and a way to log back in) from signup, and
  # this endpoint refuses them outright rather than silently letting
  # anyone rename any account.
  #
  # The password is genuinely optional -- claiming just a name is enough
  # to show up on the leaderboard. But a guest account is created with
  # NO password at all (see GuestPlayController), so without ever
  # setting one here, there is no way for them to ever log back into
  # this account again once the session ends. Setting one is what
  # actually turns a walk-up guest into a real, durable account, so it
  # also clears the guest flag.
  def claim_name
    unless current_user.guest?
      return render json: { success: false, errors: ["not a guest account"] }, status: :forbidden
    end

    attrs = { username: params[:username], email: params[:email].presence, name_claimed: true }

    password = params[:password].presence
    attrs.merge!(password: password, guest: false) if password

    if current_user.update(attrs)
      render json: { success: true, username: current_user.username, account_created: password.present? }
    else
      render json: { success: false, errors: current_user.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
