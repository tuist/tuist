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

  s3_endpoint = System.get_env("S3_ENDPOINT")

  {s3_scheme, s3_host, s3_port} =
    case s3_endpoint do
      nil ->
        {"https://", System.get_env("S3_HOST"), nil}

      "" ->
        {"https://", System.get_env("S3_HOST"), nil}

      endpoint ->
        uri = URI.parse(endpoint)

        {host, port} =
          case {uri.host, uri.port} do
            {nil, _} -> {System.get_env("S3_HOST"), nil}
            {host, nil} -> {host, nil}
            {host, port} -> {host, port}
          end

        scheme = (uri.scheme || "https") <> "://"
        {scheme, host, port}
    end

  s3_access_key_id = System.get_env("S3_ACCESS_KEY_ID") || System.get_env("AWS_ACCESS_KEY_ID")
  s3_secret_access_key = System.get_env("S3_SECRET_ACCESS_KEY") || System.get_env("AWS_SECRET_ACCESS_KEY")
  s3_region = System.get_env("S3_REGION") || System.get_env("AWS_REGION")

  s3_protocol =
    case System.get_env("S3_PROTOCOL") do
      protocol when is_binary(protocol) and protocol != "" -> [String.to_atom(protocol)]
      _ -> [:http1]
    end

  s3_virtual_host =
    case System.get_env("S3_VIRTUAL_HOST") do
      val when val in ["1", "true"] -> true
      _ -> false
    end

  otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")

  s3_config =
    [
      scheme: s3_scheme,
      host: s3_host,
      region: s3_region,
      virtual_host: s3_virtual_host
    ]

  s3_config = if s3_port, do: Keyword.put(s3_config, :port, s3_port), else: s3_config

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

  config :cache, :s3,
    bucket: System.get_env("S3_BUCKET") || raise("environment variable S3_BUCKET is missing"),
    registry_bucket: System.get_env("S3_REGISTRY_BUCKET"),
    protocols: s3_protocol

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

  # Note: connect_options cannot be used with Finch
  # Connection settings are handled at the Finch pool level
  config :ex_aws, :req_opts, []
  config :ex_aws, :s3, s3_config

  config :ex_aws,
    region: s3_region,
    http_client: TuistCommon.AWS.Client

  cond do
    s3_access_key_id && s3_secret_access_key ->
      config :ex_aws,
        access_key_id: s3_access_key_id,
        secret_access_key: s3_secret_access_key

    System.get_env("AWS_WEB_IDENTITY_TOKEN_FILE") ->
      config :ex_aws,
        access_key_id: [{:awscli, "profile_name", 30}],
        secret_access_key: [{:awscli, "profile_name", 30}],
        awscli_auth_adapter: ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter

    true ->
      nil
  end

  config :tuist_common, finch_name: Cache.Finch

  if otel_endpoint do
    config :opentelemetry,
      traces_exporter: :otlp,
      span_processor: :batch,
      resource: [
        service: [name: "tuist-cache", namespace: "tuist"],
        deployment: [environment: System.get_env("DEPLOY_ENV") || "production"]
      ]

    config :opentelemetry_exporter,
      otlp_protocol: :grpc,
      otlp_endpoint: otel_endpoint
  end
end
