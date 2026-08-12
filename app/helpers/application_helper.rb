module ApplicationHelper
  # The Facebook credentials work fine (verified working for the app
  # owner and anyone added as a Business Manager tester), but the app
  # isn't through Meta's Business/App Review yet, so anyone who ISN'T
  # a tester hits a dead-end error straight from Facebook if they click
  # it. Hidden from public view by default until that's sorted out --
  # flip FACEBOOK_LOGIN_PUBLIC=true (env var, no code/deploy change
  # needed beyond a restart) once the app is out of Development mode.
  def facebook_login_public?
    ENV["FACEBOOK_LOGIN_PUBLIC"] == "true"
  end
end
