require "test_helper"

class ChainEvaluatorTest < ActiveSupport::TestCase
  SAMPLE_GRID = [
    [3, 5, 2],
    [1, 4, 9],
    [7, 6, 8]
  ].freeze

  test "adds left to right for + links" do
    result = ChainEvaluator.call(grid: SAMPLE_GRID, coords: [[0, 0], [0, 1]], ops: ["+"])
    assert result.valid?
    assert_equal 8, result.value # 3 + 5
  end

  test "multiplies for * links" do
    result = ChainEvaluator.call(grid: SAMPLE_GRID, coords: [[0, 0], [0, 1]], ops: ["*"])
    assert result.valid?
    assert_equal 15, result.value # 3 * 5
  end

  test "evaluates strictly left to right, not by operator precedence" do
    # drawn as 3 -> (+) -> 5 -> (x) -> 2, this is (3 + 5) * 2 = 16, NOT 3 + 10 = 13
    result = ChainEvaluator.call(grid: SAMPLE_GRID, coords: [[0, 0], [0, 1], [0, 2]], ops: ["+", "*"])
    assert result.valid?
    assert_equal 16, result.value
  end

  test "allows diagonal adjacency" do
    result = ChainEvaluator.call(grid: SAMPLE_GRID, coords: [[0, 0], [1, 1]], ops: ["+"])
    assert result.valid?
    assert_equal 7, result.value # 3 + 4
  end

  test "rejects a chain shorter than 2 cells" do
    refute ChainEvaluator.call(grid: SAMPLE_GRID, coords: [[0, 0]], ops: []).valid?
  end

  test "rejects a mismatched number of operators" do
    refute ChainEvaluator.call(grid: SAMPLE_GRID, coords: [[0, 0], [0, 1], [0, 2]], ops: ["+"]).valid?
  end

  test "rejects non-adjacent links" do
    refute ChainEvaluator.call(grid: SAMPLE_GRID, coords: [[0, 0], [2, 2]], ops: ["+"]).valid?
  end

  test "rejects reusing the same cell twice" do
    refute ChainEvaluator.call(grid: SAMPLE_GRID, coords: [[0, 0], [0, 1], [0, 0]], ops: ["+", "+"]).valid?
  end

  test "rejects out of bounds coordinates" do
    refute ChainEvaluator.call(grid: SAMPLE_GRID, coords: [[0, 0], [9, 9]], ops: ["+"]).valid?
  end

  test "rejects an unknown operator" do
    refute ChainEvaluator.call(grid: SAMPLE_GRID, coords: [[0, 0], [0, 1]], ops: ["/"]).valid?
  end
end
