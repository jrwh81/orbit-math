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

  before_save { self.username = username.downcase if username.present? }
  after_create :ensure_user_stat!

  def name
    display_name.presence || username
  end

  def stat
    user_stat || ensure_user_stat!
  end

  private

  def ensure_user_stat!
    self.user_stat = UserStat.find_or_create_by!(user: self)
  end
end
