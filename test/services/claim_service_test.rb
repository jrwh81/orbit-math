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

  test "points_for_value follows the correct tier boundaries -- shared with the material tier visuals" do
    # These breakpoints (10, 20, 50, 150) MUST match grid_controller.js's
    # materialTierClass exactly, since the point value and the visual
    # rarity (crystal/gold/emerald/platinum/diamond) are meant to always
    # agree. Checked at every boundary, not just one value per tier.
    assert_equal 25, ClaimService.points_for_value(1)
    assert_equal 25, ClaimService.points_for_value(10)
    assert_equal 50, ClaimService.points_for_value(11)
    assert_equal 50, ClaimService.points_for_value(20)
    assert_equal 100, ClaimService.points_for_value(21)
    assert_equal 100, ClaimService.points_for_value(50)
    assert_equal 250, ClaimService.points_for_value(51)
    assert_equal 250, ClaimService.points_for_value(150)
    assert_equal 500, ClaimService.points_for_value(151)
    assert_equal 500, ClaimService.points_for_value(500)
  end

  test "a successful claim stores the correct tiered points on the claim record, not a flat difficulty rate" do
    user = User.create!(username: "cs_points", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 45)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    result = ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
    assert result.success?

    game_session.reload
    stored_points = game_session.claims[target["id"]]["points"]
    assert_equal ClaimService.points_for_value(target["value"]), stored_points
    assert_equal stored_points, game_session.points_for(user)
  end

  test "claimed points always match one of the five real tiers, driven by the target's actual value" do
    user = User.create!(username: "cs_varied_points", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "expert", seed: 46) # widest value range in the game
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    5.times do
      game_session.reload
      target = game_session.active_targets.find { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
      break unless target

      path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
      result = ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
      next unless result.success?

      game_session.reload
      stored_points = game_session.claims[target["id"]]["points"]
      assert_includes [25, 50, 100, 250, 500], stored_points
      assert_equal ClaimService.points_for_value(target["value"]), stored_points,
                   "claimed target worth #{target["value"]} should earn exactly #{ClaimService.points_for_value(target["value"])} points"
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

    starting_count = game_session.active_targets.size

    20.times do
      game_session.reload
      target = game_session.active_targets.find { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
      break unless target # only true if something is fundamentally broken -- assertion below will catch it

      path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
      result = ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
      assert result.success?, "expected target #{target["value"]} to be claimable: #{result.message}"

      game_session.reload
      assert_equal starting_count, game_session.active_targets.size,
                   "active target list shrank -- a claim should always replace itself with a new target"

      ids = game_session.active_targets.map { |t| t["id"] }
      assert_equal ids.uniq.size, ids.size,
                   "found duplicate target ids -- this is the actual root cause that shrinks the list on a later claim"

      unsolvable = game_session.active_targets.reject { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
      assert unsolvable.empty?,
             "found unsolvable target(s) after a claim -- the repair mechanism should prevent this: #{unsolvable.inspect}"
    end
  end

  test "regression: a claim that also triggers a repair issues no duplicate target ids" do
    # This is the actual root cause, tested directly rather than just
    # via its downstream symptom (the list shrinking): next_target_id
    # used to be a derived formula ("claims.size + active_targets.size + 1")
    # that implicitly assumed exactly one new id gets issued per claim.
    # A claim that ALSO triggers a repair (see
    # ClaimService#repair_invalidated_targets) issues a SECOND new id in
    # that same pass, which the old formula had no way to account for --
    # the next claim would recompute the same "next" id and collide with
    # one already sitting in active_targets. Claiming either target
    # sharing that id then removed BOTH via `reject`, silently shrinking
    # the list by an extra slot. Beginner's small board makes repairs
    # (and therefore this collision) common enough to hit reliably
    # across a handful of seeds.
    [10, 20, 30, 40, 50].each do |seed|
      user = User.create!(username: "cs_id_collision_#{seed}", password: "password123")
      puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: seed * 777)
      game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
      game_session.participants.create!(user: user, player_number: 1)

      20.times do
        game_session.reload
        target = game_session.active_targets.find { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
        break unless target

        path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
        ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])

        game_session.reload
        ids = game_session.active_targets.map { |t| t["id"] }
        assert_equal ids.uniq.size, ids.size, "seed #{seed}: duplicate target id found after a claim"
      end
    end
  end

  test "regression: Beginner's small addition-only board never lets the active list shrink" do
    # This is the exact scenario that surfaced a real bug: add_target's
    # "avoid duplicate values" preference was a hard requirement, and
    # Beginner's tiny addition-only 4x4 board can run out of genuinely
    # NEW values well before it runs out of valid chains -- causing
    # add_target to return nil and the active list to silently shrink
    # by one, permanently. Runs enough claims, across enough different
    # seeds, to catch a regression rather than getting lucky on one seed.
    [1, 2, 3, 4, 5].each do |seed|
      user = User.create!(username: "cs_beginner_shrink_#{seed}", password: "password123")
      puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: seed * 1000)
      game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
      game_session.participants.create!(user: user, player_number: 1)

      starting_count = game_session.active_targets.size

      15.times do
        game_session.reload
        target = game_session.active_targets.find { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
        break unless target

        path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
        ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
      end

      game_session.reload
      assert_equal starting_count, game_session.active_targets.size,
                   "seed #{seed}: active target list shrank on Beginner difficulty"
    end
  end
end
