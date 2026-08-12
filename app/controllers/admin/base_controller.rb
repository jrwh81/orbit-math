module Admin
  # Every controller under app/controllers/admin inherits from this, so
  # access control lives in exactly one place. A non-admin (including a
  # logged-out visitor) is bounced to the homepage with no indication of
  # what's behind the wall beyond "you don't have access" -- deliberately
  # vague rather than something like "admin area" that hints at what
  # exists.
  class BaseController < ApplicationController
    before_action :require_admin

    layout "admin"

    private

    def require_admin
      return if logged_in? && current_user.admin?

      redirect_to root_path, alert: "You don't have access to that."
    end
  end
end
