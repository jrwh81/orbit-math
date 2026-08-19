require "test_helper"

class SoloGamesControllerTest < ActionDispatch::IntegrationTest
  test "GET demo_path returns a real, currently-solvable chain for the live board" do
    user = User.create!(username: "demo_path_check", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 55)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    post login_path, params: { username: user.username, password: "password123" }
    get demo_path_solo_game_path(game_session)

    assert_response :success
    body = JSON.parse(response.body)
    assert body["available"]
    assert body["coords"].size >= 2
    assert_equal body["coords"].size - 1, body["ops"].size

    # The returned chain must actually evaluate to the target it claims
    # to solve -- reuse ChainEvaluator, the same authoritative evaluator
    # ClaimService itself uses, rather than re-implementing the math here.
    coords = body["coords"].map { |pair| pair.map(&:to_i) }
    eval_result = ChainEvaluator.call(grid: game_session.active_grid, coords: coords, ops: body["ops"])
    assert eval_result.valid?
    assert_equal body["target_value"], eval_result.value
  end

  test "GET demo_path is forbidden for a user who isn't a participant" do
    owner = User.create!(username: "demo_path_owner", password: "password123")
    outsider = User.create!(username: "demo_path_outsider", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 56)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: owner)
    game_session.participants.create!(user: owner, player_number: 1)

    post login_path, params: { username: outsider.username, password: "password123" }
    get demo_path_solo_game_path(game_session)

    assert_response :forbidden
  end

  test "the solo show page seeds an initial demo path when the user has demo mode enabled" do
    user = User.create!(username: "demo_seed_check", password: "password123")
    assert user.demo_mode_enabled?
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 57)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    post login_path, params: { username: user.username, password: "password123" }
    get solo_game_path(game_session)

    assert_response :success
    assert_match "data-demo-enabled-value=\"true\"", response.body
    assert_match "&quot;available&quot;:true", response.body
  end

  test "the solo show page does not seed a demo path when the user has demo mode disabled" do
    user = User.create!(username: "demo_seed_off_check", password: "password123", demo_mode_enabled: false)
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 58)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    post login_path, params: { username: user.username, password: "password123" }
    get solo_game_path(game_session)

    assert_response :success
    assert_match "data-demo-enabled-value=\"false\"", response.body
    assert_match "&quot;available&quot;:false", response.body
  end
end
