class Participant < ApplicationRecord
  belongs_to :game_session
  belongs_to :user

  validates :player_number, inclusion: { in: [1, 2] }
  validates :user_id, uniqueness: { scope: :game_session_id }
  validates :player_number, uniqueness: { scope: :game_session_id }
end
