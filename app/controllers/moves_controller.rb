class MovesController < ApplicationController
  before_action :require_login
  before_action :set_game_session

  # POST /solo_games/:solo_game_id/moves
  # POST /multiplayer/:multiplayer_game_id/moves
  #
  # Params: { coords: [[0,0],[0,1],...], ops: ["+","*",...] }
  def create
    unless @game_session.users.include?(current_user)
      return render json: { error: "not a participant" }, status: :forbidden
    end

    finalize_if_time_expired!

    if @game_session.completed?
      payload = GameStatePresenter.new(@game_session).as_json
      return render json: { result: { success: false, message: "Time's up!", user_id: current_user.id }, game: payload }
    end

    result = ClaimService.call(
      game_session: @game_session,
      user: current_user,
      coords: normalized_coords,
      ops: params[:ops].to_a
    )

    @game_session.reload
    finalize_if_time_expired! # in case this claim landed right at (or after) the buzzer

    payload = GameStatePresenter.new(@game_session).as_json

    if @game_session.multiplayer?
      GameChannel.broadcast_to(@game_session, event: "move_result", result: move_result_json(result), game: payload)
    end

    render json: { result: move_result_json(result), game: payload }
  end

  private

  def finalize_if_time_expired!
    return unless @game_session.time_expired? && !@game_session.completed?

    GameCompletionService.call(@game_session)
  end

  def set_game_session
    @game_session =
      if params[:solo_game_id]
        GameSession.solo.find(params[:solo_game_id])
      else
        GameSession.multiplayer.find(params[:multiplayer_game_id])
      end
  end

  # Client sends [[row, col], [row, col], ...]; coerce defensively to
  # integers so a malformed request can't blow up ChainEvaluator.
  def normalized_coords
    Array(params[:coords]).map do |pair|
      Array(pair).first(2).map { |v| Integer(v) rescue nil }
    end
  rescue StandardError
    []
  end

  def move_result_json(result)
    {
      success: result.success?,
      value: result.value,
      message: result.message,
      target_id: result.target && result.target["id"],
      points: result.points,
      multiplier: result.multiplier,
      chain_length: result.chain_length,
      chain_bonus: result.chain_bonus,
      user_id: current_user.id
    }
  end
end
