class HomeController < ApplicationController
  def index
    if logged_in?
      @open_games = GameSession.multiplayer.waiting.where.not(host: current_user)
                                .includes(:puzzle, :host).order(created_at: :desc).limit(5)
      # Site-wide -- every game ever played, by any player, not just the
      # current user's own. Deliberately unlimited: if this grows large
      # enough to matter for query performance, real pagination is the
      # next step, not a limit that silently hides games again. The
      # .game-list-scroll container (contained, scrolls) already keeps
      # a long list from breaking the page layout in the meantime.
      @all_games = GameSession.includes(:puzzle, participants: :user)
                               .order(created_at: :desc)
      @stat = current_user.stat
    end
  end
end
