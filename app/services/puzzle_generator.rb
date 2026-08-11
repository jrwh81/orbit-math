# Builds a new Puzzle: an NxN grid of digits (1-9 by default) plus a list
# of target values reachable by chaining adjacent cells together.
#
# Strategy: rather than generating a random grid and hoping targets exist,
# we work backwards -- we "seed" a handful of self-avoiding random walks
# across the grid first, fix their values, compute what each one equals,
# and record that as a target. Any cells not touched by a seed chain are
# then filled afterward. Later seed chains are free to reuse cells a
# previous chain already touched (and must respect the value already
# sitting there), which is what makes multiple target chains overlap and
# share real estate on one shared board -- exactly what you want for two
# players racing over the same grid, and what naturally gives some
# targets more than one valid solving chain "for free".
#
# Two "bag" randomizers (Tetris-piece style: shuffle a full set, hand out
# one at a time, reshuffle a fresh set once empty) keep the board feeling
# lively and fair instead of purely independent-random:
#   - digit bag: every value 1..9 shows up roughly evenly across the
#     board instead of clumping (e.g. six 7s and one 2)
#   - chain-length bag: chain lengths draw a genuinely mixed spread
#     within whatever range the difficulty level allows
#
# DIFFICULTY controls how easy solutions are to *spot*, not just the
# board size: a small grid with only 2-cell, addition-only chains and a
# low value ceiling (Beginner) is dramatically easier to scan by eye than
# a large grid with long multi-op chains and values in the hundreds
# (Expert), even though both use the exact same underlying algorithm.
class PuzzleGenerator
  DIFFICULTY_LEVELS = {
    "beginner" => {
      label: "Beginner",
      size: 4,
      target_count: 4,
      time_limit_seconds: 90,
      min_chain_length: 2,
      max_chain_length: 2,
      multiply_probability: 0.0,   # addition only -- just spot two neighbors that add up
      max_target_value: 20
    },
    "intermediate" => {
      label: "Intermediate",
      size: 5,
      target_count: 5,
      time_limit_seconds: 90,
      min_chain_length: 2,
      max_chain_length: 3,
      multiply_probability: 0.2,
      max_target_value: 50
    },
    "advanced" => {
      label: "Advanced",
      size: 6,
      target_count: 6,
      time_limit_seconds: 90,
      min_chain_length: 2,
      max_chain_length: 4,
      multiply_probability: 0.3,
      max_target_value: 150
    },
    "expert" => {
      label: "Expert",
      size: 8,
      target_count: 8,
      time_limit_seconds: 90,
      min_chain_length: 2,
      max_chain_length: 4,
      multiply_probability: 0.4,
      max_target_value: 500
    }
  }.freeze

  DEFAULT_DIFFICULTY = "beginner"

  def self.levels
    DIFFICULTY_LEVELS
  end

  # size:, target_count: are still accepted as explicit overrides (handy
  # for tests, or a future "custom" mode) and win over the difficulty
  # preset's own values when given; everything else about generation
  # (chain length range, multiply odds, value ceiling) always comes from
  # the resolved difficulty level.
  def self.call(difficulty: nil, size: nil, target_count: nil, seed: nil)
    new(difficulty: difficulty, size: size, target_count: target_count, seed: seed).call
  end

  # Adds one fresh target to an already-built grid, matching the given
  # difficulty's chain-length/multiply/value rules. Used by ClaimService
  # to rotate a freshly-claimed target out for a new one mid-game.
  def self.add_target(grid:, difficulty:, id:, existing_values: [], seed: nil)
    new(difficulty: difficulty, seed: seed).add_target_to(grid, id, existing_values: existing_values)
  end

  def initialize(difficulty: nil, size: nil, target_count: nil, seed: nil)
    @difficulty = DIFFICULTY_LEVELS.key?(difficulty.to_s) ? difficulty.to_s : DEFAULT_DIFFICULTY
    preset = DIFFICULTY_LEVELS.fetch(@difficulty)

    game_config = Rails.application.config.x.game
    @size = size || preset[:size]
    @target_count = target_count || preset[:target_count]
    @min_chain_length = preset[:min_chain_length]
    @max_chain_length = preset[:max_chain_length]
    @multiply_probability = preset[:multiply_probability]
    @max_target_value = preset[:max_target_value]
    @min_value = game_config.min_value
    @max_value = game_config.max_value
    @seed = seed || SecureRandom.random_number(2_147_483_647)
    @random = Random.new(@seed)
    @digit_bag = []
    @length_bag = []
  end

  def call
    grid = Array.new(@size) { Array.new(@size) }
    targets = []

    @target_count.times do
      length = next_chain_length
      path = random_self_avoiding_path(grid, length)
      next if path.nil?

      fill_path_values!(grid, path)
      ops, value = build_ops_and_value(grid, path)

      targets << {
        "id" => "t#{targets.size + 1}",
        "value" => value,
        "length" => path.size
      }
    end

    fill_remaining_cells!(grid)

    Puzzle.create!(
      size: @size,
      grid: grid,
      targets: targets,
      difficulty: @difficulty,
      seed: @seed
    )
  end

  # Generates ONE additional target chain on an already-complete grid,
  # without touching any existing cell values (fill_path_values! is a
  # no-op on cells that are already filled). This is what powers target
  # rotation: the moment a player claims a target, GameSession replaces
  # it with a fresh one drawn from the exact same difficulty rules,
  # keeping the board's solvable-targets supply effectively endless
  # instead of the game grinding to a halt once a fixed list runs out.
  #
  # existing_values is a SOFT preference, not a hard requirement: first
  # try to avoid handing back a value that's already showing elsewhere
  # on the current target list (nicer polish, the rotating list reads as
  # more varied), but if that can't be satisfied, fall back to accepting
  # ANY solvable chain regardless of duplicates. Duplicate target values
  # are explicitly allowed by design (see PuzzleGenerator's own class
  # comment) -- a small, constrained board (Beginner's addition-only 4x4
  # grid is the prime example) can easily run out of genuinely NEW values
  # long before it runs out of valid chains. Treating "avoid duplicates"
  # as a hard requirement there meant this could return nil, which
  # silently shrank the active target list by one and broke the "the
  # board never runs dry" guarantee every other part of this app assumes.
  def add_target_to(grid, id, existing_values: [])
    find_target(grid, id, avoid: existing_values) || find_target(grid, id, avoid: [])
  end

  private

  def find_target(grid, id, avoid:)
    attempts = 20

    attempts.times do
      length = next_chain_length
      path = random_self_avoiding_path(grid, length)
      next if path.nil?

      fill_path_values!(grid, path)
      ops, value = build_ops_and_value(grid, path)
      next if avoid.include?(value)

      return { "id" => id, "value" => value, "length" => path.size }
    end

    nil
  end

  # ---- bag randomizers -----------------------------------------------

  def next_digit
    refill_digit_bag! if @digit_bag.empty?
    @digit_bag.pop
  end

  def refill_digit_bag!
    @digit_bag = (@min_value..@max_value).to_a.shuffle(random: @random)
  end

  def next_chain_length
    refill_length_bag! if @length_bag.empty?
    @length_bag.pop
  end

  def refill_length_bag!
    @length_bag = (@min_chain_length..@max_chain_length).to_a.shuffle(random: @random)
  end

  # ---- grid + chain construction --------------------------------------

  def random_self_avoiding_path(grid, length)
    max_attempts = 200

    max_attempts.times do
      start = [@random.rand(@size), @random.rand(@size)]
      path = [start]

      (length - 1).times do
        current = path.last
        candidates = neighbors(current, grid.size) - path
        break if candidates.empty?

        path << candidates.sample(random: @random)
      end

      return path if path.size == length
    end

    nil
  end

  def neighbors(coord, size)
    r, c = coord
    result = []
    (-1..1).each do |dr|
      (-1..1).each do |dc|
        next if dr.zero? && dc.zero?

        nr, nc = r + dr, c + dc
        result << [nr, nc] if nr.between?(0, size - 1) && nc.between?(0, size - 1)
      end
    end
    result
  end

  def fill_path_values!(grid, path)
    path.each do |(r, c)|
      grid[r][c] ||= next_digit
    end
  end

  def build_ops_and_value(grid, path)
    first_r, first_c = path.first
    value = grid[first_r][first_c]
    ops = []

    path[1..].each do |(r, c)|
      cell_value = grid[r][c]
      use_multiply = @random.rand < @multiply_probability && (value * cell_value) <= @max_target_value

      if use_multiply
        value *= cell_value
        ops << "*"
      else
        value += cell_value
        ops << "+"
      end
    end

    [ops, value]
  end

  def fill_remaining_cells!(grid)
    grid.each_with_index do |row, r|
      row.each_index do |c|
        grid[r][c] ||= next_digit
      end
    end
  end
end
