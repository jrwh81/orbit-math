class AddTimerToGameSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :game_sessions, :time_limit_seconds, :integer, null: false, default: 90
    remove_column :game_sessions, :claim_goal, :integer, default: 8
  end
end
