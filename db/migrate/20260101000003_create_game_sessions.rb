class CreateGameSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :game_sessions do |t|
      t.integer :mode, null: false, default: 0        # 0 = solo, 1 = multiplayer
      t.integer :status, null: false, default: 0       # 0 = waiting, 1 = active, 2 = completed
      t.references :puzzle, null: false, foreign_key: true
      t.references :host, null: false, foreign_key: { to_table: :users }
      t.string :join_code
      t.jsonb :claims, null: false, default: {}
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end

    add_index :game_sessions, :join_code, unique: true
    add_index :game_sessions, [:mode, :status]
  end
end
