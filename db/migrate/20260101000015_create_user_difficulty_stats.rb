class CreateUserDifficultyStats < ActiveRecord::Migration[7.1]
  def up
    create_table :user_difficulty_stats do |t|
      t.references :user, null: false, foreign_key: true
      t.string :difficulty, null: false
      t.integer :games_played, null: false, default: 0
      t.integer :games_won, null: false, default: 0
      t.integer :targets_claimed, null: false, default: 0
      t.integer :total_points, null: false, default: 0
      t.integer :best_solo_score, null: false, default: 0

      t.timestamps
    end

    add_index :user_difficulty_stats, [:user_id, :difficulty], unique: true

    # Backfill from every already-completed game so the new per-difficulty
    # leaderboard reflects real history (including games played before
    # this migration existed), not just games completed from here on.
    say_with_time "Backfilling UserDifficultyStat from completed games" do
      count = 0
      GameSession.completed.includes(:puzzle, participants: :user).find_each do |game_session|
        UserDifficultyStat.record_completed_game!(game_session)
        count += 1
      end
      count
    end
  end

  def down
    drop_table :user_difficulty_stats
  end
end
