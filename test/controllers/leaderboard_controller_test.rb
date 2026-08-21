require "test_helper"

class LeaderboardControllerTest < ActionDispatch::IntegrationTest
  test "leaderboard renders a separate section for all four difficulties" do
    get leaderboard_path
    assert_response :success

    PuzzleGenerator::DIFFICULTY_LEVELS.each_value do |preset|
      assert_select "h2", text: preset[:label]
    end
  end

  test "a player who only played Beginner shows up on the Beginner table and NOT on Expert's" do
    user = User.create!(username: "lb_beginner_only", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 600)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)
    GameCompletionService.call(game_session)

    get leaderboard_path
    assert_response :success

    body = response.body
    # Anchor to the actual <h2> section heading, not just the bare word
    # -- the hero paragraph text on this page also happens to mention
    # both "Beginner" and "Expert" in prose, which a naive search would
    # match instead of the real section boundary.
    beginner_section = body[/<h2>Beginner<\/h2>.*?(?=<h2>|\z)/m]
    expert_section = body[/<h2>Expert<\/h2>.*?(?=<h2>|\z)/m]

    assert_match "lb_beginner_only", beginner_section
    refute_match "lb_beginner_only", expert_section
  end

  test "within a difficulty, players are ranked by their BEST single solo game score, not their career total" do
    low_best_high_total = User.create!(username: "lb_low_best", password: "password123")
    high_best_low_total = User.create!(username: "lb_high_best", password: "password123")

    # Lower best-game score, but a much higher career TOTAL across many
    # games -- exactly the scenario that would rank them #1 under the
    # old "sum of all points" ordering, and must NOT rank them #1 now.
    UserDifficultyStat.create!(user: low_best_high_total, difficulty: "beginner",
                                best_solo_score: 300, total_points: 5000, games_played: 20, games_won: 20)
    UserDifficultyStat.create!(user: high_best_low_total, difficulty: "beginner",
                                best_solo_score: 4000, total_points: 4000, games_played: 1, games_won: 1)

    get leaderboard_path
    assert_response :success

    body = response.body
    high_index = body.index("lb_high_best")
    low_index = body.index("lb_low_best")
    assert high_index < low_index,
           "the single best-scoring game should rank first, even though the other player has a higher career total"
  end

  test "a difficulty with no games yet shows a friendly empty state, not a blank/broken section" do
    get leaderboard_path
    assert_response :success
    assert_select ".muted", text: "No games played at this difficulty yet.", minimum: 1
  end

  test "a difficulty with games renders a real table with the expected columns, not a plain list" do
    user = User.create!(username: "lb_table_check", password: "password123")
    UserDifficultyStat.create!(user: user, difficulty: "beginner", best_solo_score: 900, total_points: 900,
                                games_played: 1, games_won: 1, targets_claimed: 4)

    get leaderboard_path
    assert_response :success

    assert_select "table.leaderboard-table" do
      assert_select "th", text: "Best solo game"
      assert_select "th", text: "Total pts"
      assert_select "th", text: "Wins"
      assert_select "th", text: "Prizes won"
      assert_select "th", text: "Games played"
      assert_select "td.lb-col-player", text: "lb_table_check"
      assert_select ".lb-best-score", text: "900"
      assert_select ".lb-rank-badge", text: "#1"
    end
  end
end
