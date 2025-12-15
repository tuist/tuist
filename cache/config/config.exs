import Config

# Bandit.TransportError is raised when the client disconnects mid-request (e.g. cancelled upload).
# These are expected and not actionable errors.
config :appsignal, :config,
  otp_app: :cache,
  name: "Cache",
  active: true,
  ignore_errors: ["Bandit.TransportError"]

config :cache, Cache.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled

config :cache, Cache.Repo, busy_timeout: 10_000

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
  notifier: Oban.Notifiers.PG,
  queues: [
    maintenance: 1,
    s3_transfers: 1
  ],
  plugins: [
    {Oban.Plugins.Pruner, interval: to_timeout(minute: 5), max_age: to_timeout(day: 1)},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/10 * * * *", Cache.DiskEvictionWorker},
       {"* * * * *", Cache.S3TransferWorker}
     ]}
  ]

config :cache, :cas,
  storage_dir: "tmp/cas",
  disk_usage_high_watermark_percent: 85.0,
  disk_usage_target_percent: 70.0,
  events_batch_size: 100,
  events_batch_timeout: 5_000

config :cache, ecto_repos: [Cache.Repo]

config :cache,
  namespace: Cache

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
