module Admin
  class GameSessionsController < BaseController
    def index
      @game_sessions = GameSession.includes(:puzzle, :host, participants: :user)
                                   .order(created_at: :desc)
                                   .limit(200)
    end

    def show
      @game_session = GameSession.includes(:puzzle, :host, participants: :user, moves: :user).find(params[:id])
    end
  end
end
