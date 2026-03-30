import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  port = String.to_integer(System.get_env("PORT") || "4003")

  config :xcode_processor, XcodeProcessorWeb.Endpoint,
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true

  s3_endpoint = System.get_env("S3_ENDPOINT") || raise "S3_ENDPOINT is required"
  s3_uri = URI.parse(s3_endpoint)
  s3_scheme = (s3_uri.scheme || "https") <> "://"
  s3_host = s3_uri.host

  s3_default_port =
    case s3_uri.scheme do
      "https" -> 443
      "http" -> 80
      _ -> nil
    end

  s3_port = if s3_uri.port != s3_default_port, do: s3_uri.port, else: nil

  s3_virtual_host = System.get_env("S3_VIRTUAL_HOST", "false") == "true"
  s3_bucket_as_host = System.get_env("S3_BUCKET_AS_HOST", "false") == "true"

  s3_config =
    [
      scheme: s3_scheme,
      host: s3_host,
      region: System.get_env("S3_REGION") || "auto",
      virtual_host: s3_virtual_host,
      bucket_as_host: s3_bucket_as_host
    ]

  s3_config = if s3_port, do: Keyword.put(s3_config, :port, s3_port), else: s3_config

  config :ex_aws, :req_opts, []
  config :ex_aws, :s3, s3_config

  config :ex_aws,
    region: System.get_env("S3_REGION") || "auto",
    secret_access_key: System.get_env("S3_SECRET_ACCESS_KEY"),
    access_key_id: System.get_env("S3_ACCESS_KEY_ID"),
    http_client: TuistCommon.AWS.Client

  config :xcode_processor,
    webhook_secret: System.get_env("WEBHOOK_SECRET"),
    s3_bucket: System.get_env("S3_BUCKET")

  sentry_dsn = System.get_env("SENTRY_DSN_XCODE_PROCESSOR")

  if sentry_dsn do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: System.get_env("DEPLOY_ENV") || "production"
  end

  otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")

  if otel_endpoint do
    config :opentelemetry,
      traces_exporter: :otlp,
      span_processor: :batch,
      resource: [
        service: [name: "tuist-xcode-processor", namespace: "tuist"],
        deployment: [environment: System.get_env("DEPLOY_ENV") || "production"]
      ]

    config :opentelemetry_exporter,
      otlp_protocol: :grpc,
      otlp_endpoint: otel_endpoint
  end
end
