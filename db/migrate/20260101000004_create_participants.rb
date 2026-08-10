class CreateParticipants < ActiveRecord::Migration[7.1]
  def change
    create_table :participants do |t|
      t.references :game_session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :player_number, null: false, default: 1
      t.integer :score, null: false, default: 0

      t.timestamps
    end

    add_index :participants, [:game_session_id, :user_id], unique: true
    add_index :participants, [:game_session_id, :player_number], unique: true
  end
end
