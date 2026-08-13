require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "facebook_login_public? is false when the env var is unset" do
    original = ENV.delete("FACEBOOK_LOGIN_PUBLIC")
    refute facebook_login_public?
  ensure
    ENV["FACEBOOK_LOGIN_PUBLIC"] = original
  end

  test "facebook_login_public? is false for any value other than the exact string 'true'" do
    original = ENV["FACEBOOK_LOGIN_PUBLIC"]
    ENV["FACEBOOK_LOGIN_PUBLIC"] = "yes"
    refute facebook_login_public?
  ensure
    ENV["FACEBOOK_LOGIN_PUBLIC"] = original
  end

  test "facebook_login_public? is true when the env var is exactly 'true'" do
    original = ENV["FACEBOOK_LOGIN_PUBLIC"]
    ENV["FACEBOOK_LOGIN_PUBLIC"] = "true"
    assert facebook_login_public?
  ensure
    ENV["FACEBOOK_LOGIN_PUBLIC"] = original
  end

  test "multiplayer_result returns nil when there's no second player yet" do
    user = User.create!(username: "mr_solo_only", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 700)
    game_session = GameSession.create!(mode: :multiplayer, status: :waiting, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    assert_nil multiplayer_result(game_session, user, nil)
  end

  test "multiplayer_result identifies the correct winner and loser, regardless of player order passed in" do
    p1 = User.create!(username: "mr_winner", password: "password123")
    p2 = User.create!(username: "mr_loser", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 701)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: p1, started_at: Time.current
    )
    game_session.participants.create!(user: p1, player_number: 1)
    game_session.participants.create!(user: p2, player_number: 2)

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    ClaimService.call(game_session: game_session, user: p1, coords: path[:coords], ops: path[:ops])
    GameCompletionService.call(game_session.reload)

    result = multiplayer_result(game_session, p1, p2)
    assert_equal :winner, result[:status]
    assert_equal p1, result[:winner]
    assert_equal p2, result[:loser]
    assert_equal game_session.points_for(p1), result[:winner_points]
    assert_equal game_session.points_for(p2), result[:loser_points]

    # Passing the players in the OPPOSITE order must give the identical
    # result -- who's "player one" in the argument list should never
    # affect who's actually reported as the winner.
    reversed = multiplayer_result(game_session, p2, p1)
    assert_equal result, reversed
  end

  test "multiplayer_result reports a tie when the completed game has no winner" do
    p1 = User.create!(username: "mr_tie_one", password: "password123")
    p2 = User.create!(username: "mr_tie_two", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 702)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: p1, started_at: Time.current
    )
    game_session.participants.create!(user: p1, player_number: 1)
    game_session.participants.create!(user: p2, player_number: 2)
    # No claims for either player -- 0-0 is a tie once completed.
    game_session.update!(status: :completed, ended_at: Time.current)

    result = multiplayer_result(game_session, p1, p2)
    assert_equal :tie, result[:status]
    assert_equal 0, result[:p1_points]
    assert_equal 0, result[:p2_points]
  end

  test "multiplayer_result reports in_progress for a game that hasn't completed yet, never a premature winner" do
    p1 = User.create!(username: "mr_progress_one", password: "password123")
    p2 = User.create!(username: "mr_progress_two", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 703)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: p1, started_at: Time.current
    )
    game_session.participants.create!(user: p1, player_number: 1)
    game_session.participants.create!(user: p2, player_number: 2)

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    ClaimService.call(game_session: game_session, user: p1, coords: path[:coords], ops: path[:ops])
    # Deliberately NOT completing the game -- it's still active.

    result = multiplayer_result(game_session.reload, p1, p2)
    assert_equal :in_progress, result[:status]
  end
end
