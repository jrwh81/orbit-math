class AddGuestToUsers < ActiveRecord::Migration[7.1]
  def change
    # Marks accounts created through the no-signup "Play a Game" flow
    # (see GuestPlayController) -- same User model, same leaderboard,
    # same everything else, just flagged so admin can tell guest
    # walk-up plays apart from real signups at a glance.
    add_column :users, :guest, :boolean, null: false, default: false
    add_index :users, :guest

    # Whether this guest has replaced their auto-generated placeholder
    # name ("Guest48213") with one they actually chose -- see
    # UsersController#claim_name, prompted via a modal right after their
    # game ends (see grid_controller.js#celebrateCompletion). Once true,
    # they don't get nagged with that prompt again on future rounds.
    add_column :users, :name_claimed, :boolean, null: false, default: false
  end
end
