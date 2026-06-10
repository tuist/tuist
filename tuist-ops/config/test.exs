import Config

config :tuist_ops, TuistOps.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "tuist_ops_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :tuist_ops, TuistOpsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4101],
  secret_key_base: "test_secret_key_base_only_for_tests____________________________________",
  server: false

config :tuist_ops, Oban, testing: :manual

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
