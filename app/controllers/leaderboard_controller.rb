class LeaderboardController < ApplicationController
  def index
    @top_by_wins = UserStat.includes(:user).order(games_won: :desc, targets_claimed: :desc).limit(20)
  end
end
