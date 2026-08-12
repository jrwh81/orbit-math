class HomeController < ApplicationController
  def index
    if logged_in?
      @open_games = GameSession.multiplayer.waiting.where.not(host: current_user)
                                .includes(:puzzle, :host).order(created_at: :desc).limit(5)
      @recent_games = current_user.game_sessions
                                   .includes(:puzzle, participants: :user)
                                   .order(created_at: :desc).limit(5)
      @stat = current_user.stat
    end
  end
end
