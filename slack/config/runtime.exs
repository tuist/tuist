import Config

if System.get_env("PHX_SERVER") do
  config :slack, SlackWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      Point it at a persistent disk, for example /data/slack.db.
      """

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "slack.tuist.dev"
  port = String.to_integer(System.get_env("PORT") || "4000")

  admin_username =
    System.get_env("SLACK_ADMIN_USERNAME") ||
      raise "environment variable SLACK_ADMIN_USERNAME is missing"

  admin_password =
    System.get_env("SLACK_ADMIN_PASSWORD") ||
      raise "environment variable SLACK_ADMIN_PASSWORD is missing"

  mailer_from_name = System.get_env("SLACK_MAILER_FROM_NAME") || "Tuist"

  mailer_from_email =
    System.get_env("SLACK_MAILER_FROM_EMAIL") ||
      raise "environment variable SLACK_MAILER_FROM_EMAIL is missing"

  turnstile_site_key =
    System.get_env("TURNSTILE_SITE_KEY") ||
      raise "environment variable TURNSTILE_SITE_KEY is missing"

  turnstile_secret_key =
    System.get_env("TURNSTILE_SECRET_KEY") ||
      raise "environment variable TURNSTILE_SECRET_KEY is missing"

  config :slack, Slack.Mailer,
    adapter: Swoosh.Adapters.Mailgun,
    api_key: System.get_env("MAILGUN_API_KEY") || raise("environment variable MAILGUN_API_KEY is missing"),
    domain: System.get_env("MAILGUN_DOMAIN") || "mail.tuist.dev",
    base_url: System.get_env("MAILGUN_BASE_URL") || "https://api.eu.mailgun.net/v3"

  config :slack, Slack.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    show_sensitive_data_on_connection_error: false

  config :slack, SlackWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :slack, :admin_basic_auth,
    username: admin_username,
    password: admin_password

  config :slack, :captcha,
    site_key: turnstile_site_key,
    secret_key: turnstile_secret_key

  config :slack, :mailer_from, {mailer_from_name, mailer_from_email}

  config :slack, :notifier,
    bot_token: System.get_env("SLACK_BOT_TOKEN") || raise("environment variable SLACK_BOT_TOKEN is missing"),
    channel_id: System.get_env("SLACK_CHANNEL_ID") || raise("environment variable SLACK_CHANNEL_ID is missing"),
    admin_url: "https://#{host}/admin/invitations"
end
