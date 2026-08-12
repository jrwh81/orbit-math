# Serializes a GameSession into the exact JSON shape the front-end grid
# controller expects. Used for the initial page render (embedded as JSON
# in the view), MovesController's fetch responses, and every ActionCable
# broadcast -- so the client-side rendering logic only needs one code path.
class GameStatePresenter
  def initialize(game_session)
    @game_session = game_session
  end

  def as_json(*)
    {
      id: @game_session.id,
      mode: @game_session.mode,
      status: @game_session.status,
      join_code: @game_session.join_code,
      grid: @game_session.active_grid,
      targets: targets_json,
      players: players_json,
      claims_count: @game_session.claims.size,
      time_limit_seconds: @game_session.time_limit_seconds,
      time_remaining_seconds: @game_session.time_remaining_seconds,
      winner_id: @game_session.completed? ? @game_session.winner&.id : nil,
      summary: @game_session.completed? ? summary_json : nil
    }
  end

  private

  # Targets rotate the instant they're claimed rather than sitting there
  # marked "claimed", so this is just the current live list -- no
  # claimed/claimed_by flags needed here anymore (see CHANGELOG for why).
  def targets_json
    @game_session.active_targets.map do |t|
      { id: t["id"], value: t["value"] }
    end
  end

  def players_json
    @game_session.participants.includes(:user).order(:player_number).map do |p|
      {
        user_id: p.user_id,
        name: p.user.name,
        player_number: p.player_number,
        points: @game_session.points_for(p.user),
        claims: @game_session.targets_claimed_by(p.user)
      }
    end
  end

  # Per-user "how you did this round" numbers for the end-of-round
  # summary screen, keyed by user id so the client can look up "mine"
  # regardless of whether this is a solo or multiplayer session.
  def summary_json
    @game_session.users.each_with_object({}) do |user, acc|
      acc[user.id] = {
        points: @game_session.points_for(user),
        claims: @game_session.targets_claimed_by(user),
        longest_chain: @game_session.longest_chain_for(user),
        highest_value: @game_session.highest_value_claimed_by(user)
      }
    end
  end
end
