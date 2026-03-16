import Config

config :flaky_fix_runner, FlakyFixRunnerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4010],
  check_origin: false,
  debug_errors: true,
  secret_key_base:
    "dev-only-secret-key-base-that-is-at-least-64-bytes-long-for-development-use-only"

config :logger, :console, format: "[$level] $message\n"

config :flaky_fix_runner,
  webhook_secret: "dev-webhook-secret",
  repo_base_dir: Path.join(System.user_home!(), "tuist-flaky-fixes"),
  skill_path: Path.expand("../../skills/skills/fix-flaky-tests/SKILL.md", __DIR__)
