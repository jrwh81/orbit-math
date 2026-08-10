class GameChannel < ApplicationCable::Channel
  def subscribed
    game_session = GameSession.multiplayer.find_by(id: params[:game_session_id])

    if game_session && game_session.users.include?(current_user)
      stream_for game_session
    else
      reject
    end
  end
end
