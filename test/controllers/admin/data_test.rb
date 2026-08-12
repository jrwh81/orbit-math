require "test_helper"

class AdminDataTest < ActionDispatch::IntegrationTest
  def sign_in_as_admin
    admin = User.create!(username: "data_admin_#{SecureRandom.hex(3)}", password: "password123", admin: true)
    post login_path, params: { username: admin.username, password: "password123" }
    admin
  end

  test "dashboard shows accurate total counts" do
    sign_in_as_admin
    player = User.create!(username: "dash_player", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 1)
    GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: player)

    get admin_root_path
    assert_response :success

    assert_select ".admin-stat-value", text: User.count.to_s
    assert_select ".admin-stat-value", text: GameSession.count.to_s
  end

  test "users index shows a user's real stats, not zeros for someone who has played" do
    sign_in_as_admin
    player = User.create!(username: "stats_player", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 2)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: player)
    game_session.participants.create!(user: player, player_number: 1)

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    ClaimService.call(game_session: game_session, user: player, coords: path[:coords], ops: path[:ops])
    GameCompletionService.call(game_session.reload)

    get admin_users_path
    assert_response :success
    assert_select "td", text: player.username
    # the row should show 1 game played, matching what GameCompletionService recorded
    player.user_stat.reload
    assert_select "td", text: player.user_stat.games_played.to_s
  end

  test "user detail page lists that user's actual game history" do
    sign_in_as_admin
    player = User.create!(username: "history_player", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 3)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: player)
    game_session.participants.create!(user: player, player_number: 1)

    get admin_user_path(player)
    assert_response :success
    assert_select "a[href=?]", admin_game_session_path(game_session)
  end

  test "game session detail page shows real player scores and moves" do
    sign_in_as_admin
    player = User.create!(username: "score_player", password: "password123")
    puzzle = PuzzleGenerator.call(difficulty: "beginner", seed: 4)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: player)
    game_session.participants.create!(user: player, player_number: 1)

    target = game_session.active_targets.first
    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    ClaimService.call(game_session: game_session, user: player, coords: path[:coords], ops: path[:ops])

    get admin_game_session_path(game_session)
    assert_response :success
    assert_select "td", text: "1" # score_for(player) should read 1 after that claim
  end

  test "an admin viewing a user's detail page sees THAT user's data, not their own -- guards against a variable mix-up" do
    sign_in_as_admin
    other = User.create!(username: "other_player", password: "password123", first_name: "The", last_name: "Other Player")

    get admin_user_path(other)
    assert_response :success
    # The admin's own username legitimately appears in the nav bar on
    # every page they view ("logged in as..."), so that's not what to
    # check here. What actually matters: the page body is scoped to the
    # REQUESTED user, not accidentally showing the logged-in admin's own
    # record (an easy mistake if @user ever got confused with current_user).
    assert_select "h1", text: /#{Regexp.escape(other.name)}/
    # The page's h1 shows "@username", and the .muted line beneath it
    # shows the admin-only full name -- check both, since together they
    # prove the page is scoped to the requested user, not the admin's own.
    assert_select ".muted", text: /#{Regexp.escape(other.full_name)}/
  end
end
