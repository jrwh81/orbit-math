require "test_helper"

class PuzzleGeneratorTest < ActiveSupport::TestCase
  test "generates a grid of the requested size filled with digits 1-9" do
    puzzle = PuzzleGenerator.call(size: 8, target_count: 8, seed: 42)

    assert_equal 8, puzzle.grid.size
    puzzle.grid.each do |row|
      assert_equal 8, row.size
      row.each { |value| assert_includes(1..9, value) }
    end
  end

  test "every generated target is actually solvable on its own grid" do
    puzzle = PuzzleGenerator.call(size: 8, target_count: 8, seed: 7)

    puzzle.targets.each do |target|
      path = PuzzleSolver.find_path_for(puzzle.grid, target["value"])
      assert path, "expected a solvable chain for target value #{target["value"]}"
    end
  end

  test "is deterministic for a given seed" do
    a = PuzzleGenerator.call(size: 8, target_count: 8, seed: 999)
    b = PuzzleGenerator.call(size: 8, target_count: 8, seed: 999)

    assert_equal a.grid, b.grid
    assert_equal a.targets.map { |t| t["value"] }, b.targets.map { |t| t["value"] }
  end

  test "produces different grids for different seeds" do
    a = PuzzleGenerator.call(size: 8, target_count: 8, seed: 1)
    b = PuzzleGenerator.call(size: 8, target_count: 8, seed: 2)

    refute_equal a.grid, b.grid
  end

  test "auto-generated seed (no seed: passed) fits in a Postgres integer column" do
    # Regression test: Random.new_seed can return numbers far larger than
    # a 4-byte Postgres `integer` column can hold, which blew up as
    # "X is out of range for ActiveModel::Type::Integer with limit 4 bytes"
    # the moment someone clicked "Play Solo" (no explicit seed passed).
    puzzle = PuzzleGenerator.call(size: 8, target_count: 8)

    assert puzzle.persisted?
    assert puzzle.seed.between?(0, 2_147_483_647)
  end

  test "digit distribution across the board is balanced, not clumpy" do
    # With a proper 1-9 "bag" shuffle, a 5x5 board (25 cells) should draw
    # from roughly 2-3 full cycles of 1-9, so no single digit should be
    # wildly over- or under-represented purely by chance. A naive
    # independent rand() per cell has no such guarantee and can (rarely
    # but really) produce e.g. eight 7s and zero 2s on a 25-cell board.
    puzzle = PuzzleGenerator.call(size: 5, target_count: 6, seed: 12_345)

    counts = Hash.new(0)
    puzzle.grid.flatten.each { |v| counts[v] += 1 }

    (1..9).each do |digit|
      assert counts.key?(digit), "expected digit #{digit} to appear at least once on the board"
    end

    # 25 cells / 9 digits ~= 2.8 average appearances per digit; a bag
    # shuffle should keep every digit within a tight band of that.
    counts.each_value do |count|
      assert count.between?(1, 5), "expected a balanced spread, got counts: #{counts}"
    end
  end

  test "target chain lengths are mixed, not all the same length by chance" do
    # Explicit difficulty: beginner forces every chain to exactly length 2
    # by design (that's the whole point of the easiest tier), so a test
    # that wants to see length VARIETY needs a tier that actually allows
    # it -- "expert" allows 2-4.
    puzzle = PuzzleGenerator.call(difficulty: "expert", target_count: 9, seed: 55_555)

    lengths = puzzle.targets.map { |t| t["length"] }.uniq
    assert lengths.size > 1, "expected a mix of chain lengths across targets, got all length #{lengths.first}"
  end

  test "digit bag produces the same balanced sequence for the same seed" do
    a = PuzzleGenerator.call(size: 5, target_count: 6, seed: 777)
    b = PuzzleGenerator.call(size: 5, target_count: 6, seed: 777)

    assert_equal a.grid, b.grid
  end

  test "beginner difficulty produces a 4x4 board with only 2-cell chains under 20" do
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 111)

    assert_equal 4, puzzle.size
    assert_equal "beginner", puzzle.difficulty

    puzzle.targets.each do |target|
      assert_equal 2, target["length"], "beginner chains should always be exactly 2 cells"
      assert target["value"] <= 20, "beginner target #{target["value"]} exceeds the 1-20 range"

      path = PuzzleSolver.find_path_for(puzzle.grid, target["value"], max_length: 2)
      assert path, "expected a 2-cell chain for beginner target #{target["value"]}"
    end
  end

  test "beginner difficulty is configured to never require multiplication" do
    # This checks the actual design decision directly rather than trying
    # to prove it by brute-force searching a generated board -- a board
    # can coincidentally contain an unrelated pair of cells whose PRODUCT
    # also happens to match some target value even when the target was
    # constructed additively, which would make a "no multiply solution
    # exists anywhere on this board" assertion flaky rather than meaningful.
    assert_equal 0.0, PuzzleGenerator::DIFFICULTY_LEVELS.dig("beginner", :multiply_probability)
  end

  test "each difficulty level enforces its own value ceiling" do
    PuzzleGenerator::DIFFICULTY_LEVELS.each do |key, preset|
      puzzle = PuzzleGenerator.call(difficulty: key, seed: 2468)

      assert_equal preset[:size], puzzle.size
      puzzle.targets.each do |target|
        assert target["value"] <= preset[:max_target_value],
               "#{key} target #{target["value"]} exceeds its #{preset[:max_target_value]} ceiling"
        assert target["length"].between?(preset[:min_chain_length], preset[:max_chain_length])
      end
    end
  end

  test "an unknown difficulty string falls back to the default instead of raising" do
    puzzle = PuzzleGenerator.call(difficulty: "nonsense", seed: 1)

    assert_equal PuzzleGenerator::DEFAULT_DIFFICULTY, puzzle.difficulty
  end

  test "explicit size:/target_count: still override the difficulty preset's defaults" do
    puzzle = PuzzleGenerator.call(difficulty: "beginner", size: 6, target_count: 3, seed: 9)

    assert_equal 6, puzzle.size
    assert_equal 3, puzzle.targets.size
    # chain length / value ceiling still come from the beginner preset
    puzzle.targets.each { |t| assert_equal 2, t["length"] }
  end

  test "add_target generates one more solvable target on an already-complete grid without touching cell values" do
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 20)
    grid_before = puzzle.grid.map(&:dup)

    new_target = PuzzleGenerator.add_target(grid: puzzle.grid, difficulty: "beginner", id: "t99")

    assert new_target, "expected a new target to be generated"
    assert_equal "t99", new_target["id"]
    assert new_target["value"] <= 20, "beginner rotation target should still respect the value ceiling"
    assert_equal grid_before, puzzle.grid, "add_target must never mutate existing cell values"

    path = PuzzleSolver.find_path_for(puzzle.grid, new_target["value"])
    assert path, "the newly rotated-in target should be solvable on the existing grid"
  end

  test "add_target prefers avoiding a duplicate value, but falls back to any solvable chain rather than returning nil" do
    # This is the inverse of the old (buggy) expectation: when every
    # possible value is "already showing" (impossible to truly avoid a
    # duplicate), add_target must still succeed by falling back to
    # accepting a duplicate value -- returning nil here is exactly the
    # bug that let the active target list silently shrink on Beginner's
    # small addition-only board. Duplicate target values are allowed by
    # design; failing to find a replacement at all is not.
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 21)
    existing_values = (1..20).to_a # deliberately excludes every possible beginner value

    new_target = PuzzleGenerator.add_target(
      grid: puzzle.grid, difficulty: "beginner", id: "t99", existing_values: existing_values
    )

    refute_nil new_target, "add_target should always find SOME solvable chain, even if it must duplicate a value"
    assert new_target["value"] <= 20
    assert PuzzleSolver.find_path_for(puzzle.grid, new_target["value"])
  end
end
