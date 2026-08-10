class AddRotationToGameSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :game_sessions, :active_targets, :jsonb, null: false, default: []
    add_column :game_sessions, :claim_goal, :integer, null: false, default: 8
  end
end
