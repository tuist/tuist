import Config

noora_static_path = Path.expand("../../noora/priv/static", __DIR__)

config :esbuild,
  version: "0.25.2",
  slack: [
    args: [
      "js/app.js",
      "--bundle",
      "--target=es2017",
      "--outdir=../priv/static/assets",
      "--alias:noora=#{noora_static_path}/noora.js",
      "--alias:noora/noora.css=#{noora_static_path}/noora.css"
    ],
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :slack, Slack.Mailer, adapter: Swoosh.Adapters.Local

config :slack, Slack.Repo,
  journal_mode: :wal,
  synchronous: :normal,
  temp_store: :memory,
  cache_size: -64_000,
  busy_timeout: 30_000,
  queue_target: 1_000,
  queue_interval: 1_000

config :slack, SlackWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SlackWeb.ErrorHTML, json: SlackWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Slack.PubSub,
  live_view: [signing_salt: "4Nq1xSlack"]

config :slack, :mailer_from, {"Tuist", "hello@tuist.dev"}

config :slack,
  ecto_repos: [Slack.Repo],
  generators: [timestamp_type: :utc_datetime]

config :swoosh, :api_client, false

import_config "#{config_env()}.exs"
