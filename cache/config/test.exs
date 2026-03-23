import Config

alias Ecto.Adapters.SQL.Sandbox

test_port = String.to_integer(System.get_env("TUIST_CACHE_TEST_PORT") || "4002")
test_storage_dir = System.get_env("TUIST_CACHE_TEST_STORAGE_DIR") || "/tmp/test_cas"

config :cache, Cache.DistributedKV.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cache_test",
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2 + 10,
  timeout: 45_000,
  queue_target: 45_000,
  queue_interval: 45_000

config :cache, Cache.Guardian,
  issuer: "tuist",
  secret_key: "test_guardian_secret_key_at_least_64_characters_long_for_test_purposes"

config :cache, Cache.KeyValueRepo,
  database: Path.expand("../test_key_value.sqlite3", __DIR__),
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2 + 10,
  busy_timeout: 30_000,
  timeout: 45_000,
  queue_target: 45_000,
  queue_interval: 45_000,
  show_sensitive_data_on_connection_error: false

config :cache, Cache.Repo,
  database: Path.expand("../test.sqlite3", __DIR__),
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2 + 10,
  busy_timeout: 30_000,
  timeout: 45_000,
  queue_target: 45_000,
  queue_interval: 45_000,
  show_sensitive_data_on_connection_error: false

config :cache, Cache.SQLiteBuffer, shutdown_ms: 0, flush_interval_ms: to_timeout(hour: 1), flush_timeout_ms: 50_000

config :cache, CacheWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: test_port],
  secret_key_base: "test_secret_key_base_at_least_64_characters_long_for_security_purposes",
  server: false

config :cache, Oban,
  queues: false,
  plugins: false,
  testing: :manual

config :cache, :req_options, plug: {Req.Test, Cache.Authentication}

config :cache, :s3,
  bucket: "test-bucket",
  xcode_cache_bucket: "test-xcode-cache-bucket",
  registry_bucket: "test-registry-bucket"

config :cache,
  server_url: "http://localhost:8080",
  storage_dir: test_storage_dir,
  api_key: "test-secret-key",
  key_value_mode: :local,
  distributed_kv_node_name: "test-node"

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :sentry, dsn: nil
