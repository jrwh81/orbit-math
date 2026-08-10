class UserStat < ApplicationRecord
  belongs_to :user

  def win_rate
    return 0.0 if games_played.zero?

    (games_won.to_f / games_played * 100).round(1)
  end
end
