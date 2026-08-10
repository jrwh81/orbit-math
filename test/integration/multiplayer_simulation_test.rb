require "test_helper"

# Plays an entire two-player round end to end, exactly the way
# MovesController would drive it (ClaimService for every submitted
# chain), and checks that generation, evaluation, claiming, rotation,
# and stat tracking all agree with each other once the clock runs out.
class MultiplayerSimulationTest < ActiveSupport::TestCase
  test "two players build claims during a round, and time running out crowns whoever has more" do
    player_one = User.create!(username: "sim_astra", password: "password123", display_name: "Astra")
    player_two = User.create!(username: "sim_orion", password: "password123", display_name: "Orion")

    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 2026)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: player_one, started_at: Time.current
    )
    game_session.participants.create!(user: player_one, player_number: 1)
    game_session.participants.create!(user: player_two, player_number: 2)

    starting_active_count = game_session.active_targets.size

    # player_one claims 2 out of every 3 during the round -- simulates
    # being a bit faster on average without shutting player_two out.
    9.times do |i|
      game_session.reload
      target = game_session.active_targets.find { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
      assert target, "expected a solvable target on the rotating list"

      path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
      claimer = i % 3 == 2 ? player_two : player_one
      result = ClaimService.call(game_session: game_session, user: claimer, coords: path[:coords], ops: path[:ops])
      assert result.success?, "expected target #{target["value"]} to be claimable: #{result.message}"
    end

    game_session.reload
    assert_equal starting_active_count, game_session.active_targets.size,
                 "the active target list should stay a constant size the whole round -- it should never run dry"

    # Real rounds end when the clock runs out (see GameSession#time_expired?
    # and the timer-expiry test below) -- tests don't wait out a real
    # clock, so this simulates "time's up" the same way MovesController's
    # finalize_if_time_expired! does: just finalize.
    GameCompletionService.call(game_session)
    assert game_session.completed?

    winner = game_session.winner
    assert_equal player_one, winner, "player_one claimed 2/3 of targets, so should have the higher score when time runs out"

    winner.stat.reload
    assert_equal 1, winner.stat.games_won

    loser = game_session.opponent_of(winner)
    loser.stat.reload
    assert_equal 0, loser.stat.games_won
    assert loser.stat.targets_claimed.positive?, "player_two should still have claimed some targets, just fewer"

    [player_one, player_two].each { |p| assert_equal 1, p.stat.reload.games_played }
  end

  test "claiming a target removes it and rotates a fresh replacement in immediately" do
    player_one = User.create!(username: "sim_vega", password: "password123")
    player_two = User.create!(username: "sim_lyra", password: "password123")

    puzzle = PuzzleGenerator.call(difficulty: "intermediate", seed: 3033)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: player_one, started_at: Time.current
    )
    game_session.participants.create!(user: player_one, player_number: 1)
    game_session.participants.create!(user: player_two, player_number: 2)

    original_target = game_session.active_targets.first
    original_count = game_session.active_targets.size

    path = PuzzleSolver.find_path_for(game_session.active_grid, original_target["value"])
    assert path

    result = ClaimService.call(game_session: game_session, user: player_one, coords: path[:coords], ops: path[:ops])
    assert result.success?
    assert_equal original_target["id"], result.target["id"]

    game_session.reload
    assert_equal 1, game_session.claims.size
    assert_equal original_count, game_session.active_targets.size,
                 "active target list should stay the same size right after a claim"
    refute game_session.active_targets.any? { |t| t["id"] == original_target["id"] },
           "the claimed target's specific id should be gone from the active list"
  end

  test "an invalid (non-adjacent) chain is rejected without crashing the game" do
    player_one = User.create!(username: "sim_cass", password: "password123")
    player_two = User.create!(username: "sim_drac", password: "password123")

    # Explicit size: 8 here so this test's actual intent (rejecting a
    # non-adjacent chain) stays true regardless of the app's default grid
    # size -- [0,0] to [7,7] would otherwise just be out-of-bounds on a
    # smaller default board, which is also correctly rejected but for the
    # wrong reason, silently defeating the point of this test.
    puzzle = PuzzleGenerator.call(seed: 4044, size: 8)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: player_one, started_at: Time.current
    )
    game_session.participants.create!(user: player_one, player_number: 1)
    game_session.participants.create!(user: player_two, player_number: 2)

    result = ClaimService.call(game_session: game_session, user: player_one, coords: [[0, 0], [7, 7]], ops: ["+"])

    refute result.success?
    assert_equal 0, game_session.reload.claims.size
  end

  test "the round is genuinely time-limited, verified with real time travel rather than mocking" do
    player_one = User.create!(username: "sim_clock1", password: "password123")
    player_two = User.create!(username: "sim_clock2", password: "password123")

    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 7007)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: player_one, started_at: Time.current
    )
    game_session.participants.create!(user: player_one, player_number: 1)
    game_session.participants.create!(user: player_two, player_number: 2)

    refute game_session.time_expired?
    # Real wall-clock time elapses during test execution between
    # started_at being set and this assertion running, and
    # time_remaining_seconds floors to a whole second -- so this can
    # legitimately read one or two seconds under the full limit even
    # immediately "after creation". assert_in_delta, not exact equality.
    assert_in_delta game_session.time_limit_seconds, game_session.time_remaining_seconds, 2

    travel_to(game_session.started_at + (game_session.time_limit_seconds / 2)) do
      refute game_session.time_expired?, "should still be mid-round at the halfway point"
      assert game_session.time_remaining_seconds.between?(1, game_session.time_limit_seconds - 1)
    end

    travel_to(game_session.started_at + game_session.time_limit_seconds + 1) do
      assert game_session.time_expired?
      assert_equal 0, game_session.time_remaining_seconds
    end
  end
end
