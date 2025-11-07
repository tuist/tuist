import Config

config :cache, Cache.PromEx,
  metrics_server: [
    port: 9091,
    auth_strategy: :none
  ]

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST")
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :appsignal, :config,
    push_api_key: System.get_env("APPSIGNAL_PUSH_API_KEY"),
    env: System.get_env("APPSIGNAL_ENV")

  config :cache, Cache.Repo,
    database: "/cas/repo.sqlite",
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    show_sensitive_data_on_connection_error: false

  config :cache, CacheWeb.Endpoint,
    server: true,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :cache, :cas,
    server_url: System.get_env("SERVER_URL") || raise("environment variable SERVER_URL is missing"),
    storage_dir: System.get_env("CAS_STORAGE_DIR") || raise("environment variable CAS_STORAGE_DIR is missing")

  config :cache, :s3, bucket: System.get_env("S3_BUCKET") || raise("environment variable S3_BUCKET is missing")

  config :ex_aws, :s3,
    scheme: "https://",
    host: System.get_env("S3_HOST"),
    region: System.get_env("S3_REGION")

  config :ex_aws,
    access_key_id: System.get_env("S3_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("S3_SECRET_ACCESS_KEY"),
    region: System.get_env("S3_REGION")
end
