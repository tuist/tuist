import Config

alias Ecto.Adapters.SQL.Sandbox

test_port = String.to_integer(System.get_env("TUIST_REGISTRY_TEST_PORT") || "4012")
test_storage_dir = System.get_env("TUIST_REGISTRY_TEST_STORAGE_DIR") || "/tmp/test_tuist_registry"

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :sentry, dsn: nil

config :tuist_registry, Oban,
  queues: false,
  plugins: false,
  testing: :manual

config :tuist_registry, TuistRegistry.Repo,
  database: Path.expand("../test.sqlite3", __DIR__),
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2 + 10,
  busy_timeout: 30_000,
  timeout: 45_000,
  queue_target: 45_000,
  queue_interval: 45_000,
  show_sensitive_data_on_connection_error: false

config :tuist_registry, TuistRegistry.SQLiteBuffer,
  shutdown_ms: 0,
  flush_interval_ms: to_timeout(hour: 1),
  flush_timeout_ms: 50_000

config :tuist_registry, TuistRegistryWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: test_port],
  secret_key_base: "test_secret_key_base_at_least_64_characters_long_for_security_purposes",
  server: false

config :tuist_registry, :s3, registry_bucket: "test-registry-bucket"

config :tuist_registry,
  server_url: "http://localhost:8080",
  storage_dir: test_storage_dir,
  api_key: "test-secret-key"
