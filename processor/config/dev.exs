import Config

config :processor, ProcessorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  check_origin: false,
  debug_errors: true,
  secret_key_base:
    "dev-only-secret-key-base-that-is-at-least-64-bytes-long-for-development-use-only"

config :logger, :console, format: "[$level] $message\n"

config :ex_aws,
  access_key_id: System.get_env("S3_ACCESS_KEY_ID", "minio"),
  secret_access_key: System.get_env("S3_SECRET_ACCESS_KEY", "minio1234"),
  http_client: TuistCommon.AWS.Client

config :ex_aws, :s3,
  scheme: System.get_env("S3_SCHEME", "http://"),
  host: System.get_env("S3_HOST", "localhost"),
  port: String.to_integer(System.get_env("S3_PORT", "9095")),
  region: System.get_env("S3_REGION", "us-east-1")

config :processor,
  webhook_secret: "dev-webhook-secret",
  s3_bucket: System.get_env("S3_BUCKET", "tuist-development")
