class User < ApplicationRecord
  has_secure_password

  has_many :participants, dependent: :destroy
  has_many :game_sessions, through: :participants
  has_many :hosted_game_sessions, class_name: "GameSession", foreign_key: :host_id, dependent: :destroy, inverse_of: :host
  has_many :moves, dependent: :destroy
  has_one :user_stat, dependent: :destroy

  validates :username, presence: true, uniqueness: { case_sensitive: false },
                        format: { with: /\A[a-zA-Z0-9_]{3,20}\z/, message: "3-20 letters, numbers, underscores only" }
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true,
                     format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { email.present? }
  validates :password, length: { minimum: 6 }, allow_nil: true

  # These only apply when a User is saved with the :signup validation
  # context (see RegistrationsController), NOT on ordinary .create!/.save
  # calls -- which is exactly what every test, seed, and admin-created
  # user in this app uses. Making these a blanket model-level requirement
  # would have broken dozens of existing `User.create!(username:, password:)`
  # call sites that never set an email/name (email in particular has been
  # optional since day one). Rails validation contexts let the signup
  # FORM genuinely require these fields without touching any of that.
  validates :first_name, presence: true, length: { maximum: 50 }, on: :signup
  validates :last_name, presence: true, length: { maximum: 50 }, on: :signup
  validates :email, presence: true, on: :signup

  before_save { self.username = username.downcase if username.present? }
  after_create :ensure_user_stat!

  # The ONLY name ever shown to other players -- leaderboard, in-game
  # scoreboard, "hosted by" labels, nav bar, everywhere. Deliberately
  # always the username, never a real name, for privacy: the leaderboard
  # in particular is a fully public page, viewable without logging in.
  # See full_name for the admin-only real-name display.
  def name
    username
  end

  # First + last name, admin-only. Never shown to other players -- see
  # the comment on #name for why. Returns nil (not "") if both are
  # blank, e.g. for accounts created before this field existed.
  def full_name
    [first_name, last_name].reject(&:blank?).join(" ").presence
  end

  def stat
    user_stat || ensure_user_stat!
  end

  private

  def ensure_user_stat!
    self.user_stat = UserStat.find_or_create_by!(user: self)
  end
end
