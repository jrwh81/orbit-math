class SessionsController < ApplicationController
  def new
    redirect_to root_path if logged_in?
  end

  def create
    user = User.find_by(username: params[:username].to_s.downcase)

    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome back, #{user.name}!"
    else
      flash.now[:alert] = "Invalid username or password"
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    session[:user_id] = nil
    redirect_to root_path, notice: "Logged out."
  end
end
