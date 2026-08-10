# Brute-force search for ANY chain (2 to max_length cells) on a grid that
# evaluates to a given target value. Not used by the live game (players
# find their own chains!) -- this exists so db/seeds.rb can generate
# realistic demo game history, and so the test suite can assert that
# every puzzle PuzzleGenerator produces is actually solvable.
class PuzzleSolver
  def self.find_path_for(grid, value, max_length: 4)
    new(grid, max_length).find_path_for(value)
  end

  def initialize(grid, max_length)
    @grid = grid
    @size = grid.size
    @max_length = max_length
  end

  def find_path_for(target_value)
    @size.times do |r|
      @size.times do |c|
        result = search([[r, c]], [], target_value)
        return result if result
      end
    end
    nil
  end

  private

  def search(coords, ops, target_value)
    if coords.size >= 2
      eval_result = ChainEvaluator.call(grid: @grid, coords: coords, ops: ops)
      return { coords: coords, ops: ops } if eval_result.valid? && eval_result.value == target_value
    end

    return nil if coords.size >= @max_length

    last = coords.last
    neighbors(last).each do |next_coord|
      next if coords.include?(next_coord)

      %w[+ *].each do |op|
        found = search(coords + [next_coord], ops + [op], target_value)
        return found if found
      end
    end

    nil
  end

  def neighbors(coord)
    r, c = coord
    result = []
    (-1..1).each do |dr|
      (-1..1).each do |dc|
        next if dr.zero? && dc.zero?

        nr, nc = r + dr, c + dc
        result << [nr, nc] if nr.between?(0, @size - 1) && nc.between?(0, @size - 1)
      end
    end
    result
  end
end
