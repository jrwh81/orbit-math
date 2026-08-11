class AddNextIdSeqToGameSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :game_sessions, :next_id_seq, :integer, null: false, default: 1
  end
end
