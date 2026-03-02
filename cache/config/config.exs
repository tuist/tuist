import Config

config :cache, Cache.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled

config :cache, Cache.Repo,
  busy_timeout: 30_000,
  journal_mode: :wal,
  synchronous: :normal,
  temp_store: :memory,
  cache_size: -64_000,
  auto_vacuum: :incremental,
  journal_size_limit: 67_108_864,
  queue_target: 1_000,
  queue_interval: 1_000,
  custom_pragmas: [mmap_size: 268_435_456]

config :cache, Cache.SQLiteBuffer,
  flush_interval_ms: 500,
  flush_timeout_ms: 30_000,
  max_batch_size: 1000,
  shutdown_ms: 30_000

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
    clean: 10,
    maintenance: 1,
    s3_transfers: 1,
    registry_sync: 1,
    registry_release: 5
  ],
  plugins: [
    {Oban.Plugins.Pruner, interval: to_timeout(minute: 5), max_age: to_timeout(day: 1)},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/10 * * * *", Cache.DiskEvictionWorker},
       {"0 * * * *", Cache.OrphanCleanupWorker},
       {"0 */6 * * *", Cache.KeyValueEvictionWorker},
       {"* * * * *", Cache.S3TransferWorker},
       {"*/10 * * * *", Cache.Registry.SyncWorker},
       {"*/15 * * * *", Cache.SQLiteMaintenanceWorker}
     ]}
  ]

config :cache, ecto_repos: [Cache.Repo]

config :cache,
  env: config_env(),
  namespace: Cache

config :cache,
  storage_dir: "tmp/cas",
  disk_usage_high_watermark_percent: 85.0,
  disk_usage_target_percent: 70.0,
  events_batch_size: 100,
  events_batch_timeout: 5_000,
  key_value_eviction_max_age_days: 30,
  registry_sync_limit: 1_000

config :ex_aws, http_client: TuistCommon.AWS.Client

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :auth_account_handle,
    :selected_account_handle,
    :selected_project_handle
  ]

config :mime, :types, %{
  "application/vnd.swift.registry.v1+json" => ["swift-registry-v1-json"],
  "application/vnd.swift.registry.v1+zip" => ["swift-registry-v1-zip"],
  "application/vnd.swift.registry.v1+swift" => ["swift-registry-v1-api"]
}

config :opentelemetry, traces_exporter: :none

config :phoenix, :json_library, Jason

config :sentry,
  client: TuistCommon.SentryHTTPClient,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  before_send: {TuistCommon.SentryEventFilter, :before_send}

config :tuist_common, finch_name: Cache.Finch

import_config "#{config_env()}.exs"
