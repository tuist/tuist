import Config

config :processor, ProcessorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base:
    "test-only-secret-key-base-that-is-at-least-64-bytes-long-for-testing-use-only-ok",
  server: false

config :processor,
  webhook_secret: "test-webhook-secret"

config :logger, level: :warning

config :sentry, dsn: nil
