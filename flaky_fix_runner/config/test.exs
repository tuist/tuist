import Config

config :flaky_fix_runner, FlakyFixRunnerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4011],
  secret_key_base:
    "test-only-secret-key-base-that-is-at-least-64-bytes-long-for-testing-use-only-ok",
  server: false

config :flaky_fix_runner,
  webhook_secret: "test-webhook-secret",
  repo_base_dir: "/tmp/flaky-fix-runner-tests",
  skill_path: nil

config :logger, level: :warning

config :sentry, dsn: nil
