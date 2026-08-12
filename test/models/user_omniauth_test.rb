require "test_helper"

class UserOmniauthTest < ActiveSupport::TestCase
  def auth_hash(provider: "google_oauth2", uid: "uid-123", email: "person@example.com")
    OmniAuth::AuthHash.new(
      provider: provider,
      uid: uid,
      info: OmniAuth::AuthHash::InfoHash.new(email: email, first_name: "Ada", last_name: "Lovelace")
    )
  end

  test "returns the existing user when provider+uid already match a linked account" do
    user = User.create!(username: "already_linked", provider: "google_oauth2", uid: "uid-123")

    found = User.from_omniauth(auth_hash(uid: "uid-123"))
    assert_equal user, found
  end

  test "links a new OAuth identity to an existing account with a matching email, rather than creating a duplicate" do
    existing = User.create!(username: "existing_traditional", email: "person@example.com", password: "password123")
    refute existing.oauth_account?

    found = User.from_omniauth(auth_hash(email: "person@example.com", uid: "brand-new-uid"))

    assert_equal existing.id, found.id
    found.reload
    assert_equal "google_oauth2", found.provider
    assert_equal "brand-new-uid", found.uid
  end

  test "returns nil when nothing matches -- signals a genuinely new sign-in" do
    found = User.from_omniauth(auth_hash(email: "nobody_yet@example.com", uid: "never-seen-uid"))
    assert_nil found
  end

  test "returns nil (not a crash) when the provider gives no email and nothing else matches" do
    auth = OmniAuth::AuthHash.new(provider: "facebook", uid: "no-email-uid", info: OmniAuth::AuthHash::InfoHash.new)
    assert_nil User.from_omniauth(auth)
  end

  test "an OAuth account never requires a password, even in the :signup context" do
    user = User.new(username: "oauth_no_password", provider: "google_oauth2", uid: "uid-999",
                     first_name: "Ada", last_name: "Lovelace", email: "ada@example.com")
    assert user.valid?(:signup), user.errors.full_messages.join(", ")
  end

  test "a traditional (non-OAuth) signup still requires a password" do
    user = User.new(username: "no_oauth_no_password", first_name: "Ada", last_name: "Lovelace", email: "ada2@example.com")
    refute user.valid?(:signup)
    assert user.errors[:password].any?
  end

  test "password confirmation mismatch is still caught after disabling has_secure_password's built-in validations" do
    user = User.new(username: "mismatch_check", password: "password123", password_confirmation: "different")
    refute user.valid?
    assert user.errors[:password_confirmation].any?
  end

  test "uid uniqueness is scoped to provider, not globally unique" do
    User.create!(username: "first_provider_user", provider: "google_oauth2", uid: "shared-uid")

    # Same uid string, but a DIFFERENT provider -- should be allowed,
    # since uids are only meaningful within their own provider's namespace.
    other = User.new(username: "second_provider_user", provider: "facebook", uid: "shared-uid")
    assert other.valid?

    # Same uid AND same provider -- must be rejected.
    duplicate = User.new(username: "duplicate_uid_user", provider: "google_oauth2", uid: "shared-uid")
    refute duplicate.valid?
    assert duplicate.errors[:uid].any?
  end
end
