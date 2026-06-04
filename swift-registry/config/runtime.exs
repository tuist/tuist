import Config

if config_env() == :dev do
  port = String.to_integer(System.get_env("TUIST_SWIFT_REGISTRY_PORT") || "8091")
  server_url = System.get_env("TUIST_SWIFT_REGISTRY_SERVER_URL") || "http://localhost:8080"

  config :swift_registry, SwiftRegistryWeb.Endpoint,
    url: [host: "localhost", port: port, scheme: "http"],
    http: [ip: {0, 0, 0, 0}, port: port]

  config :swift_registry, server_url: server_url
end

if config_env() == :prod do
  env = fn names ->
    names
    |> List.wrap()
    |> Enum.find_value(fn name ->
      case System.get_env(name) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

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
          port: port,
          thousand_island_options: [
            transport_options: [backlog: 16_384]
          ]
        ]

      path ->
        File.mkdir_p!(Path.dirname(path))

        suffix = Regex.replace(~r/[^A-Za-z0-9._-]/, System.fetch_env!("HOSTNAME"), "-")

        unique_path = Path.rootname(path) <> "-#{suffix}" <> Path.extname(path)
        _ = File.rm(unique_path)
        Application.put_env(:swift_registry, :socket_path, unique_path)

        [
          ip: {:local, unique_path},
          port: 0,
          thousand_island_options: [
            transport_options: [backlog: 16_384]
          ]
        ]
    end

  sentry_dsn = env.(["SENTRY_DSN_SWIFT_REGISTRY", "SENTRY_DSN_CACHE"])

  if sentry_dsn do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: System.get_env("SENTRY_ENV") || "production"
  end

  s3_endpoint = System.get_env("S3_ENDPOINT")

  {s3_scheme, s3_host, s3_port} =
    case s3_endpoint do
      nil ->
        {"https://", env.("S3_HOST"), nil}

      "" ->
        {"https://", env.("S3_HOST"), nil}

      endpoint ->
        uri = URI.parse(endpoint)

        {host, port} =
          case {uri.host, uri.port} do
            {nil, _} -> {env.("S3_HOST"), nil}
            {host, nil} -> {host, nil}
            {host, port} -> {host, port}
          end

        scheme = (uri.scheme || "https") <> "://"
        {scheme, host, port}
    end

  s3_access_key_id = env.(["S3_ACCESS_KEY_ID", "AWS_ACCESS_KEY_ID"])
  s3_secret_access_key = env.(["S3_SECRET_ACCESS_KEY", "AWS_SECRET_ACCESS_KEY"])
  s3_region = env.(["S3_REGION", "AWS_REGION"])

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

  otel_endpoint = env.("OTEL_EXPORTER_OTLP_ENDPOINT")

  s3_config =
    [
      scheme: s3_scheme,
      host: s3_host,
      region: s3_region,
      virtual_host: s3_virtual_host
    ]

  s3_config = if s3_port, do: Keyword.put(s3_config, :port, s3_port), else: s3_config

  # Note: connect_options cannot be used with Finch
  # Connection settings are handled at the Finch pool level
  config :ex_aws, :req_opts, []
  config :ex_aws, :s3, s3_config

  config :ex_aws,
    region: s3_region,
    http_client: TuistCommon.AWS.Client

  config :swift_registry, SwiftRegistry.Repo,
    database: "/data/repo.sqlite",
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    show_sensitive_data_on_connection_error: false

  config :swift_registry, SwiftRegistryWeb.Endpoint,
    server: true,
    url: [host: host, port: 443, scheme: "https"],
    http: http_config,
    secret_key_base: secret_key_base

  config :swift_registry, :oban_web_basic_auth,
    username: System.get_env("OBAN_WEB_USERNAME"),
    password: System.get_env("OBAN_WEB_PASSWORD")

  config :swift_registry, :s3,
    registry_bucket: env.("S3_REGISTRY_BUCKET") || raise("environment variable S3_REGISTRY_BUCKET is missing"),
    protocols: s3_protocol,
    ca_cert_pem: env.(["S3_CA_CERT_PEM", "TUIST_S3_CA_CERT_PEM"])

  config :swift_registry,
    server_url: env.("SERVER_URL") || "https://tuist.dev",
    server_ca_cert_pem: env.(["SERVER_CA_CERT_PEM", "TUIST_SERVER_CA_CERT_PEM"]),
    storage_dir: env.("STORAGE_DIR") || raise("environment variable STORAGE_DIR is missing"),
    disk_usage_high_watermark_percent: SwiftRegistry.Config.float_env("DISK_HIGH_WATERMARK_PERCENT", 75.0),
    disk_usage_target_percent: SwiftRegistry.Config.float_env("DISK_TARGET_PERCENT", 60.0),
    api_key: env.(["TUIST_SWIFT_REGISTRY_API_KEY", "TUIST_CACHE_API_KEY"]),
    analytics_failure_threshold: SwiftRegistry.Config.int_env("ANALYTICS_FAILURE_THRESHOLD", 3),
    analytics_cooldown_ms: SwiftRegistry.Config.int_env("ANALYTICS_COOLDOWN_MS", 60_000),
    analytics_receive_timeout_ms: SwiftRegistry.Config.int_env("ANALYTICS_RECEIVE_TIMEOUT_MS", 2_000),
    analytics_pool_timeout_ms: SwiftRegistry.Config.int_env("ANALYTICS_POOL_TIMEOUT_MS", 1_000),
    registry_github_token: env.("REGISTRY_GITHUB_TOKEN"),
    registry_sync_enabled: SwiftRegistry.Config.bool_env("REGISTRY_SYNC_ENABLED", true),
    registry_sync_allowlist: SwiftRegistry.Config.list_env("REGISTRY_SYNC_ALLOWLIST")

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

  config :tuist_common, finch_name: SwiftRegistry.Finch

  if otel_endpoint do
    config :opentelemetry,
      traces_exporter: :otlp,
      span_processor: :batch,
      resource: [
        service: [name: "tuist-swift-registry", namespace: "tuist"],
        deployment: [environment: System.get_env("DEPLOY_ENV") || "production"]
      ]

    config :opentelemetry_exporter,
      otlp_protocol: :grpc,
      otlp_endpoint: otel_endpoint
  end
end
