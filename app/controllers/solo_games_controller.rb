class SoloGamesController < ApplicationController
  before_action :require_login

  def new
    @difficulty_levels = PuzzleGenerator.levels
  end

  def create
    # PuzzleGenerator already falls back to a safe default for an
    # unknown/missing difficulty, but resolving it here too means the
    # game_session's puzzle and this controller always agree on what was
    # actually requested (useful if we want to echo it back later).
    difficulty = PuzzleGenerator::DIFFICULTY_LEVELS.key?(params[:difficulty]) ? params[:difficulty] : PuzzleGenerator::DEFAULT_DIFFICULTY
    puzzle = PuzzleGenerator.call(difficulty: difficulty)

    game_session = GameSession.create!(
      mode: :solo,
      status: :active,
      puzzle: puzzle,
      host: current_user
    )
    game_session.participants.create!(user: current_user, player_number: 1)

    redirect_to solo_game_path(game_session)
  end

  def show
    @game_session = GameSession.solo.find(params[:id])
    authorize_participant!
    # Seeds the demo walkthrough's first step synchronously with the
    # initial page render, so it can start the instant the board is on
    # screen instead of waiting on a follow-up fetch. "Show me again"
    # later in the same session reuses #demo_path for a fresh one.
    @demo_path = demo_path_for(@game_session) if show_demo?
  end

  # POST /solo_games/:id/finish
  #
  # Called by the client the instant its own countdown hits zero.
  # Idempotent -- if the game is already completed (e.g. this fired
  # slightly after a move request already finalized it), this just
  # returns the current state without double-finalizing.
  def finish
    @game_session = GameSession.solo.find(params[:id])

    unless @game_session.users.include?(current_user)
      return render json: { error: "not a participant" }, status: :forbidden
    end

    GameCompletionService.call(@game_session) if @game_session.active? && !@game_session.completed?

    render json: GameStatePresenter.new(@game_session).as_json
  end

  # GET /solo_games/:id/demo_path
  #
  # Used by the client-side demo walkthrough (solo only) to find a real,
  # currently-solvable chain on THIS board to guide the player through --
  # never a fabricated example. Recomputed fresh on every call rather
  # than cached, so "show me another one" after the board has moved on
  # always points at a chain that's actually still sitting there.
  def demo_path
    @game_session = GameSession.solo.find(params[:id])

    unless @game_session.users.include?(current_user)
      return render json: { error: "not a participant" }, status: :forbidden
    end

    render json: demo_path_for(@game_session)
  end

  private

  def show_demo?
    current_user.demo_mode_enabled && @game_session.active?
  end

  # Picks the first currently-solvable active target and returns the
  # exact chain that solves it -- shared by both #show (seeding the
  # initial walkthrough) and #demo_path (fetched fresh for "do it
  # again", since the original chain's cells get replaced once claimed).
  def demo_path_for(game_session)
    target = game_session.active_targets.find { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
    return { available: false } unless target

    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    {
      available: true,
      target_id: target["id"],
      target_value: target["value"],
      coords: path[:coords],
      ops: path[:ops]
    }
  end

  def authorize_participant!
    return if @game_session.users.include?(current_user)

    redirect_to root_path, alert: "That game isn't yours."
  end
end
