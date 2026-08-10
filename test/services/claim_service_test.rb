require "test_helper"

class ClaimServiceTest < ActiveSupport::TestCase
  test "a successful claim regenerates every cell in the winning chain to a different value" do
    user = User.create!(username: "cs_regen", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 42)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    old_values = path[:coords].map { |(r, c)| game_session.active_grid[r][c] }

    result = ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
    assert result.success?

    game_session.reload
    new_values = path[:coords].map { |(r, c)| game_session.active_grid[r][c] }

    old_values.zip(new_values).each_with_index do |(old_val, new_val), i|
      refute_equal old_val, new_val, "expected cell #{path[:coords][i]} to have a new value after being claimed"
    end
  end

  test "cells NOT part of the winning chain are left untouched" do
    user = User.create!(username: "cs_untouched", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "advanced", seed: 43) # bigger board, more untouched cells to check
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    grid_before = game_session.active_grid.map(&:dup)
    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    touched = path[:coords].map { |(r, c)| [r, c] }

    ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
    game_session.reload

    grid_before.each_with_index do |row, r|
      row.each_index do |c|
        next if touched.include?([r, c])

        assert_equal grid_before[r][c], game_session.active_grid[r][c],
                     "cell [#{r},#{c}] wasn't part of the winning chain and should be unchanged"
      end
    end
  end

  test "every remaining active target stays solvable after many claims, even as cells regenerate and overlap" do
    # Beginner's small 4x4 board makes cell overlap between different
    # targets common, so this is exactly the scenario most likely to
    # expose a broken repair mechanism if one existed.
    user = User.create!(username: "cs_invariant", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 44)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    20.times do
      game_session.reload
      target = game_session.active_targets.find { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
      break unless target # only true if something is fundamentally broken -- assertion below will catch it

      path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
      result = ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
      assert result.success?, "expected target #{target["value"]} to be claimable: #{result.message}"

      game_session.reload
      unsolvable = game_session.active_targets.reject { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
      assert unsolvable.empty?,
             "found unsolvable target(s) after a claim -- the repair mechanism should prevent this: #{unsolvable.inspect}"
    end
  end
end
