require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid with a username and password" do
    user = User.new(username: "starrider", password: "password123")
    assert user.valid?
  end

  test "requires a username" do
    user = User.new(password: "password123")
    refute user.valid?
    assert user.errors[:username].any?
  end

  test "rejects usernames with invalid characters" do
    user = User.new(username: "star rider!", password: "password123")
    refute user.valid?
  end

  test "requires a password of at least 6 characters" do
    user = User.new(username: "shorty", password: "abc")
    refute user.valid?
  end

  test "downcases the username before saving" do
    user = User.create!(username: "CosmicNova", password: "password123")
    assert_equal "cosmicnova", user.reload.username
  end

  test "automatically gets a UserStat row on creation" do
    user = User.create!(username: "statcheck", password: "password123")
    assert user.stat.present?
    assert_equal 0, user.stat.games_played
  end

  test "#name is always the username, never a real name -- privacy guarantee for public-facing display" do
    user = User.new(username: "privacycheck", password: "password123", first_name: "Real", last_name: "Name")
    assert_equal "privacycheck", user.name
  end

  test "#full_name joins first and last name, and is nil (not blank string) when both are absent" do
    with_name = User.new(first_name: "Grace", last_name: "Hopper")
    assert_equal "Grace Hopper", with_name.full_name

    without_name = User.new
    assert_nil without_name.full_name
  end

  test "first_name/last_name/email are NOT required on an ordinary create -- only within the :signup context" do
    # This is the core guarantee that keeps the rest of the test suite
    # (and seeds, and admin-created users) working: plain User.create!
    # calls, exactly like every other test in this app already does,
    # must keep working without needing first_name/last_name/email.
    user = User.new(username: "plain_create", password: "password123")
    assert user.valid?, "a plain (non-signup) User should not require first_name/last_name/email"
    assert user.save
  end

  test "first_name/last_name/email ARE required when saved with the :signup context" do
    user = User.new(username: "signup_context_check", password: "password123")
    refute user.valid?(:signup)
    assert user.errors[:first_name].any?
    assert user.errors[:last_name].any?
    assert user.errors[:email].any?
  end

  test "demo_mode_enabled defaults to true on a brand new account" do
    user = User.create!(username: "demo_default_check", password: "password123")
    assert user.demo_mode_enabled?, "demo mode should be ON by default -- it's opt-out, not opt-in"
  end
end
