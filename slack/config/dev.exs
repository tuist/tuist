import Config

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :plug_init_mode, :runtime
config :phoenix, :stacktrace_depth, 20

config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true

config :slack, Slack.Repo,
  database: Path.expand("../dev.db", __DIR__),
  pool_size: 5,
  show_sensitive_data_on_connection_error: true

config :slack, SlackWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4010],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_at_least_64_characters_long_for_local_development",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:slack, ~w(--sourcemap=inline --watch)]}
  ]

config :slack, SlackWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/slack_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :slack, :admin_basic_auth,
  username: System.get_env("SLACK_ADMIN_USERNAME") || "admin",
  password: System.get_env("SLACK_ADMIN_PASSWORD") || "admin"

config :slack, :captcha,
  site_key: System.get_env("TURNSTILE_SITE_KEY"),
  secret_key: System.get_env("TURNSTILE_SECRET_KEY")

config :slack, :notifier,
  bot_token: System.get_env("SLACK_BOT_TOKEN"),
  channel_id: System.get_env("SLACK_CHANNEL_ID")

config :slack, dev_routes: true
