require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "signing up can never grant admin access, even if the param is included in the request" do
    post signup_path, params: {
      user: {
        username: "sneaky_signup",
        password: "password123",
        password_confirmation: "password123",
        admin: true # a malicious or malformed request trying to self-promote
      }
    }

    user = User.find_by(username: "sneaky_signup")
    assert user, "expected the signup to still succeed"
    refute user.admin?, "signup must never be able to grant admin access, regardless of what's in the request"
  end
end
