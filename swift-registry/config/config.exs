import Config

config :ex_aws, http_client: TuistCommon.AWS.Client

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id
  ]

config :mime, :types, %{
  "application/vnd.swift.registry.v1+json" => ["swift-registry-v1-json"],
  "application/vnd.swift.registry.v1+zip" => ["swift-registry-v1-zip"],
  "application/vnd.swift.registry.v1+swift" => ["swift-registry-v1-api"]
}

config :opentelemetry, traces_exporter: :none

config :phoenix, :json_library, JSON

config :sentry,
  client: TuistCommon.SentryHTTPClient,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  before_send: {TuistCommon.SentryEventFilter, :before_send}

config :swift_registry, Oban,
  repo: SwiftRegistry.Repo,
  engine: Oban.Engines.Lite,
  notifier: Oban.Notifiers.PG,
  queues: [
    maintenance: 1,
    s3_transfers: 1,
    registry_sync: 1,
    registry_release: 5
  ],
  plugins: [
    {Oban.Plugins.Pruner, interval: to_timeout(minute: 5), max_age: to_timeout(day: 1)},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/10 * * * *", SwiftRegistry.DiskEvictionWorker},
       {"0 * * * *", SwiftRegistry.OrphanCleanupWorker},
       {"* * * * *", SwiftRegistry.S3TransferWorker},
       {"*/10 * * * *", SwiftRegistry.Registry.SyncWorker},
       {"*/15 * * * *", SwiftRegistry.SQLiteMaintenanceWorker}
     ]}
  ]

config :swift_registry, SwiftRegistry.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled

config :swift_registry, SwiftRegistry.Repo,
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

config :swift_registry, SwiftRegistry.SQLiteBuffer,
  flush_interval_ms: 500,
  flush_timeout_ms: 30_000,
  max_batch_size: 1_000,
  shutdown_ms: 30_000

config :swift_registry, SwiftRegistryWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SwiftRegistryWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SwiftRegistry.PubSub,
  live_view: [signing_salt: "unique_salt_here"]

config :swift_registry, ecto_repos: [SwiftRegistry.Repo]

config :swift_registry,
  env: config_env(),
  namespace: SwiftRegistry

config :swift_registry,
  storage_dir: "tmp/cas",
  disk_usage_high_watermark_percent: 75.0,
  disk_usage_target_percent: 60.0,
  events_batch_size: 100,
  events_batch_timeout: 5_000,
  analytics_failure_threshold: 3,
  analytics_cooldown_ms: 60_000,
  analytics_receive_timeout_ms: 2_000,
  analytics_pool_timeout_ms: 1_000,
  registry_sync_enabled: true,
  registry_sync_limit: 1_000

config :tuist_common, finch_name: SwiftRegistry.Finch

import_config "#{config_env()}.exs"
