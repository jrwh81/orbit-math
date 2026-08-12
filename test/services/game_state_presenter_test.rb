require "test_helper"

class GameStatePresenterTest < ActiveSupport::TestCase
  test "summary is nil while the game is still active" do
    user = User.create!(username: "gsp_active", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 1)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    payload = GameStatePresenter.new(game_session).as_json
    assert_nil payload[:summary]
  end

  test "summary includes claims, longest chain, and highest value per user once completed" do
    user = User.create!(username: "gsp_completed", password: "password123", first_name: "Presenter", last_name: "Test")
    puzzle = PuzzleGenerator.call(difficulty: "advanced", seed: 2)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    2.times do
      game_session.reload
      target = game_session.active_targets.find { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
      path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
      ClaimService.call(game_session: game_session, user: user, coords: path[:coords], ops: path[:ops])
    end

    game_session.reload
    GameCompletionService.call(game_session)

    payload = GameStatePresenter.new(game_session).as_json
    refute_nil payload[:summary]

    my_summary = payload[:summary][user.id]
    refute_nil my_summary, "expected a summary entry keyed by the user's id"
    assert_equal game_session.score_for(user), my_summary[:claims]
    assert_equal game_session.longest_chain_for(user), my_summary[:longest_chain]
    assert_equal game_session.highest_value_claimed_by(user), my_summary[:highest_value]
    assert my_summary[:longest_chain] >= 2, "every claim requires at least a 2-cell chain"
  end

  test "targets_json no longer includes claimed/claimed_by flags" do
    user = User.create!(username: "gsp_targets", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 3)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: user)
    game_session.participants.create!(user: user, player_number: 1)

    payload = GameStatePresenter.new(game_session).as_json
    payload[:targets].each do |t|
      assert_equal %i[id value], t.keys.sort
    end
  end
end
