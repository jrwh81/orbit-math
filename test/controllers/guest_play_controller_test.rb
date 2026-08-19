require "test_helper"

class GuestPlayControllerTest < ActionDispatch::IntegrationTest
  test "GET /play with no session creates a guest account and drops straight into a solo game" do
    assert_difference "User.count", 1 do
      get play_path
    end

    user = User.last
    assert user.guest?
    assert user.demo_mode_enabled?, "guests should get the same on-by-default demo mode as anyone else"
    refute user.name_claimed?
    assert_match(/\Aguest\d+\z/, user.username)

    game_session = GameSession.solo.last
    assert_redirected_to solo_game_path(game_session)
    assert_equal user, game_session.host
    assert game_session.users.include?(user)
  end

  test "GET /play twice in a row reuses the same guest session instead of creating a second account" do
    get play_path
    first_game = GameSession.solo.last
    guest_id = session[:user_id]

    assert_no_difference "User.count" do
      get play_path
    end

    assert_equal guest_id, session[:user_id]
    second_game = GameSession.solo.last
    refute_equal first_game.id, second_game.id, "a second visit should start a NEW game, not reuse the finished one"
  end

  test "GET /play for an already logged-in real user just starts a fresh game for them, no new account" do
    user = User.create!(username: "existing_player", password: "password123")
    post login_path, params: { username: user.username, password: "password123" }

    assert_no_difference "User.count" do
      get play_path
    end

    game_session = GameSession.solo.last
    assert_equal user, game_session.host
    refute user.reload.guest?, "an existing real account should never get flagged as a guest just by clicking Play a Game"
  end

  test "every generated guest username is actually unique even across repeated visits" do
    get play_path
    first_username = User.last.username
    delete logout_path

    get play_path
    second_username = User.last.username

    refute_equal first_username, second_username
  end
end
