module Admin
  class DashboardController < BaseController
    def index
      @total_users = User.count
      @total_games = GameSession.count
      @games_by_mode = GameSession.group(:mode).count
      @games_by_status = GameSession.group(:status).count
      @games_by_difficulty = GameSession.joins(:puzzle).group("puzzles.difficulty").count
      @total_claims = Move.where(claimed: true).count

      @recent_users = User.order(created_at: :desc).limit(10)
      @recent_games = GameSession.includes(:puzzle, :host).order(created_at: :desc).limit(10)
      @active_games = GameSession.includes(:puzzle, :host).where(status: :active).order(started_at: :desc).limit(10)
    end
  end
end
