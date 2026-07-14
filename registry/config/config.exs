import Config

config :ex_aws, http_client: TuistCommon.AWS.Client

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id
  ]

config :mime, :types, %{
  "application/vnd.swift.registry.v1+json" => ["swift-v1-json"],
  "application/vnd.swift.registry.v1+zip" => ["swift-v1-zip"],
  "application/vnd.swift.registry.v1+swift" => ["swift-v1-api"]
}

config :opentelemetry, traces_exporter: :none

config :phoenix, :json_library, JSON

config :sentry,
  client: TuistCommon.SentryHTTPClient,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  before_send: {TuistCommon.SentryEventFilter, :before_send}

config :tuist_common, finch_name: TuistRegistry.Finch

config :tuist_registry, TuistRegistry.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled

config :tuist_registry, TuistRegistryWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: TuistRegistryWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TuistRegistry.PubSub,
  live_view: [signing_salt: "unique_salt_here"]

config :tuist_registry,
  env: config_env(),
  namespace: TuistRegistry

import_config "#{config_env()}.exs"
