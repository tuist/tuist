import Config

test_port = String.to_integer(System.get_env("TUIST_REGISTRY_TEST_PORT") || "4012")

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :sentry, dsn: nil

config :tuist_registry, TuistRegistryWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: test_port],
  secret_key_base: "test_secret_key_base_at_least_64_characters_long_for_security_purposes",
  server: false

config :tuist_registry, :s3, registry_bucket: "test-registry-bucket"

config :tuist_registry,
  server_url: "http://localhost:8080"
