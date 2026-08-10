ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    include ActiveSupport::Testing::TimeHelpers

    parallelize(workers: :number_of_processors)

    # No fixtures directory is used on purpose -- every test builds its
    # own data with plain ActiveRecord calls (often via the real service
    # objects) so each test file reads top to bottom with no hidden state.
  end
end
