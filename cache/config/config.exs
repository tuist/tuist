import Config

config :appsignal, :config,
  otp_app: :cache,
  name: "Cache",
  active: true

config :cache, CacheWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CacheWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Cache.PubSub,
  live_view: [signing_salt: "unique_salt_here"]

config :cache, Oban,
  repo: Cache.Repo,
  engine: Oban.Engines.Lite,
  queues: [s3_uploads: 10],
  plugins: [
    Oban.Plugins.Pruner
  ]

config :cache, ecto_repos: [Cache.Repo]

config :cache,
  namespace: Cache

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
