import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing"

  port = String.to_integer(System.get_env("PORT") || "4010")

  config :flaky_fix_runner, FlakyFixRunnerWeb.Endpoint,
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true

  config :flaky_fix_runner,
    webhook_secret: System.get_env("WEBHOOK_SECRET"),
    repo_base_dir:
      System.get_env("REPO_BASE_DIR") || Path.join(System.user_home!(), "tuist-flaky-fixes"),
    skill_path: System.get_env("SKILL_PATH")

  sentry_dsn = System.get_env("SENTRY_DSN_FLAKY_FIX_RUNNER")

  if sentry_dsn do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: System.get_env("SENTRY_ENV") || "production"
  end
end
