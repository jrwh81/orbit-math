require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module OrbitMath
  class Application < Rails::Application
    config.load_defaults 7.1

    config.autoload_lib(ignore: %w[assets tasks])

    # Time zone
    config.time_zone = "Eastern Time (US & Canada)"

    # ---------------------------------------------------------------------
    # Game / brand configuration.
    #
    # This is the ONE place that controls the displayed name of the game
    # everywhere in the app (page titles, homepage, emails, PWA manifest).
    # Change GAME_NAME below (or set the GAME_NAME environment variable in
    # production) and the entire app rebrands itself instantly.
    # ---------------------------------------------------------------------
    config.x.game.name        = ENV.fetch("GAME_NAME", "OrbitMath")
    config.x.game.tagline     = ENV.fetch("GAME_TAGLINE", "Link numbers. Beat the belt. Race for the loot.")
    config.x.game.grid_size   = ENV.fetch("GAME_GRID_SIZE", 5).to_i
    config.x.game.min_value   = 1
    config.x.game.max_value   = 9
    config.x.game.target_count = ENV.fetch("GAME_TARGET_COUNT", 6).to_i
  end
end
