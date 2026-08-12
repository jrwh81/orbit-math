class HomeController < ApplicationController
  def index
    if logged_in?
      @open_games = GameSession.multiplayer.waiting.where.not(host: current_user)
                                .includes(:puzzle, :host).order(created_at: :desc).limit(5)
      # Deliberately unlimited for now -- was capped at 5, which silently
      # hid anything older than a player's 5 most recent games. The
      # .game-list-scroll container (contained, scrolls) already handles
      # a long list without breaking the page layout; if this list grows
      # large enough to matter for query performance, real pagination is
      # the next step, not a limit that hides real history again.
      @recent_games = current_user.game_sessions
                                   .includes(:puzzle, participants: :user)
                                   .order(created_at: :desc)
      @stat = current_user.stat
    end
  end
end
