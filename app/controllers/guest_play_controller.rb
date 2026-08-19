class GuestPlayController < ApplicationController
  # No require_login on purpose -- clicking "Play a Game" IS how someone
  # who isn't logged in yet gets an account, with zero form to fill in
  # first. Anyone already logged in (guest or real) just gets
  # fast-pathed into a fresh game too, so "Play a Game" always means
  # exactly that -- one click, straight into a round -- regardless of
  # who clicks it. Naming happens AFTER the round ends instead (see
  # UsersController#claim_name), not before it starts.

  # GET /play
  def new
    ensure_guest_session! unless logged_in?
    jump_into_game!
  end

  private

  # Auto-generates a unique placeholder username so play can start
  # immediately with no form -- "Guest48213", retried until it's
  # actually unique. They get a real chance to pick their own name for
  # the leaderboard right after this first game ends.
  def ensure_guest_session!
    username = nil
    loop do
      username = "Guest#{rand(10_000..999_999)}"
      break unless User.exists?(username: username.downcase)
    end

    user = User.create!(username: username, guest: true)
    session[:user_id] = user.id
  end

  # Always Beginner -- the friendliest board (smallest grid, addition
  # only) for someone who, as far as this app knows, has never played
  # before. Every difficulty runs the same 90-second clock (see
  # PuzzleGenerator::DIFFICULTY_LEVELS), so this is genuinely "a 90
  # second game" regardless. Demo mode defaults on for every new
  # account already, so the guided walkthrough just happens
  # automatically -- nothing extra to wire up here.
  def jump_into_game!
    puzzle = PuzzleGenerator.call(difficulty: PuzzleGenerator::DEFAULT_DIFFICULTY)
    game_session = GameSession.create!(mode: :solo, status: :active, puzzle: puzzle, host: current_user)
    game_session.participants.create!(user: current_user, player_number: 1)
    redirect_to solo_game_path(game_session)
  end
end
