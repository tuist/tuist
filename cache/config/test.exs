import Config

config :appsignal, :config, active: false

config :cache, Cache.Guardian,
  issuer: "tuist",
  secret_key: "test_guardian_secret_key_at_least_64_characters_long_for_test_purposes"

config :cache, Cache.Repo,
  database: Path.expand("../test.sqlite3", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  show_sensitive_data_on_connection_error: false

config :cache, CacheWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_at_least_64_characters_long_for_security_purposes",
  server: false

config :cache, Oban,
  queues: false,
  plugins: false,
  testing: :manual

config :cache, :cas,
  server_url: "http://localhost:8080",
  storage_dir: "/tmp/test_cas",
  api_key: "test-secret-key"

config :cache, :req_options, plug: {Req.Test, Cache.Authentication}
config :cache, :s3, bucket: "test-bucket"

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
