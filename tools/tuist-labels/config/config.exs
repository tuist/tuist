import Config

config :tuist_labels, TuistLabelsWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  pubsub_server: TuistLabels.PubSub,
  live_view: [signing_salt: "labels-live"],
  render_errors: [
    formats: [html: TuistLabelsWeb.Errors, json: TuistLabelsWeb.Errors],
    layout: false
  ],
  secret_key_base: :crypto.strong_rand_bytes(64) |> Base.encode64(),
  server: config_env() != :test,
  http: [ip: {127, 0, 0, 1}, port: 3077]

config :phoenix, :json_library, Jason
config :phoenix, :filter_parameters, ["token", "controlToken", "relayToken"]
config :logger, level: :warning
