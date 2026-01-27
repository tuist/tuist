import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PUBLIC_HOST")
  port = String.to_integer(System.get_env("PORT") || "4000")
  socket_path = System.get_env("PHX_SOCKET_PATH")

  http_config =
    case socket_path do
      nil ->
        [
          ip: {0, 0, 0, 0, 0, 0, 0, 0},
          port: port
        ]

      path ->
        File.mkdir_p!(Path.dirname(path))
        _ = File.rm(path)

        [
          ip: {:local, path},
          port: 0
        ]
    end

  sentry_dsn = System.get_env("SENTRY_DSN_CACHE")

  if sentry_dsn do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: System.get_env("SENTRY_ENV") || "production"
  end

  config :cache, Cache.Guardian,
    issuer: "tuist",
    secret_key: System.get_env("GUARDIAN_SECRET_KEY")

  config :cache, Cache.Repo,
    database: "/data/repo.sqlite",
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    show_sensitive_data_on_connection_error: false

  config :cache, CacheWeb.Endpoint,
    server: true,
    url: [host: host, port: 443, scheme: "https"],
    http: http_config,
    secret_key_base: secret_key_base

  config :cache, :oban_web_basic_auth,
    username: System.get_env("OBAN_WEB_USERNAME"),
    password: System.get_env("OBAN_WEB_PASSWORD")

  config :cache, :s3, bucket: System.get_env("S3_BUCKET") || raise("environment variable S3_BUCKET is missing")

  config :cache,
    server_url: System.get_env("SERVER_URL") || "https://tuist.dev",
    storage_dir: System.get_env("STORAGE_DIR") || raise("environment variable STORAGE_DIR is missing"),
    disk_usage_high_watermark_percent: Cache.Config.float_env("DISK_HIGH_WATERMARK_PERCENT", 85.0),
    disk_usage_target_percent: Cache.Config.float_env("DISK_TARGET_PERCENT", 70.0),
    api_key: System.get_env("TUIST_CACHE_API_KEY"),
    registry_github_token: System.get_env("REGISTRY_GITHUB_TOKEN"),
    registry_sync_allowlist: Cache.Config.list_env("REGISTRY_SYNC_ALLOWLIST"),
    registry_sync_limit: Cache.Config.int_env("REGISTRY_SYNC_LIMIT", 350),
    registry_sync_min_interval_seconds: Cache.Config.int_env("REGISTRY_SYNC_MIN_INTERVAL_SECONDS", 21_600)

  config :ex_aws, :s3,
    scheme: "https://",
    host: System.get_env("S3_HOST"),
    region: System.get_env("S3_REGION")

  config :ex_aws,
    access_key_id: System.get_env("S3_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("S3_SECRET_ACCESS_KEY"),
    region: System.get_env("S3_REGION"),
    http_client: TuistCommon.AWS.Client

  config :tuist_common, finch_name: Cache.Finch
end
