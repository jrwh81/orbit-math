require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "facebook_login_public? is false when the env var is unset" do
    original = ENV.delete("FACEBOOK_LOGIN_PUBLIC")
    refute facebook_login_public?
  ensure
    ENV["FACEBOOK_LOGIN_PUBLIC"] = original
  end

  test "facebook_login_public? is false for any value other than the exact string 'true'" do
    original = ENV["FACEBOOK_LOGIN_PUBLIC"]
    ENV["FACEBOOK_LOGIN_PUBLIC"] = "yes"
    refute facebook_login_public?
  ensure
    ENV["FACEBOOK_LOGIN_PUBLIC"] = original
  end

  test "facebook_login_public? is true when the env var is exactly 'true'" do
    original = ENV["FACEBOOK_LOGIN_PUBLIC"]
    ENV["FACEBOOK_LOGIN_PUBLIC"] = "true"
    assert facebook_login_public?
  ensure
    ENV["FACEBOOK_LOGIN_PUBLIC"] = original
  end
end
