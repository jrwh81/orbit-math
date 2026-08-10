max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

port ENV.fetch("PORT", 3000)

environment ENV.fetch("RAILS_ENV", "development")

pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")

workers ENV.fetch("WEB_CONCURRENCY", 0)

preload_app! if ENV.fetch("WEB_CONCURRENCY", 0).to_i > 0

plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments
# (not required for the MVP; left here for production reference).
# plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
