ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    include ActiveSupport::Testing::TimeHelpers

    # Parallel test workers are forked processes, and forking a process
    # that already holds an open Postgres connection is a known
    # fork-safety hazard -- the child can inherit a corrupted/shared
    # socket to the DB and segfault outright rather than raising a clean
    # Ruby error (this is exactly what happened: a crash report full of
    # raw memory addresses, no readable backtrace, network-framework
    # frames in the stack). This suite is nowhere near large enough for
    # parallelization to matter for speed, so it's simplest to just
    # disable it rather than chase fork-safety across the pg gem.
    parallelize(workers: 1)

    # No fixtures directory is used on purpose -- every test builds its
    # own data with plain ActiveRecord calls (often via the real service
    # objects) so each test file reads top to bottom with no hidden state.
  end
end
