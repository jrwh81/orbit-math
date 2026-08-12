require "test_helper"

class AdminAccessControlTest < ActionDispatch::IntegrationTest
  # These are the core security guarantee of the whole admin namespace:
  # every single admin route must be unreachable by anyone who isn't
  # logged in AND flagged admin. Tested against every admin route
  # directly rather than just the base controller in isolation, since
  # what actually matters is that EVERY action is actually gated, not
  # just that the gating mechanism works in principle.

  ADMIN_GET_PATHS = %w[/admin /admin/users /admin/game_sessions].freeze

  test "a logged-out visitor is redirected away from every admin page" do
    ADMIN_GET_PATHS.each do |path|
      get path
      assert_redirected_to root_path, "expected #{path} to redirect a logged-out visitor"
    end
  end

  test "a logged-in but non-admin user is redirected away from every admin page" do
    user = User.create!(username: "regular_user", password: "password123")
    post login_path, params: { username: user.username, password: "password123" }

    ADMIN_GET_PATHS.each do |path|
      get path
      assert_redirected_to root_path, "expected #{path} to redirect a non-admin user"
    end
  end

  test "a non-admin cannot view another user's admin detail page either" do
    user = User.create!(username: "regular_user2", password: "password123")
    other = User.create!(username: "someone_else", password: "password123")
    post login_path, params: { username: user.username, password: "password123" }

    get admin_user_path(other)
    assert_redirected_to root_path
  end

  test "an admin can reach every admin page" do
    admin = User.create!(username: "the_admin", password: "password123", admin: true)
    post login_path, params: { username: admin.username, password: "password123" }

    ADMIN_GET_PATHS.each do |path|
      get path
      assert_response :success, "expected an admin to be able to reach #{path}"
    end
  end

  test "the Admin nav link only appears in the layout for admin users" do
    regular = User.create!(username: "nav_regular", password: "password123")
    post login_path, params: { username: regular.username, password: "password123" }
    get root_path
    assert_select "a", text: "Admin", count: 0

    delete logout_path

    admin = User.create!(username: "nav_admin", password: "password123", admin: true)
    post login_path, params: { username: admin.username, password: "password123" }
    get root_path
    assert_select "a", text: "Admin", count: 1
  end
end
