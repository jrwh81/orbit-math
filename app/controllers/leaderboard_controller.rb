class LeaderboardController < ApplicationController
  def index
    # One leaderboard per difficulty, not a single combined ranking --
    # a Beginner-only player and an Expert grinder were never really
    # comparable on one list. Deliberately no .limit() here: an earlier,
    # unrelated feature on this app (the homepage's game history) caused
    # real user confusion by silently capping a list at 5, so this
    # shows everyone within a difficulty, contained in a scrollable
    # panel in the view rather than an arbitrary cutoff.
    @leaderboards = PuzzleGenerator::DIFFICULTY_LEVELS.keys.index_with do |difficulty|
      UserDifficultyStat.where(difficulty: difficulty)
                         .includes(:user)
                         .order(total_points: :desc, games_won: :desc)
    end
  end
end
