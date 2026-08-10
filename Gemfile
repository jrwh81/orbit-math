source "https://rubygems.org"

ruby "3.2.2"

gem "rails", "~> 7.1.3"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"

# Hotwire
gem "turbo-rails"
gem "stimulus-rails"
gem "importmap-rails"

# Assets
gem "propshaft"

# Auth
gem "bcrypt", "~> 3.1.7"

# JSON builder for API-ish responses (moves endpoint)
gem "jbuilder"

# Rails 7.1's test runner was written against minitest 5.x's API and
# breaks under minitest 6.x (ArgumentError in line_filtering.rb) --
# pin it explicitly so bundler doesn't resolve to the newest major version.
gem "minitest", "~> 5.20"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[mri windows]
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
end

# Deployment
gem "dotenv-rails", groups: %i[development test]
