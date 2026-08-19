require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "PATCH /demo_mode turns demo mode off for the current user" do
    user = User.create!(username: "demo_toggle_off", password: "password123")
    assert user.demo_mode_enabled?, "should start enabled by default"

    post login_path, params: { username: user.username, password: "password123" }
    patch demo_mode_path, params: { enabled: "false" }

    assert_response :success
    body = JSON.parse(response.body)
    refute body["demo_mode_enabled"]
    refute user.reload.demo_mode_enabled?
  end

  test "PATCH /demo_mode can turn demo mode back on" do
    user = User.create!(username: "demo_toggle_on", password: "password123", demo_mode_enabled: false)

    post login_path, params: { username: user.username, password: "password123" }
    patch demo_mode_path, params: { enabled: "true" }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["demo_mode_enabled"]
    assert user.reload.demo_mode_enabled?
  end

  test "PATCH /demo_mode requires login" do
    patch demo_mode_path, params: { enabled: "false" }
    assert_redirected_to login_path
  end

  test "PATCH /claim_name lets a guest replace their placeholder name and add an optional email" do
    get play_path # establishes a guest session, same as clicking "Play a Game"
    guest = User.last
    assert guest.guest?
    refute guest.name_claimed?

    patch claim_name_path, params: { username: "StarChaser", email: "star@example.com" }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal "starchaser", body["username"] # usernames are downcased before saving

    guest.reload
    assert_equal "starchaser", guest.username
    assert_equal "star@example.com", guest.email
    assert guest.name_claimed?
  end

  test "PATCH /claim_name works with no email at all -- it's optional" do
    get play_path
    guest = User.last

    patch claim_name_path, params: { username: "NoEmailHere" }

    assert_response :success
    assert JSON.parse(response.body)["success"]
    assert_nil guest.reload.email
    assert guest.reload.name_claimed?
  end

  test "PATCH /claim_name rejects a name that's already taken, without marking name_claimed" do
    User.create!(username: "takenname", password: "password123")
    get play_path
    guest = User.last

    patch claim_name_path, params: { username: "TakenName" }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    refute body["success"]
    assert body["errors"].any?
    refute guest.reload.name_claimed?, "a failed claim shouldn't silently mark the prompt as handled"
  end

  test "PATCH /claim_name refuses to rename a real (non-guest) account" do
    user = User.create!(username: "real_account_check", password: "password123")
    post login_path, params: { username: user.username, password: "password123" }

    patch claim_name_path, params: { username: "SomethingElse" }

    assert_response :forbidden
    assert_equal "real_account_check", user.reload.username
  end

  test "PATCH /claim_name requires login" do
    patch claim_name_path, params: { username: "Whoever" }
    assert_redirected_to login_path
  end
end
