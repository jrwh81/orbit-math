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
end
