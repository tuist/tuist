import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  port = String.to_integer(System.get_env("PORT") || "4002")

  config :processor, ProcessorWeb.Endpoint,
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true

  s3_endpoint = System.get_env("S3_ENDPOINT") || raise "S3_ENDPOINT is required"
  %{host: s3_host, scheme: s3_scheme, port: s3_port} = URI.parse(s3_endpoint)

  s3_config =
    [
      scheme: "#{s3_scheme}://",
      host: s3_host,
      region: System.get_env("S3_REGION") || "auto",
      bucket_as_host: true
    ]
    |> then(&if(is_nil(s3_port), do: &1, else: Keyword.put(&1, :port, s3_port)))

  config :ex_aws, :s3, s3_config

  config :ex_aws,
    secret_access_key: System.get_env("S3_SECRET_ACCESS_KEY"),
    access_key_id: System.get_env("S3_ACCESS_KEY_ID"),
    http_client: TuistCommon.AWS.Client

  config :processor,
    webhook_secret: System.get_env("WEBHOOK_SECRET"),
    s3_bucket: System.get_env("S3_BUCKET")
end
