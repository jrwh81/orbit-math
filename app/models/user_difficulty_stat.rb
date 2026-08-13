class UserDifficultyStat < ApplicationRecord
  belongs_to :user

  validates :difficulty, inclusion: { in: PuzzleGenerator::DIFFICULTY_LEVELS.keys }
  validates :user_id, uniqueness: { scope: :difficulty }

  # The single place that rolls a completed GameSession into per-
  # difficulty stats -- used by GameCompletionService for every game
  # going forward, AND by the CreateUserDifficultyStats migration to
  # backfill history from games that completed before this table
  # existed. Keeping it in one place means the backfill and live
  # gameplay can never drift out of sync with each other.
  def self.record_completed_game!(game_session)
    difficulty = game_session.puzzle&.difficulty
    return unless PuzzleGenerator::DIFFICULTY_LEVELS.key?(difficulty)

    winner = game_session.multiplayer? ? game_session.winner : nil

    game_session.users.each do |user|
      claimed = game_session.targets_claimed_by(user)
      points = game_session.points_for(user)

      stat = find_or_create_by!(user_id: user.id, difficulty: difficulty)
      stat.games_played += 1
      stat.targets_claimed += claimed
      stat.total_points += points

      if game_session.solo?
        stat.best_solo_score = [stat.best_solo_score, points].max
        stat.games_won += 1
      elsif winner && winner.id == user.id
        stat.games_won += 1
      end

      stat.save!
    end
  end

  def difficulty_label
    PuzzleGenerator::DIFFICULTY_LEVELS.dig(difficulty, :label) || difficulty.to_s.capitalize
  end

  def win_rate
    return 0.0 if games_played.zero?

    (games_won.to_f / games_played * 100).round(1)
  end
end
