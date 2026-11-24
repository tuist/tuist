import Config

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :symptoms, Oban, testing: :manual

# Pure-module tests run without PostgreSQL: the application starts neither
# the repo nor migrations in test. test/test_helper.exs starts the repo when
# tests tagged `:db` are included.
config :symptoms, Symptoms.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "symptoms_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :symptoms, SymptomsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4201],
  secret_key_base: "test_secret_key_base_only_for_tests____________________________________",
  server: false

config :symptoms,
  api_token: "test-api-token",
  sources: [],
  pipeline_delay_seconds: 0

config :symptoms, migrate_on_boot: false, start_repo: false
