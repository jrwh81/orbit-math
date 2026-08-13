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

  test "within a difficulty, players are ranked by total points, highest first" do
    low_scorer = User.create!(username: "lb_low", password: "password123")
    high_scorer = User.create!(username: "lb_high", password: "password123")

    # Give high_scorer more claims (and therefore more points) than
    # low_scorer, both at the same difficulty.
    [[low_scorer, 1], [high_scorer, 3]].each do |user, claim_count|
      claim_count.times do |i|
        puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 610 + i)
        game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
        game_session.participants.create!(user: user, player_number: 1)
        target = game_session.active_targets.first
        path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
        ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
        GameCompletionService.call(game_session.reload)
      end
    end

    get leaderboard_path
    assert_response :success

    body = response.body
    high_index = body.index("lb_high")
    low_index = body.index("lb_low")
    assert high_index < low_index, "expected the higher-scoring player to appear first on the leaderboard"
  end

  test "a difficulty with no games yet shows a friendly empty state, not a blank/broken section" do
    get leaderboard_path
    assert_response :success
    assert_select ".muted", text: "No games played at this difficulty yet.", minimum: 1
  end
end
