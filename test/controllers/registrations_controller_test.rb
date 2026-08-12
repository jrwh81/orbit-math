require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "signing up can never grant admin access, even if the param is included in the request" do
    post signup_path, params: {
      user: {
        first_name: "Sneaky",
        last_name: "Signup",
        username: "sneaky_signup",
        email: "sneaky@example.com",
        password: "password123",
        password_confirmation: "password123",
        admin: true # a malicious or malformed request trying to self-promote
      }
    }

    user = User.find_by(username: "sneaky_signup")
    assert user, "expected the signup to still succeed"
    refute user.admin?, "signup must never be able to grant admin access, regardless of what's in the request"
  end

  test "signup requires first name, last name, and email -- not just username/password" do
    post signup_path, params: {
      user: {
        username: "incomplete_signup",
        password: "password123",
        password_confirmation: "password123"
        # deliberately missing first_name, last_name, email
      }
    }

    refute User.exists?(username: "incomplete_signup"), "signup should have failed validation"
    assert_response :unprocessable_content
  end

  test "a full, valid signup succeeds and stores first/last name separately from username" do
    post signup_path, params: {
      user: {
        first_name: "Ada",
        last_name: "Lovelace",
        username: "ada_l",
        email: "ada@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    user = User.find_by(username: "ada_l")
    assert user
    assert_equal "Ada", user.first_name
    assert_equal "Lovelace", user.last_name
    assert_equal "Ada Lovelace", user.full_name
    assert_equal "ada_l", user.name, "the public-facing #name must be the username, never the real name"
  end
end
