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
end
