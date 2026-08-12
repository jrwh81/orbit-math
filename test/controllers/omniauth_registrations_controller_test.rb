require "test_helper"

class OmniauthRegistrationsControllerTest < ActionDispatch::IntegrationTest
  def sign_in_with_pending_oauth
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "pending-uid-1",
      info: OmniAuth::AuthHash::InfoHash.new(
        email: "pending_person@example.com", first_name: "Grace", last_name: "Hopper", name: "Grace Hopper"
      )
    )
    get "/auth/google_oauth2/callback"
    assert_redirected_to finish_oauth_signup_path
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test "cannot reach the username step without a pending OAuth sign-in" do
    get finish_oauth_signup_path
    assert_redirected_to signup_path
  end

  test "the form is pre-filled with the provider's real name and email, editable only for username" do
    sign_in_with_pending_oauth

    get finish_oauth_signup_path
    assert_response :success
    # Rails omits the value attribute entirely for a nil field rather
    # than rendering value="" -- just confirm the empty, ready-to-fill
    # username input is present, not a specific value attribute.
    assert_select "input[name=?]", "user[username]"
    assert_match "Grace Hopper", response.body
    assert_match "pending_person@example.com", response.body
  end

  test "choosing a username completes the signup and logs the user in" do
    sign_in_with_pending_oauth

    assert_difference "User.count", 1 do
      post finish_oauth_signup_path, params: { user: { username: "grace_h" } }
    end

    assert_redirected_to root_path
    user = User.find_by(username: "grace_h")
    assert user
    assert_equal "google_oauth2", user.provider
    assert_equal "Grace", user.first_name
    assert_equal "pending_person@example.com", user.email
    assert_nil user.password_digest, "an OAuth account should never have a password"

    follow_redirect!
    assert_match "grace_h", response.body
  end

  test "an invalid username re-renders the form with an error, without creating an account" do
    sign_in_with_pending_oauth

    assert_no_difference "User.count" do
      post finish_oauth_signup_path, params: { user: { username: "a" } } # too short
    end

    assert_response :unprocessable_content
    assert_select ".form-errors"
  end

  test "a duplicate username is rejected the same as any other signup" do
    User.create!(username: "taken_name", password: "password123")
    sign_in_with_pending_oauth

    assert_no_difference "User.count" do
      post finish_oauth_signup_path, params: { user: { username: "taken_name" } }
    end

    assert_response :unprocessable_content
  end
end
