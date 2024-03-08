# frozen_string_literal: true

# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers: a minimum and maximum.
# Any libraries that use thread pools should be configured to match
# the maximum value specified for Puma. Default is set to 5 threads for minimum
# and maximum; this matches the default thread size of Active Record.
#
max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

rails_env = ENV.fetch("RAILS_ENV", "development")
environment rails_env
case rails_env
when "production", "staging", "canary"
  # If you are running more than 1 thread per process, the workers count
  # should be equal to the number of processors (CPU cores) in production.
  #
  # It defaults to 1 because it's impossible to reliably detect how many
  # CPU cores are available. Make sure to set the `WEB_CONCURRENCY` environment
  # variable to match the number of processors.
  workers_count = Integer(ENV.fetch("WEB_CONCURRENCY", 1))
  workers(workers_count) if workers_count > 1

  preload_app!
when "development"
  # Specifies a very generous `worker_timeout` so that the worker
  # isn't killed by Puma when suspended by a debugger.
  worker_timeout(3600)
end

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Only use a pidfile when requested
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

self_hosted = ENV["TUIST_CLOUD_SELF_HOSTED"] == "1"

unless self_hosted
  plugin :appsignal
  lowlevel_error_handler do |_e|
    [
      500,
      {},
      ["An error has occurred, and engineers have been informed. Please reload the page."\
        " If you continue to have problems, contact contact@tuist.io"],
    ]
  end
end
