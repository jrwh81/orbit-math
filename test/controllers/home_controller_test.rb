require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "homepage loads for a logged out visitor" do
    get root_path
    assert_response :success
    assert_select "h1", text: Rails.application.config.x.game.name
  end

  test "homepage shows a How to Play section, even for a logged out visitor" do
    get root_path
    assert_response :success
    assert_select ".how-to-play h2", text: "How to Play"
    # the illustrative demo grid and its worked example should render too
    assert_select ".demo-board .cell", count: 4
    assert_select ".demo-expression", text: /3 \+ 5.*4 = 32/
  end

  test "homepage shows stats and dashboard once logged in" do
    user = User.create!(username: "dashcheck", password: "password123")
    post login_path, params: { username: user.username, password: "password123" }
    assert_redirected_to root_path

    get root_path
    assert_response :success
    assert_select ".dashboard"
  end

  test "recent games shows the PLAYER'S username, the opponent's username, difficulty, and points" do
    player = User.create!(username: "recent_player", password: "password123")
    opponent = User.create!(username: "recent_opponent", password: "password123")

    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 100)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: player, started_at: Time.current
    )
    game_session.participants.create!(user: player, player_number: 1)
    game_session.participants.create!(user: opponent, player_number: 2)

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    ClaimService.call(game_session: game_session, user: player, coords: path[:coords], ops: path[:ops])
    expected_points = game_session.reload.points_for(player)

    post login_path, params: { username: player.username, password: "password123" }
    get root_path

    assert_response :success
    # Both usernames must appear -- the player who actually played this
    # game, and (for multiplayer) who they played against.
    assert_match "recent_player", response.body
    assert_match "vs recent_opponent", response.body
    assert_match "#{expected_points} pts", response.body
    assert_select ".difficulty-badge", text: "Beginner"
  end

  test "recent games shows the player's username for a solo run too, not just multiplayer" do
    player = User.create!(username: "recent_solo_player", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 103)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: player)
    game_session.participants.create!(user: player, player_number: 1)

    post login_path, params: { username: player.username, password: "password123" }
    get root_path

    assert_response :success
    assert_match "recent_solo_player", response.body
    assert_match "Solo run", response.body
  end

  test "recent games has no Open link for a completed game, but does for one still in progress" do
    player = User.create!(username: "recent_status", password: "password123")

    finished_puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 101)
    finished = GameSession.create!(mode: :solo, status: :active, puzzle: finished_puzzle, host: player)
    finished.participants.create!(user: player, player_number: 1)
    GameCompletionService.call(finished)

    ongoing_puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 102)
    ongoing = GameSession.create!(mode: :solo, status: :active, puzzle: ongoing_puzzle, host: player)
    ongoing.participants.create!(user: player, player_number: 1)

    post login_path, params: { username: player.username, password: "password123" }
    get root_path

    assert_response :success
    assert_select "a[href=?]", solo_game_path(ongoing), text: "Open"
    assert_select "a[href=?]", solo_game_path(finished), count: 0
  end

  test "regression: game history shows every game, not just the 5 most recent" do
    # This is the exact bug reported: a player with more than 5 games
    # couldn't see anything past their 5 most recent, silently hiding
    # real history rather than paginating it or making that limit visible.
    player = User.create!(username: "history_full", password: "password123")

    game_sessions = 7.times.map do |i|
      puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 200 + i)
      g = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: player)
      g.participants.create!(user: player, player_number: 1)
      GameCompletionService.call(g)
      g
    end

    post login_path, params: { username: player.username, password: "password123" }
    get root_path

    assert_response :success
    # All 7 should be reachable via their unique difficulty badges/ids --
    # simplest robust check is that all 7 game ids appear as data on the
    # page somewhere (e.g. the completed games' "Open" links are gone,
    # but the games themselves -- via their difficulty_label/points rows --
    # should each still render one <li> per game).
    assert_select ".game-list-scroll .game-list li", count: game_sessions.size
  end
end
