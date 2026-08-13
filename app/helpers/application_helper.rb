module ApplicationHelper
  # The Facebook credentials work fine (verified working for the app
  # owner and anyone added as a Business Manager tester), but the app
  # isn't through Meta's Business/App Review yet, so anyone who ISN'T
  # a tester hits a dead-end error straight from Facebook if they click
  # it. Hidden from public view by default until that's sorted out --
  # flip FACEBOOK_LOGIN_PUBLIC=true (env var, no code/deploy change
  # needed beyond a restart) once the app is out of Development mode.
  def facebook_login_public?
    ENV["FACEBOOK_LOGIN_PUBLIC"] == "true"
  end

  # Returns plain data describing how to display a multiplayer game's
  # result -- deliberately NOT pre-built HTML strings, so the view's
  # normal <%= %> interpolation keeps auto-escaping usernames rather
  # than a helper needing to manage html_safe/escaping itself.
  #
  # :status is one of :winner, :tie, or :in_progress -- a completed
  # game with no winner is a tie (GameSession#winner already returns
  # nil for a tie rather than picking one arbitrarily), and a game
  # that hasn't finished yet has no winner to report at all.
  def multiplayer_result(game_session, player_one, player_two)
    return nil unless player_one && player_two

    p1_points = game_session.points_for(player_one)
    p2_points = game_session.points_for(player_two)

    if game_session.completed?
      winner = game_session.winner
      if winner
        loser = winner.id == player_one.id ? player_two : player_one
        {
          status: :winner,
          winner: winner, winner_points: game_session.points_for(winner),
          loser: loser, loser_points: game_session.points_for(loser)
        }
      else
        { status: :tie, player_one: player_one, p1_points: p1_points, player_two: player_two, p2_points: p2_points }
      end
    else
      { status: :in_progress, player_one: player_one, p1_points: p1_points, player_two: player_two, p2_points: p2_points }
    end
  end
end
