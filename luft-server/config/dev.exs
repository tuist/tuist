import Config

config :logger, :console, format: "[$level] $message\n"

config :luft_server, LuftServer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "luft_server_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :luft_server, LuftServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4200],
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_only_for_local_development_do_not_use_in_prod_____",
  watchers: []

# A local Tuist server (`server/`, `mise run dev`) with the Luft server client
# configured; see the README.
config :luft_server,
  tuist_issuer: System.get_env("TUIST_URL", "http://localhost:8080"),
  public_url: "http://localhost:4200",
  oauth_client_id: System.get_env("LUFT_SERVER_OAUTH_CLIENT_ID"),
  oauth_client_secret: System.get_env("LUFT_SERVER_OAUTH_CLIENT_SECRET")

config :phoenix, :plug_init_mode, :runtime
config :phoenix, :stacktrace_depth, 20
config :luft_server, migrate_on_boot: false
config :luft_server, secure_cookies: false
