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

  private

  def authorize_participant!
    return if @game_session.users.include?(current_user)

    redirect_to root_path, alert: "That game isn't yours."
  end
end
