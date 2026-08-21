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

  test "all games shows 'in progress' (not a premature winner) for a multiplayer game still underway" do
    player = User.create!(username: "recent_player", password: "password123")
    opponent = User.create!(username: "recent_opponent", password: "password123")
    viewer = User.create!(username: "unrelated_viewer", password: "password123") # not a participant at all

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

    # Logged in as someone who wasn't even in this game -- it should
    # still show up, since this is a site-wide feed, not personal history.
    post login_path, params: { username: viewer.username, password: "password123" }
    get root_path

    assert_response :success
    assert_match "recent_player", response.body
    assert_match "vs", response.body
    assert_match "recent_opponent", response.body
    assert_match "#{expected_points} pts", response.body
    assert_match "in progress", response.body
    refute_match "Winner:", response.body
    assert_select ".difficulty-badge", text: "Beginner"
  end

  test "all games explicitly labels the winner once a multiplayer game completes" do
    winner_user = User.create!(username: "explicit_winner", password: "password123")
    loser_user = User.create!(username: "explicit_loser", password: "password123")
    viewer = User.create!(username: "explicit_viewer", password: "password123")

    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 105)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: winner_user, started_at: Time.current
    )
    game_session.participants.create!(user: winner_user, player_number: 1)
    game_session.participants.create!(user: loser_user, player_number: 2)

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    ClaimService.call(game_session: game_session, user: winner_user, coords: path[:coords], ops: path[:ops])
    GameCompletionService.call(game_session.reload)

    post login_path, params: { username: viewer.username, password: "password123" }
    get root_path

    assert_response :success
    assert_match "Winner:", response.body
    assert_match "explicit_winner", response.body
    assert_match "Opponent:", response.body
    assert_match "explicit_loser", response.body
    assert_select ".winner-name", text: "explicit_winner"
  end

  test "all games labels a completed 0-0 multiplayer game as a tie, not a winner" do
    p1 = User.create!(username: "tie_player_one", password: "password123")
    p2 = User.create!(username: "tie_player_two", password: "password123")
    viewer = User.create!(username: "tie_viewer", password: "password123")

    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 106)
    game_session = GameSession.create!(
      mode: :multiplayer, status: :active, puzzle: puzzle, host: p1, started_at: Time.current
    )
    game_session.participants.create!(user: p1, player_number: 1)
    game_session.participants.create!(user: p2, player_number: 2)
    game_session.update!(status: :completed, ended_at: Time.current)

    post login_path, params: { username: viewer.username, password: "password123" }
    get root_path

    assert_response :success
    assert_match "Tie:", response.body
    refute_match "Winner:", response.body
  end

  test "all games shows the player's username for a solo run too, not just multiplayer" do
    player = User.create!(username: "recent_solo_player", password: "password123")
    viewer = User.create!(username: "another_viewer", password: "password123")

    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 103)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: player)
    game_session.participants.create!(user: player, player_number: 1)

    post login_path, params: { username: viewer.username, password: "password123" }
    get root_path

    assert_response :success
    assert_match "recent_solo_player", response.body
    assert_match "Solo run", response.body
  end

  test "Open link only shows for a game the CURRENT viewer is actually part of, and never for a completed one" do
    player = User.create!(username: "recent_status", password: "password123")
    other_player = User.create!(username: "someone_elses_game", password: "password123")

    # player's own game, still in progress -- should show Open for player
    my_ongoing_puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 102)
    my_ongoing = GameSession.create!(mode: :solo, status: :active, puzzle: my_ongoing_puzzle, host: player)
    my_ongoing.participants.create!(user: player, player_number: 1)

    # player's own game, completed -- should never show Open
    my_finished_puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 101)
    my_finished = GameSession.create!(mode: :solo, status: :active, puzzle: my_finished_puzzle, host: player)
    my_finished.participants.create!(user: player, player_number: 1)
    GameCompletionService.call(my_finished)

    # someone else's game, still in progress -- should NOT show Open to player
    others_ongoing_puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 104)
    others_ongoing = GameSession.create!(mode: :solo, status: :active, puzzle: others_ongoing_puzzle, host: other_player)
    others_ongoing.participants.create!(user: other_player, player_number: 1)

    post login_path, params: { username: player.username, password: "password123" }
    get root_path

    assert_response :success
    assert_select "a[href=?]", solo_game_path(my_ongoing), text: "Open"
    assert_select "a[href=?]", solo_game_path(my_finished), count: 0
    assert_select "a[href=?]", solo_game_path(others_ongoing), count: 0
  end

  test "regression: All games shows every game site-wide, not just 5 or just the viewer's own" do
    # The bug went through two wrong fixes before landing here: first it
    # was capped at 5, then it was "every game the current viewer has
    # played" -- neither is what was actually wanted, which is literally
    # every game, played by anyone, visible to any logged-in viewer.
    player_one = User.create!(username: "history_p1", password: "password123")
    player_two = User.create!(username: "history_p2", password: "password123")
    viewer = User.create!(username: "history_viewer", password: "password123")

    games_for_p1 = 4.times.map do |i|
      puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 200 + i)
      g = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: player_one)
      g.participants.create!(user: player_one, player_number: 1)
      GameCompletionService.call(g)
      g
    end

    games_for_p2 = 4.times.map do |i|
      puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 300 + i)
      g = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: player_two)
      g.participants.create!(user: player_two, player_number: 1)
      GameCompletionService.call(g)
      g
    end

    total_games = games_for_p1.size + games_for_p2.size

    # Logged in as a THIRD person who played none of these -- should
    # still see all 8, proving this is a genuine site-wide feed.
    post login_path, params: { username: viewer.username, password: "password123" }
    get root_path

    assert_response :success
    assert_select ".game-list-scroll .game-list li", count: total_games
  end

  test "the mobile nav hamburger toggle is present and correctly wired to Stimulus" do
    get root_path
    assert_response :success

    assert_select "header[data-controller='nav']"
    assert_select "button.nav-toggle[data-action='nav#toggle'][aria-label='Menu'][aria-expanded='false']"
    assert_select "nav.site-nav[data-nav-target='menu']"
  end

  test "homepage renders Open Graph and Twitter Card tags with an absolute image URL, for social link previews" do
    get root_path
    assert_response :success

    expected_image_url = "#{request.base_url}/og-image.jpg"
    assert_select "meta[property='og:type'][content='website']"
    assert_select "meta[property='og:title']"
    assert_select "meta[property='og:description']"
    assert_select "meta[property='og:image'][content=?]", expected_image_url
    assert_select "meta[property='og:url'][content=?]", root_url
    assert_select "meta[name='twitter:card'][content='summary_large_image']"
    assert_select "meta[name='twitter:image'][content=?]", expected_image_url

    # Every platform that reads these tags ignores relative image paths
    # outright -- this is the one thing that would silently break the
    # whole feature if it regressed.
    assert_match(/\Ahttps?:\/\//, expected_image_url)
  end
end
