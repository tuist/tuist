import Config

alias Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :slack, Slack.Mailer, adapter: Swoosh.Adapters.Test

config :swoosh, :api_client, false

config :slack, Slack.Repo,
  database: Path.expand("../test.db", __DIR__),
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2 + 10,
  busy_timeout: 30_000

config :slack, SlackWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4011],
  secret_key_base: "test_secret_key_base_at_least_64_characters_long_for_security_purposes",
  server: false

config :slack, :admin_basic_auth,
  username: "admin",
  password: "admin"

config :slack, :captcha, site_key: nil, secret_key: nil
config :slack, :notifier, bot_token: nil, channel_id: nil
