class GameSession < ApplicationRecord
  enum :mode, { solo: 0, multiplayer: 1 }
  enum :status, { waiting: 0, active: 1, completed: 2 }

  belongs_to :puzzle
  belongs_to :host, class_name: "User"
  has_many :participants, dependent: :destroy
  has_many :users, through: :participants
  has_many :moves, dependent: :destroy

  before_validation :assign_join_code, if: -> { multiplayer? && join_code.blank? }
  before_validation :set_started_at, if: -> { active? && started_at.blank? }
  before_validation :initialize_round!, if: -> { puzzle.present? && active_targets.blank? }

  validates :join_code, presence: true, uniqueness: true, if: :multiplayer?

  # ---- Rotating targets ----------------------------------------------
  # active_targets is the LIVE, currently-visible target list -- it
  # always stays at a constant size. claims is a running HISTORY of
  # every target ever claimed (for scoring), not a "which of the fixed
  # targets are done" tracker -- targets rotate out and get replaced
  # the instant they're claimed, so the board never runs dry mid-round.
  # claims: { "t5" => { "user_id" => 3, "value" => 9, "claimed_at" => ... } }

  def claimed_target_ids
    claims.keys
  end

  def score_for(user)
    claims.values.count { |c| c["user_id"] == user.id }
  end

  # ---- Timer -----------------------------------------------------------
  # The round ends when the clock runs out, not when some claim count is
  # hit -- whoever has the most claims (multiplayer) or however many you
  # personally got (solo) when time expires is the result.

  def time_expired?
    active? && started_at.present? && Time.current >= started_at + time_limit_seconds
  end

  def time_remaining_seconds
    return time_limit_seconds if started_at.blank?
    return 0 if completed?

    remaining = (started_at + time_limit_seconds) - Time.current
    [remaining.to_i, 0].max
  end

  # Returns the user with the highest score, or nil for a tie (or if the
  # game isn't a completed multiplayer match). Deliberately NOT max_by,
  # which would silently pick a "winner" on a tie -- ties matter here.
  def winner
    return nil unless multiplayer? && completed?

    grouped = users.group_by { |u| score_for(u) }
    top_score = grouped.keys.max
    contenders = grouped[top_score]

    contenders.size == 1 ? contenders.first : nil
  end

  def opponent_of(user)
    users.find { |u| u.id != user.id }
  end

  # ---- Post-round stats ------------------------------------------------
  # Pulled from this session's own Move records (not global UserStat),
  # so these are specifically "how you did in THIS round" numbers for
  # the end-of-round summary screen.

  def longest_chain_for(user)
    moves.where(user: user, claimed: true).pluck(:path).map(&:size).max || 0
  end

  def highest_value_claimed_by(user)
    moves.where(user: user, claimed: true).maximum(:result_value) || 0
  end

  # A genuinely unique id for the next target to rotate in, backed by a
  # real persistent counter (next_id_seq) rather than a derived formula.
  # This MUST increment on every single call, including repeated calls
  # within the same claim -- a claim that also triggers a repair (see
  # ClaimService#repair_invalidated_targets) issues MORE than one new id
  # in a single pass, and a formula like "claims.size + active_targets.size + 1"
  # has no way to account for that. Getting this wrong doesn't just risk
  # a cosmetic duplicate id: two active targets sharing an id means
  # claiming EITHER one removes BOTH via `reject { |t| t["id"] == ... }`,
  # silently shrinking the active list by an extra slot on top of the
  # normal one -- a real bug that made it all the way to production
  # before being caught.
  def next_target_id
    id = "t#{next_id_seq}"
    self.next_id_seq += 1
    id
  end

  private

  def assign_join_code
    loop do
      code = SecureRandom.alphanumeric(6).upcase
      unless GameSession.exists?(join_code: code)
        self.join_code = code
        break
      end
    end
  end

  def set_started_at
    self.started_at = Time.current
  end

  # Seeds active_targets from the puzzle's initial target list and sets
  # time_limit_seconds from that puzzle's difficulty preset, so every
  # controller that creates a GameSession (solo, multiplayer, future
  # ones) gets correct rotation/timer setup automatically -- there's no
  # extra step to remember or forget.
  #
  # Only applies the preset's time_limit_seconds if the record still has
  # whatever the column's raw DB default is -- i.e. nobody explicitly
  # asked for something else. Without this check, a caller (a test
  # wanting a short, controllable round length, say) that explicitly
  # passes time_limit_seconds: 30 would have it silently clobbered back
  # to the difficulty's normal value, since this callback fires for
  # every new GameSession regardless of what was already assigned.
  def initialize_round!
    self.active_targets = puzzle.targets.map(&:dup)
    self.active_grid = puzzle.grid.map(&:dup)
    self.next_id_seq = active_targets.size + 1 # t1..tN already used by the initial targets

    preset = PuzzleGenerator::DIFFICULTY_LEVELS[puzzle.difficulty]
    return unless preset

    column_default = self.class.column_defaults["time_limit_seconds"]
    self.time_limit_seconds = preset[:time_limit_seconds] if time_limit_seconds == column_default
  end
end
