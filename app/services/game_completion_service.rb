# Finalizes a GameSession once the clock runs out (or a host ends it
# early) and rolls the results into each player's UserStat.
class GameCompletionService
  def self.call(game_session)
    new(game_session).call
  end

  def initialize(game_session)
    @game_session = game_session
  end

  def call
    return if @game_session.completed?

    @game_session.update!(status: :completed, ended_at: Time.current)
    winner = @game_session.winner

    @game_session.users.each do |user|
      stat = user.stat
      claimed = @game_session.targets_claimed_by(user)
      points = @game_session.points_for(user)

      stat.games_played += 1
      stat.targets_claimed += claimed
      stat.total_score += points

      if @game_session.solo?
        # Solo is a timed practice run, not pass/fail -- every completed
        # round counts as a "win" for streak/stat purposes; the real
        # measure of how you did is best_solo_score.
        stat.best_solo_score = [stat.best_solo_score, points].max
        stat.games_won += 1
      elsif winner && winner.id == user.id
        stat.games_won += 1
      end

      stat.save!
    end

    @game_session
  end
end
