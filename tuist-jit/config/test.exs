import Config

config :tuist_jit, TuistJit.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "tuist_jit_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :tuist_jit, TuistJitWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4101],
  secret_key_base: "test_secret_key_base_only_for_tests____________________________________",
  server: false

config :tuist_jit, Oban, testing: :manual

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
