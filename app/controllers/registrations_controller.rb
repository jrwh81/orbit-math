class RegistrationsController < ApplicationController
  def new
    redirect_to root_path if logged_in?
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save(context: :signup)
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Welcome, #{@user.name}!"
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def user_params
    params.require(:user).permit(:first_name, :last_name, :username, :email, :password, :password_confirmation)
  end
end
