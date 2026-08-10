class CreateUserStats < ActiveRecord::Migration[7.1]
  def change
    create_table :user_stats do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.integer :games_played, null: false, default: 0
      t.integer :games_won, null: false, default: 0
      t.integer :targets_claimed, null: false, default: 0
      t.integer :total_score, null: false, default: 0
      t.integer :best_solo_score, null: false, default: 0

      t.timestamps
    end
  end
end
