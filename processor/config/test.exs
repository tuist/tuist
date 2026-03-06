import Config

config :processor, ProcessorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "test-only-secret-key-base-that-is-at-least-64-bytes-long-for-testing-use-only-ok",
  server: false

config :logger, level: :warning
