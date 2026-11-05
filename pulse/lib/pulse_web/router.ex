defmodule PulseWeb.Router do
  use PulseWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PulseWeb do
    get "/metrics", MetricsController, :index
    get "/healthz", HealthController, :live
    get "/readyz", HealthController, :ready
    get "/.well-known/oauth-protected-resource", OAuthMetadataController, :show
    get "/.well-known/oauth-protected-resource/*resource", OAuthMetadataController, :show
  end

  # MCP clients advertise both application/json and text/event-stream, and
  # the transport defines its own status codes, so `/mcp` skips `:accepts`.
  # Origin and media-type checks run in `PulseWeb.MCPRequestGate`.
  scope "/", PulseWeb do
    # OTLP responses mirror JSON/protobuf rather than applying JSON Accept negotiation.
    get "/api/search/tags", TempoController, :tags
    get "/api/v2/search/tags", TempoController, :tags_v2
    get "/api/search/tag/*tag_path", TempoController, :tag_values
    get "/api/v2/search/tag/*tag_path", TempoController, :tag_values_v2
    get "/api/search", TempoController, :search
    get "/api/metrics/query_range", TempoController, :metrics_query_range
    get "/api/metrics/query", TempoController, :metrics_query
    get "/api/traces/:trace_id", TempoController, :trace
    get "/api/v2/traces/:trace_id", TempoController, :trace_v2
    post "/v1/traces", OTLPTracesController, :create
    post "/v1/metrics", OTLPMetricsController, :create
    post "/v1/logs", OTLPController, :logs
    get "/api/echo", CompatController, :tempo_echo
    get "/api/status/buildinfo", CompatController, :tempo_buildinfo
    get "/api/v1/status/buildinfo", CompatController, :prometheus_buildinfo
    get "/api/v1/metadata", CompatController, :metadata
    get "/api/v1/query_exemplars", CompatController, :query_exemplars
    post "/api/v1/query_exemplars", CompatController, :query_exemplars
    get "/api/v1/format_query", CompatController, :format_query
    post "/api/v1/format_query", CompatController, :format_query
    get "/loki/api/v1/status/buildinfo", LokiQueryController, :buildinfo
    get "/loki/api/v1/tail", LokiQueryController, :tail
    post "/mcp", MCPController, :rpc
    match :*, "/mcp", MCPController, :method_not_allowed
  end

  # SDKs may omit Accept/Content-Type or use text/plain to avoid preflight.
  scope "/api", PulseWeb do
    get "/store", SentryController, :store
    post "/store", SentryController, :store
    post "/:project_id/envelope", SentryController, :envelope
    get "/:project_id/store", SentryController, :store
    post "/:project_id/store", SentryController, :store
  end

  scope "/", PulseWeb do
    pipe_through :api

    post "/api/v1/reliability/investigations/:id/complete", ReliabilityController, :complete

    get "/api/v1/admin/tenants", AdminController, :index
    get "/api/v1/admin/tenants/:tenant", AdminController, :show
    put "/api/v1/admin/tenants/:tenant", AdminController, :update
    delete "/api/v1/admin/tenants/:tenant", AdminController, :delete
    get "/api/v1/admin/tenants/:tenant/usage", AdminController, :usage

    post "/api/v1/alerting/import/preview", AlertingController, :import_preview
    post "/api/v1/alerting/import/rule-file/preview", AlertingController, :import_rule_file_preview
    get "/api/v1/alerting/rules", AlertingController, :index
    get "/api/v1/alerting/rules/:id", AlertingController, :show
    post "/api/v1/alerting/rules/:id", AlertingController, :create
    put "/api/v1/alerting/rules/:id", AlertingController, :update
    delete "/api/v1/alerting/rules/:id", AlertingController, :delete
    get "/api/v1/alerting/rules/:id/changes", AlertingController, :changes
    post "/api/v1/alerting/rules/:id/changes", AlertingController, :changes
    get "/api/v1/alerting/rules/:id/revisions/:revision", AlertingController, :revision
    post "/api/v1/alerting/rules/:id/revisions/:revision", AlertingController, :revision
    post "/api/v1/alerting/rules/:id/restore", AlertingController, :restore
    get "/api/v1/alerting/rules/:id/state", AlertingController, :state
    post "/api/v1/alerting/rules/:id/events", AlertingController, :events
    post "/api/v1/alerting/rules/:id/preview", AlertingController, :preview
    post "/api/v1/alerting/rules/:id/evaluate", AlertingController, :evaluate

    post "/loki/api/v1/push", LokiController, :push
    post "/api/v1/write", RemoteWriteController, :write
    get "/api/v1/labels", PrometheusDiscoveryController, :labels
    post "/api/v1/labels", PrometheusDiscoveryController, :labels
    get "/api/v1/label/:name/values", PrometheusDiscoveryController, :label_values
    post "/api/v1/label/:name/values", PrometheusDiscoveryController, :label_values
    get "/api/v1/series", PrometheusDiscoveryController, :series
    post "/api/v1/series", PrometheusDiscoveryController, :series
    get "/api/v1/query", PrometheusQueryController, :query
    post "/api/v1/query", PrometheusQueryController, :query
    get "/api/v1/query_range", PrometheusQueryController, :query_range
    post "/api/v1/query_range", PrometheusQueryController, :query_range

    get "/loki/api/v1/query_range", LokiQueryController, :query_range
    post "/loki/api/v1/query_range", LokiQueryController, :query_range
    get "/loki/api/v1/query", LokiQueryController, :query
    post "/loki/api/v1/query", LokiQueryController, :query
    get "/loki/api/v1/labels", LokiQueryController, :labels
    post "/loki/api/v1/labels", LokiQueryController, :labels
    get "/loki/api/v1/label/:name/values", LokiQueryController, :label_values
    post "/loki/api/v1/label/:name/values", LokiQueryController, :label_values
    get "/loki/api/v1/series", LokiQueryController, :series
    post "/loki/api/v1/series", LokiQueryController, :series
    get "/loki/api/v1/index/stats", LokiQueryController, :index_stats
    post "/loki/api/v1/index/stats", LokiQueryController, :index_stats
    get "/loki/api/v1/index/volume", LokiQueryController, :volume
    post "/loki/api/v1/index/volume", LokiQueryController, :volume
    get "/loki/api/v1/index/volume_range", LokiQueryController, :volume_range
    post "/loki/api/v1/index/volume_range", LokiQueryController, :volume_range
    get "/loki/api/v1/detected_labels", LokiQueryController, :detected_labels
    post "/loki/api/v1/detected_labels", LokiQueryController, :detected_labels
    get "/loki/api/v1/detected_fields", LokiQueryController, :detected_fields
    post "/loki/api/v1/detected_fields", LokiQueryController, :detected_fields
    get "/loki/api/v1/detected_field/:name/values", LokiQueryController, :detected_field_values
    post "/loki/api/v1/detected_field/:name/values", LokiQueryController, :detected_field_values
    get "/loki/api/v1/patterns", LokiQueryController, :patterns
    post "/loki/api/v1/patterns", LokiQueryController, :patterns
  end
end
