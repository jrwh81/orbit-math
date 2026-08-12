module Admin
  class UsersController < BaseController
    def index
      @users = User.includes(:user_stat).order(created_at: :desc).limit(200)
    end

    def show
      @user = User.includes(:user_stat).find(params[:id])
      @game_sessions = @user.game_sessions
                             .includes(:puzzle, :host)
                             .order(created_at: :desc)
                             .limit(50)
    end
  end
end
