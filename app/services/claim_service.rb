# Processes one player's submitted chain against a GameSession.
#
# This is the single authoritative place where a chain is validated,
# evaluated, and (if it matches a currently-open target) locked in as a
# claim. On a successful claim, three things happen together:
#   1. The claimed target is removed and a fresh one rotates in.
#   2. The specific cells that made up the winning chain get NEW digit
#      values -- claiming a chain "uses up" those numbers, so the board
#      keeps evolving over the round instead of sitting static.
#   3. Any OTHER still-active target that happened to share one of those
#      now-changed cells gets checked for solvability and repaired if
#      the regeneration broke it -- multiple targets are allowed to
#      overlap the same cells by design, so this is a real possibility,
#      and "there should always be an answer available" is a hard
#      guarantee this app makes, not just a nice-to-have.
#
# For multiplayer games two people can submit a winning chain within
# milliseconds of each other -- GameSession#with_lock takes a row-level
# Postgres lock (SELECT ... FOR UPDATE) so only one of them can actually
# win the race, and the loser gets a clear "already claimed" result
# instead of a corrupted double-claim.
class ClaimService
  Result = Struct.new(:success, :value, :target, :replacement, :message, :move, :points, :multiplier, keyword_init: true) do
    alias_method :success?, :success
  end

  # A prize's base point value, driven purely by how big its target
  # value is -- three tiers, not a flat rate per difficulty. Deliberately
  # shares its exact breakpoints (20, 100) with the material tier
  # visuals grid_controller.js uses (crystal/emerald/diamond), so a
  # prize that LOOKS rarer is always worth more base points too -- the
  # two are meant to move together, never drift apart. A public class
  # method (not just an internal helper) so tests, views, and any other
  # code that needs "how many points is this prize worth" have one
  # single source of truth instead of duplicating these numbers.
  PRIZE_TIERS = [
    { max: 20, points: 100 },
    { max: 100, points: 300 },
    { max: Float::INFINITY, points: 500 }
  ].freeze

  def self.points_for_value(value)
    PRIZE_TIERS.find { |tier| value <= tier[:max] }[:points]
  end

  # The chain multiplier rewards reaching for bigger digits on the
  # board, not just landing on a big target -- 3x for a chain that only
  # ever touched 1-3, 5x if it touched a 4-6 anywhere, 8x if it touched
  # a 7-9 anywhere. Driven by the SINGLE HIGHEST digit actually used
  # (not an average), so linking even one ambitious number pays off
  # immediately. Shares its exact 1-3/4-6/7-9 boundaries with
  # cellValueColorClass in grid_controller.js on purpose: the multiplier
  # a chain earns always matches the color band its brightest linked
  # number would show on screen.
  MULTIPLIER_TIERS = [
    { max: 3, multiplier: 3 },
    { max: 6, multiplier: 5 },
    { max: 9, multiplier: 8 }
  ].freeze

  def self.multiplier_for_chain(annotated_path)
    highest_digit = annotated_path.map { |step| step["value"] }.max
    tier = MULTIPLIER_TIERS.find { |t| highest_digit <= t[:max] }
    (tier || MULTIPLIER_TIERS.last)[:multiplier]
  end

  # A claim's total points: the prize's own base value times the
  # multiplier its solving chain earned. This is the number that
  # actually lands on the scoreboard and flashes on screen.
  def self.points_for_claim(target_value, annotated_path)
    points_for_value(target_value) * multiplier_for_chain(annotated_path)
  end

  def self.call(game_session:, user:, coords:, ops:)
    new(game_session, user, coords, ops).call
  end

  def initialize(game_session, user, coords, ops)
    @game_session = game_session
    @user = user
    @coords = coords
    @ops = ops
  end

  def call
    return Result.new(success: false, message: "Game is not active") unless @game_session.active?

    # Validate against the LIVE grid, not the puzzle's original template
    # -- once cells start regenerating, the template no longer reflects
    # what the player is actually looking at on screen.
    eval_result = ChainEvaluator.call(grid: @game_session.active_grid, coords: @coords, ops: @ops)
    return Result.new(success: false, message: eval_result.error) unless eval_result.valid?

    claimed_target, replacement, points, multiplier = attempt_claim_and_rotate(eval_result.value, eval_result.annotated_path)
    move = record_move(eval_result, claimed_target)

    if claimed_target
      Result.new(
        success: true, value: eval_result.value, target: claimed_target,
        replacement: replacement, message: "claimed", move: move,
        points: points, multiplier: multiplier
      )
    else
      Result.new(success: false, value: eval_result.value, message: "No open target matches #{eval_result.value}", move: move)
    end
  end

  private

  # Row-level lock guarantees exactly one caller wins when two players
  # submit a matching chain for the same target at nearly the same time.
  def attempt_claim_and_rotate(value, annotated_path)
    claimed_target = nil
    replacement = nil
    points = nil
    multiplier = nil

    @game_session.with_lock do
      target = @game_session.active_targets.find { |t| t["value"] == value }
      next unless target

      grid = @game_session.active_grid.map(&:dup) # fresh array object, not a mutated live reference --
      regenerate_cells!(grid, @coords)             # see the comment on regenerate_cells! for why this matters

      remaining_targets = @game_session.active_targets.reject { |t| t["id"] == target["id"] }
      remaining_targets = repair_invalidated_targets(grid, remaining_targets)

      remaining_values = remaining_targets.map { |t| t["value"] }
      replacement = PuzzleGenerator.add_target(
        grid: grid,
        difficulty: @game_session.puzzle.difficulty,
        id: @game_session.next_target_id,
        existing_values: remaining_values
      )

      multiplier = self.class.multiplier_for_chain(annotated_path)
      points = self.class.points_for_value(value) * multiplier

      @game_session.active_grid = grid
      @game_session.active_targets = replacement ? remaining_targets + [replacement] : remaining_targets
      @game_session.claims = @game_session.claims.merge(
        target["id"] => {
          "user_id" => @user.id,
          "value" => value,
          "points" => points,
          "multiplier" => multiplier,
          "claimed_at" => Time.current.iso8601
        }
      )
      @game_session.save!
      claimed_target = target
    end

    [claimed_target, replacement, points, multiplier]
  end

  # Gives every cell in the winning chain a new value, different from
  # what it was, so the change actually reads as visible on screen.
  #
  # IMPORTANT: this mutates `grid` in place, so the caller must always
  # pass a freshly-duplicated array (never `@game_session.active_grid`
  # directly) -- ActiveRecord's dirty tracking on a jsonb column detects
  # changes by comparing the "current" value against the value captured
  # at load time, and mutating that same cached object in place rather
  # than assigning a genuinely new one risks the change silently not
  # being detected/persisted on save. Same reason `claims` is always
  # updated via `.merge` (which returns a new Hash) rather than mutated
  # directly.
  def regenerate_cells!(grid, coords)
    game_config = Rails.application.config.x.game

    coords.each do |(r, c)|
      old_value = grid[r][c]
      new_value = old_value
      new_value = rand(game_config.min_value..game_config.max_value) while new_value == old_value
      grid[r][c] = new_value
    end
  end

  # Cell regeneration can silently strand another active target that
  # relied on one of the cells that just changed. Re-check every
  # remaining target against the updated grid and swap in a fresh
  # (still-solvable) value + id for any that no longer resolve.
  #
  # Each call to @game_session.next_target_id here increments a real
  # persisted counter -- important, because a single claim can trigger
  # more than one repair alongside the primary replacement, and every
  # one of those needs a genuinely unique id (see the comment on
  # GameSession#next_target_id for what goes wrong if they collide).
  def repair_invalidated_targets(grid, targets)
    targets.map do |t|
      next t if PuzzleSolver.find_path_for(grid, t["value"])

      other_values = targets.map { |x| x["value"] } - [t["value"]]
      fixed = PuzzleGenerator.add_target(
        grid: grid,
        difficulty: @game_session.puzzle.difficulty,
        id: @game_session.next_target_id,
        existing_values: other_values
      )
      fixed || t # extremely unlikely fallback: leave it rather than crash
    end
  end

  def record_move(eval_result, claimed_target)
    Move.create!(
      game_session: @game_session,
      user: @user,
      path: eval_result.annotated_path,
      ops: @ops,
      result_value: eval_result.value,
      claimed: claimed_target.present?,
      target_id: claimed_target && claimed_target["id"]
    )
  end
end
