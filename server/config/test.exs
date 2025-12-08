import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Oban
config :tuist, Oban, testing: :inline

config :tuist, Tuist.ClickHouseRepo,
  hostname: "localhost",
  port: 8123,
  database: "tuist_test#{System.get_env("MIX_TEST_PARTITION")}",
  # Workaround for ClickHouse lazy materialization bug with projections
  # https://github.com/ClickHouse/ClickHouse/issues/80201
  settings: [query_plan_optimize_lazy_materialization: 0]

config :tuist, Tuist.IngestRepo,
  hostname: "localhost",
  port: 8123,
  database: "tuist_test#{System.get_env("MIX_TEST_PARTITION")}",
  flush_interval_ms: 5000,
  max_buffer_size: 100_000,
  pool_size: 5,
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
  database: "tuist_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  queue_target: 5000,
  queue_interval: 1000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tuist, TuistWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
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
