class LeaderboardController < ApplicationController
  def index
    # One leaderboard per difficulty, not a single combined ranking --
    # a Beginner-only player and an Expert grinder were never really
    # comparable on one list. Deliberately no .limit() here: an earlier,
    # unrelated feature on this app (the homepage's game history) caused
    # real user confusion by silently capping a list at 5, so this
    # shows everyone within a difficulty, contained in a scrollable
    # panel in the view rather than an arbitrary cutoff.
    #
    # Ranked by best_solo_score -- the single highest-scoring SOLO game
    # a player has ever had at this difficulty -- not total_points
    # (every point they've ever earned, summed across every game,
    # multiplayer included). A career total rewards volume; this
    # rewards the single best run, which is what a leaderboard is
    # supposed to celebrate. total_points is still the tiebreaker for
    # two players who've never bettered each other's best game.
    @leaderboards = PuzzleGenerator::DIFFICULTY_LEVELS.keys.index_with do |difficulty|
      UserDifficultyStat.where(difficulty: difficulty)
                         .includes(:user)
                         .order(best_solo_score: :desc, total_points: :desc)
    end
  end
end
