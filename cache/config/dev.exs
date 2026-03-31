import Config

config :cache, Cache.Guardian,
  issuer: "tuist",
  secret_key: "development_guardian_secret_key_at_least_64_characters_long_for_dev"

config :cache, Cache.KeyValueRepo,
  database: "dev_key_value.sqlite3",
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :cache, Cache.Repo,
  database: "dev.sqlite3",
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :cache, CacheWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 8087],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_at_least_64_characters_long_for_security",
  watchers: []

config :cache, :oban_web_basic_auth, username: "admin", password: "admin"

config :cache, :s3,
  bucket: "tuist-development",
  xcode_cache_bucket: nil,
  registry_bucket: nil,
  protocols: [:http1]

config :cache,
  server_url: "http://localhost:8080",
  storage_dir: System.get_env("STORAGE_DIR") || "/tmp/cache",
  api_key: System.get_env("TUIST_CACHE_API_KEY")

config :ex_aws, :s3,
  scheme: "http://",
  host: "localhost",
  port: 9095,
  region: "us-east-1"

config :ex_aws,
  access_key_id: System.get_env("S3_ACCESS_KEY_ID", "minio"),
  secret_access_key: System.get_env("S3_SECRET_ACCESS_KEY", "minio1234")

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :plug_init_mode, :runtime
config :phoenix, :stacktrace_depth, 20
