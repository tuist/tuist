import Config

config :xcode_processor, XcodeProcessorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4004],
  secret_key_base:
    "test-only-secret-key-base-that-is-at-least-64-bytes-long-for-testing-use-only-ok",
  server: false

config :xcode_processor,
  webhook_secret: "test-webhook-secret"

config :logger, level: :warning

config :sentry, dsn: nil
