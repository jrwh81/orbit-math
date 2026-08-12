require "test_helper"
require "concurrent"

# This test genuinely runs two threads on two separate DB connections at
# the same instant, both trying to claim the same target with the same
# winning chain. It exists to prove GameSession#with_lock (a real
# Postgres row lock) actually prevents a double-claim, not just to
# exercise the happy path.
#
# Transactional fixtures are turned off for this class on purpose: Rails'
# default transactional test wrapper runs the whole test on ONE
# connection, which would make rows created here invisible to the other
# threads' connections. We clean up manually instead.
class ClaimServiceConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "only one player wins when both submit the same winning chain at the same instant" do
    puzzle = PuzzleGenerator.call(difficulty: "intermediate", seed: 55)

    host  = User.create!(username: "race_host_#{SecureRandom.hex(4)}", password: "password123")
    guest = User.create!(username: "race_guest_#{SecureRandom.hex(4)}", password: "password123")

    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: host, started_at: Time.current
    )
    game_session.participants.create!(user: host, player_number: 1)
    game_session.participants.create!(user: guest, player_number: 2)

    # Pick a target whose value is genuinely unique on the active list --
    # two DIFFERENT targets are allowed to share the same displayed value
    # by design, so grabbing an arbitrary one (e.g. .first) could let
    # both threads legitimately claim two different same-valued targets,
    # which would look like a broken race but is actually correct game
    # behavior. This test needs a true single-target race to prove anything.
    value_counts = game_session.active_targets.each_with_object(Hash.new(0)) { |t, h| h[t["value"]] += 1 }
    target = game_session.active_targets.find { |t| value_counts[t["value"]] == 1 }
    assert target, "expected at least one uniquely-valued active target"
    original_target_id = target["id"]

    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    assert path, "fixture puzzle should have a solvable target"

    results = []
    results_mutex = Mutex.new
    barrier = Concurrent::CyclicBarrier.new(2)

    threads = [host, guest].map do |user|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          # Each thread MUST load its own independent GameSession instance.
          # Sharing the single `game_session` object across threads races
          # at the in-memory Ruby object level regardless of DB locking --
          # a real HTTP request per player (as MovesController does) never
          # hits this, but a test simulating two requests must mimic it.
          own_session = GameSession.find(game_session.id)
          barrier.wait # line both threads up so they fire as close to simultaneously as possible
          result = ClaimService.call(game_session: own_session, user: user, coords: path[:coords], ops: path[:ops])
          results_mutex.synchronize { results << result }
        end
      end
    end
    threads.each(&:join)

    # The real invariant GameSession#with_lock exists to guarantee: the
    # SPECIFIC target instance available at race time can only ever be
    # won by ONE of the two simultaneous submissions. Checked by target
    # id, not just "only one success total" -- because the OTHER
    # submission succeeding too isn't necessarily a bug. Target rotation
    # only *prefers* to avoid a duplicate value (see PuzzleGenerator.add_target),
    # it doesn't guarantee it, so the replacement that rotates in after
    # the winning claim can legitimately land on the same value by
    # coincidence -- in which case the "losing" submission is actually
    # claiming a real, different target that happens to share a number,
    # which is correct game behavior, not a double-claim.
    wins_of_original_target = results.select { |r| r.success? && r.target && r.target["id"] == original_target_id }
    assert_equal 1, wins_of_original_target.size,
                 "expected exactly one thread to win the race for THIS target, got #{wins_of_original_target.size}"

    game_session.reload
    assert game_session.claims.key?(original_target_id), "the original target should be recorded as claimed"
  ensure
    game_session&.destroy
    host&.destroy
    guest&.destroy
    puzzle&.destroy
  end
end
