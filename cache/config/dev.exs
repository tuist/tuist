import Config

config :cache, Cache.Guardian,
  issuer: "tuist",
  secret_key: "development_guardian_secret_key_at_least_64_characters_long_for_dev"

config :cache, Cache.Repo,
  database: "dev.sqlite3",
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :cache, CacheWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 8087],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_at_least_64_characters_long_for_security",
  watchers: []

config :cache, :cas,
  server_url: "http://localhost:8080",
  storage_dir: "tmp/cas",
  api_key: System.get_env("TUIST_CACHE_API_KEY")

config :cache, :oban_web_basic_auth, username: "admin", password: "admin"

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :plug_init_mode, :runtime
config :phoenix, :stacktrace_depth, 20
