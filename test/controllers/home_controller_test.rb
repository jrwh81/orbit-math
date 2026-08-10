require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "homepage loads for a logged out visitor" do
    get root_path
    assert_response :success
    assert_select "h1", text: Rails.application.config.x.game.name
  end

  test "homepage shows stats and dashboard once logged in" do
    user = User.create!(username: "dashcheck", password: "password123")
    post login_path, params: { username: user.username, password: "password123" }
    assert_redirected_to root_path

    get root_path
    assert_response :success
    assert_select ".dashboard"
  end
end
