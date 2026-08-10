require "test_helper"

class MovesControllerTest < ActionDispatch::IntegrationTest
  test "a move submitted after the server-side time limit is rejected and finalizes the round" do
    user = User.create!(username: "int_timer", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 9001)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    post login_path, params: { username: user.username, password: "password123" }
    assert_redirected_to root_path

    travel_to(game_session.started_at + game_session.time_limit_seconds + 5) do
      target = game_session.active_targets.first
      path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])

      post solo_game_moves_path(game_session),
           params: { coords: path[:coords], ops: path[:ops] }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    end

    assert_response :success
    body = JSON.parse(response.body)

    refute body["result"]["success"], "a move after time is up should never succeed, even if it would have matched"
    assert_equal "Time's up!", body["result"]["message"]

    game_session.reload
    assert game_session.completed?, "the server should finalize the round itself once it notices time has expired"
  end

  test "a move submitted well within the time limit is processed normally" do
    user = User.create!(username: "int_timer2", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 9002)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    post login_path, params: { username: user.username, password: "password123" }

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])

    post solo_game_moves_path(game_session),
         params: { coords: path[:coords], ops: path[:ops] }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    assert_response :success
    body = JSON.parse(response.body)

    assert body["result"]["success"]
    refute game_session.reload.completed?
  end
end
