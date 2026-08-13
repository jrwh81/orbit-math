require "test_helper"

class UserDifficultyStatTest < ActiveSupport::TestCase
  test "recording a solo game creates a stat row scoped to that difficulty" do
    user = User.create!(username: "uds_solo", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 500)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
    game_session.reload

    UserDifficultyStat.record_completed_game!(game_session)

    stat = UserDifficultyStat.find_by(user: user, difficulty: "beginner")
    assert stat
    assert_equal 1, stat.games_played
    assert_equal 1, stat.games_won # solo always counts as a "win" for stat purposes
    assert_equal game_session.targets_claimed_by(user), stat.targets_claimed
    assert_equal game_session.points_for(user), stat.total_points
    assert_equal stat.total_points, stat.best_solo_score
  end

  test "regression: a game whose puzzle has an unrecognized difficulty is skipped, not a crash" do
    # This is exactly what broke the migration's backfill in practice:
    # a Puzzle row left over from before real difficulty tiers existed,
    # still holding the old placeholder value "normal". There's no
    # sensible tier to guess for it, so it must be silently skipped --
    # both here and, more importantly, during the migration's backfill
    # loop, which iterates over EVERY completed game and can't afford to
    # abort partway through over one old row.
    user = User.create!(username: "uds_legacy_diff", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 501)
    puzzle.update_column(:difficulty, "normal") # bypass validation, simulating genuinely old data
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    assert_nothing_raised do
      UserDifficultyStat.record_completed_game!(game_session)
    end

    assert_equal 0, UserDifficultyStat.where(user: user).count
  end

  test "recording a second game at the SAME difficulty accumulates rather than overwrites" do
    user = User.create!(username: "uds_accumulate", password: "password123")

    2.times do |i|
      puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 501 + i)
      game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
      game_session.participants.create!(user: user, player_number: 1)
      target = game_session.active_targets.first
      path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
      ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
      UserDifficultyStat.record_completed_game!(game_session.reload)
    end

    stat = UserDifficultyStat.find_by(user: user, difficulty: "beginner")
    assert_equal 2, stat.games_played
    assert_equal 2, stat.games_won
  end

  test "games at DIFFERENT difficulties create separate rows, never mixed together" do
    user = User.create!(username: "uds_separate", password: "password123")

    beginner_puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 510)
    beginner_game = GameSession.create!(mode: :solo, status: :active, puzzle: beginner_puzzle, host: user)
    beginner_game.participants.create!(user: user, player_number: 1)
    UserDifficultyStat.record_completed_game!(beginner_game)

    expert_puzzle = PuzzleGenerator.call(difficulty: "expert", seed: 511)
    expert_game = GameSession.create!(mode: :solo, status: :active, puzzle: expert_puzzle, host: user)
    expert_game.participants.create!(user: user, player_number: 1)
    UserDifficultyStat.record_completed_game!(expert_game)

    assert_equal 2, UserDifficultyStat.where(user: user).count
    beginner_stat = UserDifficultyStat.find_by(user: user, difficulty: "beginner")
    expert_stat = UserDifficultyStat.find_by(user: user, difficulty: "expert")
    assert_equal 1, beginner_stat.games_played
    assert_equal 1, expert_stat.games_played
  end

  test "a multiplayer win is only credited to the actual winner, and a tie credits neither" do
    p1 = User.create!(username: "uds_mp_winner", password: "password123")
    p2 = User.create!(username: "uds_mp_loser", password: "password123")

    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 520)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: p1, started_at: Time.current
    )
    game_session.participants.create!(user: p1, player_number: 1)
    game_session.participants.create!(user: p2, player_number: 2)

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    ClaimService.call(game_session: game_session, user: p1, coords: path[:coords], ops: path[:ops])
    game_session.update!(status: :completed, ended_at: Time.current)

    UserDifficultyStat.record_completed_game!(game_session)

    winner_stat = UserDifficultyStat.find_by(user: p1, difficulty: "beginner")
    loser_stat = UserDifficultyStat.find_by(user: p2, difficulty: "beginner")
    assert_equal 1, winner_stat.games_won
    assert_equal 0, loser_stat.games_won
    assert_equal 0, loser_stat.best_solo_score, "multiplayer games should never touch best_solo_score"
  end

  test "GameCompletionService calls this automatically -- no manual step needed for live gameplay" do
    user = User.create!(username: "uds_auto_completion", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "intermediate", seed: 530)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    assert_difference "UserDifficultyStat.count", 1 do
      GameCompletionService.call(game_session)
    end

    stat = UserDifficultyStat.find_by(user: user, difficulty: "intermediate")
    assert stat
    assert_equal 1, stat.games_played
  end
end
