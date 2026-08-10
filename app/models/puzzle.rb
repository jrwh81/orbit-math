# A Puzzle is a reusable template: an NxN grid of digits plus a list of
# target values that can be reached by chaining adjacent cells together.
# Many GameSessions (solo or multiplayer) can be played against the very
# same Puzzle -- each GameSession tracks its own claims independently.
class Puzzle < ApplicationRecord
  has_many :game_sessions, dependent: :nullify

  validates :size, numericality: { greater_than: 2 }
  validates :grid, presence: true
  validates :targets, presence: true
  validates :difficulty, inclusion: { in: PuzzleGenerator::DIFFICULTY_LEVELS.keys }

  def difficulty_label
    PuzzleGenerator::DIFFICULTY_LEVELS.dig(difficulty, :label) || difficulty.to_s.capitalize
  end

  # targets: [{ "id" => "t1", "value" => 42 }, ...]
  def target_ids
    targets.map { |t| t["id"] }
  end

  def target_for(id)
    targets.find { |t| t["id"] == id.to_s }
  end

  def value_at(row, col)
    grid[row][col]
  end
end
