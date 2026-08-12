require "test_helper"

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  setup { OmniAuth.config.test_mode = true }

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  def mock_google_auth(email: "new_person@example.com", uid: "google-uid-1", first_name: "Ada", last_name: "Lovelace")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: OmniAuth::AuthHash::InfoHash.new(
        email: email, first_name: first_name, last_name: last_name, name: "#{first_name} #{last_name}"
      )
    )
  end

  test "a returning user with an already-linked Google account is logged straight in" do
    User.create!(username: "returning_oauth_user", provider: "google_oauth2", uid: "google-uid-1")
    mock_google_auth(uid: "google-uid-1")

    get "/auth/google_oauth2/callback"

    assert_redirected_to root_path
    follow_redirect!
    assert_match "returning_oauth_user", response.body
  end

  test "a brand new Google sign-in redirects to choose a username, with no account created yet" do
    mock_google_auth(email: "genuinely_new@example.com", uid: "google-uid-new")

    assert_no_difference "User.count" do
      get "/auth/google_oauth2/callback"
    end

    assert_redirected_to finish_oauth_signup_path
  end

  test "signing in with Google using an email that matches an existing traditional account links it, doesn't duplicate it" do
    existing = User.create!(username: "traditional_account", email: "shared@example.com", password: "password123")
    mock_google_auth(email: "shared@example.com", uid: "google-uid-link")

    assert_no_difference "User.count" do
      get "/auth/google_oauth2/callback"
    end

    assert_redirected_to root_path
    existing.reload
    assert_equal "google_oauth2", existing.provider
    assert_equal "google-uid-link", existing.uid
  end
end
