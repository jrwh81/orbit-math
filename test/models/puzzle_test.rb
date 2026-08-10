require "test_helper"

class PuzzleTest < ActiveSupport::TestCase
  test "rejects a difficulty outside the known set at the model level" do
    puzzle = Puzzle.new(size: 5, grid: [[1]], targets: [{ "id" => "t1", "value" => 5 }], difficulty: "not_a_real_level")

    refute puzzle.valid?
    assert puzzle.errors[:difficulty].any?
  end

  test "accepts every difficulty PuzzleGenerator actually offers" do
    PuzzleGenerator::DIFFICULTY_LEVELS.each_key do |key|
      puzzle = Puzzle.new(size: 5, grid: [[1]], targets: [{ "id" => "t1", "value" => 5 }], difficulty: key)
      assert puzzle.valid?, "expected #{key} to be a valid difficulty"
    end
  end

  test "difficulty_label reads the human-friendly label from PuzzleGenerator's presets" do
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 1)
    assert_equal "Beginner", puzzle.difficulty_label
  end
end
