# Validates and evaluates a "chain" the player has drawn across the grid.
#
# A chain is a sequence of grid coordinates plus the operator used to link
# each consecutive pair. A single click on an adjacent cell links with "+"
# (addition); a double-click links with "*" (multiplication). The chain is
# evaluated strictly LEFT TO RIGHT in the order it was drawn (no PEMDAS) --
# this matches how the path is drawn on screen, so what you see is what
# you get: 3 -> (+) -> 5 -> (x) -> 2 reads as (3 + 5) * 2 = 16, not 3 + 10.
#
# This class NEVER trusts client-supplied cell values -- it always looks
# the real value up from the authoritative Puzzle#grid, so a tampered
# request can't forge a winning chain.
class ChainEvaluator
  Result = Struct.new(:valid, :value, :error, :annotated_path, keyword_init: true) do
    alias_method :valid?, :valid
  end

  VALID_OPS = %w[+ *].freeze

  def self.call(grid:, coords:, ops:)
    new(grid, coords, ops).call
  end

  def initialize(grid, coords, ops)
    @grid = grid
    @coords = coords || []
    @ops = ops || []
  end

  def call
    return invalid("Chain must include at least 2 cells") if @coords.size < 2
    return invalid("Need exactly one operator between each pair of cells") if @ops.size != @coords.size - 1
    return invalid("Unknown operator") unless @ops.all? { |op| VALID_OPS.include?(op) }
    return invalid("Cells must be in bounds") unless in_bounds?
    return invalid("A chain can't reuse the same cell twice") if @coords.uniq.size != @coords.size
    return invalid("Each link must connect neighboring cells") unless contiguous?

    evaluate
  end

  private

  def in_bounds?
    size = @grid.size
    @coords.all? { |(r, c)| r.is_a?(Integer) && c.is_a?(Integer) && r.between?(0, size - 1) && c.between?(0, size - 1) }
  end

  def contiguous?
    @coords.each_cons(2).all? do |(r1, c1), (r2, c2)|
      dr = (r1 - r2).abs
      dc = (c1 - c2).abs
      dr <= 1 && dc <= 1 && !(dr.zero? && dc.zero?)
    end
  end

  def evaluate
    first_r, first_c = @coords.first
    value = @grid[first_r][first_c]
    annotated = [{ "row" => first_r, "col" => first_c, "value" => value }]

    @ops.each_with_index do |op, i|
      r, c = @coords[i + 1]
      cell_value = @grid[r][c]
      value = op == "*" ? value * cell_value : value + cell_value
      annotated << { "row" => r, "col" => c, "value" => cell_value, "op" => op }
    end

    Result.new(valid: true, value: value, error: nil, annotated_path: annotated)
  end

  def invalid(message)
    Result.new(valid: false, value: nil, error: message, annotated_path: nil)
  end
end
