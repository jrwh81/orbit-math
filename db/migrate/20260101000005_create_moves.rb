class CreateMoves < ActiveRecord::Migration[7.1]
  def change
    create_table :moves do |t|
      t.references :game_session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.jsonb :path, null: false, default: []
      t.jsonb :ops, null: false, default: []
      t.integer :result_value
      t.boolean :claimed, null: false, default: false
      t.string :target_id

      t.timestamps
    end

    add_index :moves, [:game_session_id, :claimed]
  end
end
