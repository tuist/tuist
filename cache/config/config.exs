import Config

config :appsignal, :config,
  otp_app: :cache,
  name: "Cache",
  active: true

config :cache, Cache.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled

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
  queues: [
    s3_uploads: 10,
    s3_downloads: 10,
    maintenance: 1
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"*/10 * * * *", Cache.DiskEvictionWorker}
     ]}
  ]

config :cache, :cas,
  storage_dir: "tmp/cas",
  disk_usage_high_watermark_percent: 85.0,
  disk_usage_target_percent: 70.0

config :cache, ecto_repos: [Cache.Repo]

config :cache,
  namespace: Cache

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
