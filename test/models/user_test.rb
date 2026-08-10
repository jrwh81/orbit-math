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
end
