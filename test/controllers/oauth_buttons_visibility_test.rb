require "test_helper"

class OauthButtonsVisibilityTest < ActionDispatch::IntegrationTest
  test "Facebook button is hidden by default on login and signup, Google button always shows" do
    original = ENV.delete("FACEBOOK_LOGIN_PUBLIC")

    get login_path
    assert_select ".btn-oauth-google"
    assert_select ".btn-oauth-facebook", count: 0

    get signup_path
    assert_select ".btn-oauth-google"
    assert_select ".btn-oauth-facebook", count: 0
  ensure
    ENV["FACEBOOK_LOGIN_PUBLIC"] = original
  end

  test "Facebook button appears on both pages once explicitly enabled" do
    original = ENV["FACEBOOK_LOGIN_PUBLIC"]
    ENV["FACEBOOK_LOGIN_PUBLIC"] = "true"

    get login_path
    assert_select ".btn-oauth-facebook"

    get signup_path
    assert_select ".btn-oauth-facebook"
  ensure
    ENV["FACEBOOK_LOGIN_PUBLIC"] = original
  end
end
