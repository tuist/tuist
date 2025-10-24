import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere.

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :cache, CacheWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :cache, CacheWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
end

# Configure Tigris S3 settings
tigris_endpoint = System.get_env("TUIST_S3_TIGRIS_ENDPOINT")

if tigris_endpoint && tigris_endpoint != "" do
  %{host: tigris_host, scheme: tigris_scheme, port: tigris_port} = URI.parse(tigris_endpoint)
  
  tigris_config = [
    scheme: "#{tigris_scheme}://",
    host: tigris_host,
    region: System.get_env("TUIST_S3_TIGRIS_REGION", "us-east-1")
  ]
  
  tigris_config = if tigris_port, do: Keyword.put(tigris_config, :port, tigris_port), else: tigris_config
  
  config :ex_aws, :s3, tigris_config
end

config :ex_aws,
  access_key_id: System.get_env("TUIST_S3_TIGRIS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("TUIST_S3_TIGRIS_SECRET_ACCESS_KEY"),
  region: System.get_env("TUIST_S3_TIGRIS_REGION", "us-east-1")


config :cache,
  s3_bucket: System.get_env("TUIST_S3_TIGRIS_BUCKET_NAME"),
  s3_endpoint: System.get_env("TUIST_S3_TIGRIS_ENDPOINT"),
  s3_virtual_host: System.get_env("TUIST_S3_VIRTUAL_HOST", "false") == "true"
