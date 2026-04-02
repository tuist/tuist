import Config

test_postgres_db = System.get_env("TUIST_SERVER_TEST_POSTGRES_DB") || "tuist_test#{System.get_env("MIX_TEST_PARTITION")}"

test_clickhouse_db =
  System.get_env("TUIST_SERVER_TEST_CLICKHOUSE_DB") || "tuist_test#{System.get_env("MIX_TEST_PARTITION")}"

test_port = String.to_integer(System.get_env("TUIST_SERVER_TEST_PORT") || "4002")

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Prevent ExAws.Config.AuthCache from trying to fetch credentials from AWS instance metadata
config :ex_aws,
  access_key_id: "test",
  secret_access_key: "test",
  region: "us-east-1"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Disable Sentry in tests
config :sentry, dsn: nil

# Oban
config :tuist, Oban, testing: :manual

config :tuist, Tuist.ClickHouseRepo,
  hostname: "localhost",
  port: 8123,
  database: test_clickhouse_db,
  # Workaround for ClickHouse lazy materialization bug with projections
  # https://github.com/ClickHouse/ClickHouse/issues/80201
  settings: [readonly: 1, query_plan_optimize_lazy_materialization: 0]

config :tuist, Tuist.IngestRepo,
  hostname: "localhost",
  port: 8123,
  database: test_clickhouse_db,
  flush_interval_ms: 5000,
  max_buffer_size: 100_000,
  pool_size: 5,
  sync_writes: true,
  # Workaround for ClickHouse lazy materialization bug with projections
  # https://github.com/ClickHouse/ClickHouse/issues/80201
  settings: [query_plan_optimize_lazy_materialization: 0]

# Configures Bamboo API Client
config :tuist, Tuist.Mailer, adapter: Bamboo.TestAdapter

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :tuist, Tuist.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: test_postgres_db,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  queue_target: 5000,
  queue_interval: 1000

config :tuist, Tuist.Tasks, sync: true

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tuist, TuistWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: test_port],
  secret_key_base: "pbaHQK0N946e06chs5G1/RUJnkI//2QshGgUvJQkADTV3AiQHV/dXlLdjnaQxtxx",
  server: false

config :tuist,
  api_pipeline_producer_module: Broadway.DummyProducer,
  api_pipeline_producer_options: []

config :tuist,
  ecto_repos: [Tuist.Repo, Tuist.IngestRepo],
  generators: [timestamp_type: :utc_datetime],
  api_pipeline_producer_module: OffBroadwayMemory.Producer,
  api_pipeline_producer_options: [buffer: :api_data_pipeline_in_memory_buffer]
