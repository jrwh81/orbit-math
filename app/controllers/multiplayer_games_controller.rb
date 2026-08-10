class MultiplayerGamesController < ApplicationController
  before_action :require_login
  before_action :set_game_session, only: [:show, :start, :finish]

  def index
    @open_games = GameSession.multiplayer.waiting
                              .where.not(host: current_user)
                              .order(created_at: :desc)
    @my_games = current_user.game_sessions.multiplayer.order(created_at: :desc).limit(10)
    @difficulty_levels = PuzzleGenerator.levels
  end

  def create
    difficulty = PuzzleGenerator::DIFFICULTY_LEVELS.key?(params[:difficulty]) ? params[:difficulty] : PuzzleGenerator::DEFAULT_DIFFICULTY
    puzzle = PuzzleGenerator.call(difficulty: difficulty)
    game_session = GameSession.create!(mode: :multiplayer, status: :waiting, puzzle: puzzle, host: current_user)
    game_session.participants.create!(user: current_user, player_number: 1)

    redirect_to multiplayer_game_path(game_session)
  end

  def join
    game_session = GameSession.multiplayer.find_by(join_code: params[:code].to_s.strip.upcase)

    if game_session.nil?
      redirect_to multiplayer_games_path, alert: "No open game found with that code." and return
    end

    if game_session.users.include?(current_user)
      redirect_to multiplayer_game_path(game_session) and return
    end

    if game_session.participants.count >= 2
      redirect_to multiplayer_games_path, alert: "That game is already full." and return
    end

    game_session.participants.create!(user: current_user, player_number: 2)
    GameChannel.broadcast_to(game_session, event: "opponent_joined", players: player_names(game_session))

    redirect_to multiplayer_game_path(game_session)
  end

  def show
    authorize_participant!
  end

  def start
    unless @game_session.host_id == current_user.id
      redirect_to multiplayer_game_path(@game_session), alert: "Only the host can start the game." and return
    end

    unless @game_session.participants.count == 2
      redirect_to multiplayer_game_path(@game_session), alert: "Waiting for an opponent to join." and return
    end

    @game_session.update!(status: :active, started_at: Time.current)
    GameChannel.broadcast_to(@game_session, event: "game_started", game: GameStatePresenter.new(@game_session).as_json)

    redirect_to multiplayer_game_path(@game_session)
  end

  # POST /multiplayer/:id/finish
  #
  # Called by whichever client's own countdown hits zero first.
  # Idempotent, and broadcasts the final state to both players so a
  # slightly-lagging opponent's clock still ends in sync rather than
  # ticking on past zero waiting for its own timer to fire.
  def finish
    unless @game_session.users.include?(current_user)
      return render json: { error: "not a participant" }, status: :forbidden
    end

    GameCompletionService.call(@game_session) if @game_session.active? && !@game_session.completed?

    payload = GameStatePresenter.new(@game_session).as_json
    GameChannel.broadcast_to(
      @game_session,
      event: "move_result",
      result: { success: false, message: "Time's up!", user_id: current_user.id },
      game: payload
    )

    render json: payload
  end

  private

  def set_game_session
    @game_session = GameSession.multiplayer.find(params[:id])
  end

  def authorize_participant!
    return if @game_session.users.include?(current_user)

    redirect_to multiplayer_games_path, alert: "You're not part of that game."
  end

  def player_names(game_session)
    game_session.participants.includes(:user).order(:player_number).map { |p| p.user.name }
  end
end
