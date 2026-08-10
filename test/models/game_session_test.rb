require "test_helper"

class GameSessionTest < ActiveSupport::TestCase
  test "creating a game session auto-initializes active_targets and time_limit_seconds from its puzzle" do
    user = User.create!(username: "gs_init", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 1)

    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)

    assert_equal puzzle.targets.size, game_session.active_targets.size
    assert_equal puzzle.targets.map { |t| t["value"] }, game_session.active_targets.map { |t| t["value"] }
    assert_equal PuzzleGenerator::DIFFICULTY_LEVELS.dig("beginner", :time_limit_seconds), game_session.time_limit_seconds
  end

  test "next_target_id increments monotonically as claims accumulate and the active list stays constant size" do
    user = User.create!(username: "gs_ids", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 2)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    starting_ids = game_session.active_targets.map { |t| t["id"] }
    assert_equal starting_ids.size, starting_ids.uniq.size, "initial target ids should already be unique"

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    result = ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
    assert result.success?

    game_session.reload
    new_ids = game_session.active_targets.map { |t| t["id"] }
    assert_equal starting_ids.size, new_ids.size
    refute_includes new_ids, target["id"], "the claimed id should be gone"
    assert_equal new_ids.size, new_ids.uniq.size, "ids should stay unique after rotation"
  end

  test "time_expired? is false right after creation and true once time travels past the limit" do
    user = User.create!(username: "gs_solo_timer", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 3)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user, time_limit_seconds: 30)
    game_session.participants.create!(user: user, player_number: 1)

    refute game_session.time_expired?
    # assert_in_delta, not exact equality: real wall-clock time elapses
    # during test execution between started_at being set and this
    # assertion running, and time_remaining_seconds floors to a whole
    # second, so this can legitimately read a second or two under 30
    # even "immediately" after creation.
    assert_in_delta 30, game_session.time_remaining_seconds, 2

    travel_to(game_session.started_at + 31) do
      assert game_session.time_expired?
      assert_equal 0, game_session.time_remaining_seconds
    end
  end

  test "time_expired? is always false once the game is completed, regardless of the clock" do
    user = User.create!(username: "gs_completed_timer", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 4)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user, time_limit_seconds: 30)
    game_session.participants.create!(user: user, player_number: 1)

    GameCompletionService.call(game_session)

    travel_to(game_session.started_at + 999) do
      refute game_session.time_expired?, "a completed game is never 'expired' -- it's just done"
      assert_equal 0, game_session.time_remaining_seconds
    end
  end

  test "longest_chain_for and highest_value_claimed_by reflect only this user's successful claims" do
    p1 = User.create!(username: "gs_stats1", password: "password123")
    p2 = User.create!(username: "gs_stats2", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "advanced", seed: 5) # allows chains up to length 4
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: p1, started_at: Time.current
    )
    game_session.participants.create!(user: p1, player_number: 1)
    game_session.participants.create!(user: p2, player_number: 2)

    assert_equal 0, game_session.longest_chain_for(p1)
    assert_equal 0, game_session.highest_value_claimed_by(p1)

    longest_seen = 0
    highest_value_seen = 0

    4.times do
      game_session.reload
      target = game_session.active_targets.find { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
      break unless target

      path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
      result = ClaimService.call(game_session: game_session, user: p1, coords: path[:coords], ops: path[:ops])
      next unless result.success?

      longest_seen = [longest_seen, path[:coords].size].max
      highest_value_seen = [highest_value_seen, target["value"]].max
    end

    game_session.reload
    assert_equal longest_seen, game_session.longest_chain_for(p1)
    assert_equal highest_value_seen, game_session.highest_value_claimed_by(p1)

    # p2 never claimed anything, so their numbers should stay at zero
    # even though the game_session itself now has plenty of claims on it
    assert_equal 0, game_session.longest_chain_for(p2)
    assert_equal 0, game_session.highest_value_claimed_by(p2)
  end
end
