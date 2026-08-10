class AddActiveGridToGameSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :game_sessions, :active_grid, :jsonb, null: false, default: []
  end
end
