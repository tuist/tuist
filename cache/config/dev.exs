import Config

# For development, we disable any cache and enable
# debugging and code reloading.
config :cache, CacheWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 8087],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_at_least_64_characters_long_for_security",
  watchers: []

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :cache, :cas,
  server_url: "http://localhost:8080",
  storage_dir: "tmp/cas"
