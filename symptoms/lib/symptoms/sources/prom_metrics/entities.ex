defmodule Symptoms.Sources.PromMetrics.Entities do
  @moduledoc """
  The default production entity list for `Symptoms.Sources.PromMetrics`,
  copied from the replay manifest (`.amp/in/replay-data/manifest.json`,
  generated 2026-11-16 against the `grafanacloud-tuist-prom` Mimir data
  source). Override it with `config :symptoms, Symptoms.Sources.PromMetrics,
  entities: [...]` or the `:entities` option.

  - `role: :numerator` pairs with the `:denominator` entity whose key has the
    same prefix (`x.5xx` with `x.requests`); the pair gives an error share.
    A numerator without a denominator is evaluated on its own value.
  - `role: :backlog` adds growth and time to drain; `:backlog_age` is the
    oldest job's age; `:resource` is a saturation or latency level.
  - `split` selects one series (`{label, value}`) of a query that returns
    several; `nil` means the query returns one series.
  - Increases are per 5 minutes even though the source evaluates them every
    minute (README "Inputs": PromQL at 1 min).
  """

  @entities [
    %{
      key: "ingress.tuist-dev.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"host", "tuist.dev"},
      units: "requests per 5 min (increase, rounded counts are not exact integers)",
      promql:
        ~s'sum by (host) (increase(nginx_ingress_controller_requests{env="production",host=~"tuist.dev|registry.tuist.dev"}[5m]))'
    },
    %{
      key: "ingress.tuist-dev.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"host", "tuist.dev"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (host) (increase(nginx_ingress_controller_requests{env="production",host=~"tuist.dev|registry.tuist.dev",status=~"5.."}[5m])) or (0 * sum by (host) (increase(nginx_ingress_controller_requests{env="production",host=~"tuist.dev|registry.tuist.dev"}[5m])))'
    },
    %{
      key: "ingress.registry-tuist-dev.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"host", "registry.tuist.dev"},
      units: "requests per 5 min (increase, rounded counts are not exact integers)",
      promql:
        ~s'sum by (host) (increase(nginx_ingress_controller_requests{env="production",host=~"tuist.dev|registry.tuist.dev"}[5m]))'
    },
    %{
      key: "ingress.registry-tuist-dev.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"host", "registry.tuist.dev"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (host) (increase(nginx_ingress_controller_requests{env="production",host=~"tuist.dev|registry.tuist.dev",status=~"5.."}[5m])) or (0 * sum by (host) (increase(nginx_ingress_controller_requests{env="production",host=~"tuist.dev|registry.tuist.dev"}[5m])))'
    },
    %{
      key: "ingress.kura-cache.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: nil,
      units: "requests per 5 min, all *.cache.tuist.dev and *.kura.tuist.dev hosts",
      promql: ~s|sum(increase(nginx_ingress_controller_requests{env="production",exported_namespace="kura"}[5m]))|
    },
    %{
      key: "ingress.kura-cache.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: nil,
      units: "5xx responses per 5 min",
      promql:
        ~s|sum(increase(nginx_ingress_controller_requests{env="production",exported_namespace="kura",status=~"5.."}[5m])) or (0 * sum(increase(nginx_ingress_controller_requests{env="production",exported_namespace="kura"}[5m])))|
    },
    %{
      key: "cache-nginx.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: nil,
      units: "responses per 5 min, legacy cache-* nginx fleet",
      promql: "sum(increase(cache_nginx_http_responses_total{instance!~\".*-(canary|staging)\"}[5m]))"
    },
    %{
      key: "cache-nginx.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: nil,
      units: "5xx responses per 5 min",
      promql:
        ~s'sum(increase(cache_nginx_http_responses_total{instance!~".*-(canary|staging)",status_class="5"}[5m])) or (0 * sum(increase(cache_nginx_http_responses_total{instance!~".*-(canary|staging)"}[5m])))'
    },
    %{
      key: "server-phoenix.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: nil,
      units: "requests per 5 min",
      promql: "sum(increase(tuist_prom_ex_phoenix_http_requests_total{env=\"production\"}[5m]))"
    },
    %{
      key: "server-phoenix.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: nil,
      units: "5xx responses per 5 min",
      promql:
        ~s|sum(increase(tuist_prom_ex_phoenix_http_requests_total{env="production",status=~"5.."}[5m])) or (0 * sum(increase(tuist_prom_ex_phoenix_http_requests_total{env="production"}[5m])))|
    },
    %{
      key: "oban.default.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "default"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.default.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "default"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.process_build.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "process_build"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.process_build.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "process_build"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.process_xcresult.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "process_xcresult"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.process_xcresult.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "process_xcresult"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.vcs_comments.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "vcs_comments"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.vcs_comments.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "vcs_comments"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.webhooks.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "webhooks"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.webhooks.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "webhooks"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.storage_retention.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "storage_retention"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.storage_retention.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "storage_retention"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.alert_evaluations.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "alert_evaluations"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.alert_evaluations.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "alert_evaluations"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.swift_registry_sync.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "swift_registry_sync"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.swift_registry_sync.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "swift_registry_sync"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.swift_registry_release.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "swift_registry_release"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.swift_registry_release.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "swift_registry_release"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.process_bazel_tests.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "process_bazel_tests"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.process_bazel_tests.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "process_bazel_tests"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.runner_gitlab.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "runner_gitlab"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.runner_gitlab.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "runner_gitlab"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.kura_provisioning.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "kura_provisioning"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.kura_provisioning.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "kura_provisioning"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.mcp_events.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "mcp_events"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.mcp_events.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "mcp_events"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.coverage_deltas.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "coverage_deltas"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.coverage_deltas.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "coverage_deltas"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.alert_evaluation_batches.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "alert_evaluation_batches"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.alert_evaluation_batches.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "alert_evaluation_batches"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.automation_notifications.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "automation_notifications"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.automation_notifications.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "automation_notifications"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.remote_execution_maintenance.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "remote_execution_maintenance"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.remote_execution_maintenance.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "remote_execution_maintenance"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.push.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "push"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.push.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "push"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.threads.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "threads"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.threads.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "threads"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.sandbox_archives.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "sandbox_archives"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.sandbox_archives.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "sandbox_archives"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.jams.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "jams"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.jams.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "jams"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.sandbox_snapshot_copies.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "sandbox_snapshot_copies"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.sandbox_snapshot_copies.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "sandbox_snapshot_copies"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "oban.thread_exit_watches.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "thread_exit_watches"},
      units: "jobs (available state)",
      promql: ~s|max by (queue) (tuist_oban_queue_length_count{env="production",state="available"})|
    },
    %{
      key: "oban.thread_exit_watches.oldest_available_age",
      phenomenon: :latency,
      role: :backlog_age,
      split: {"queue", "thread_exit_watches"},
      units: "seconds",
      promql: "max by (queue) (tuist_oban_queue_oldest_available_age_seconds{env=\"production\"})"
    },
    %{
      key: "kura.eu-central.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"region", "eu-central"},
      units: "public requests per 5 min (internal, health and metrics routes excluded)",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"})))'
    },
    %{
      key: "kura.eu-central.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"region", "eu-central"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",status=~"5..",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) or (sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) * 0)'
    },
    %{
      key: "kura.us-east.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"region", "us-east"},
      units: "public requests per 5 min (internal, health and metrics routes excluded)",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"})))'
    },
    %{
      key: "kura.us-east.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"region", "us-east"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",status=~"5..",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) or (sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) * 0)'
    },
    %{
      key: "kura.us-west.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"region", "us-west"},
      units: "public requests per 5 min (internal, health and metrics routes excluded)",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"})))'
    },
    %{
      key: "kura.us-west.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"region", "us-west"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",status=~"5..",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) or (sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) * 0)'
    },
    %{
      key: "kura.scw-fr-par-runners.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"region", "scw-fr-par-runners"},
      units: "public requests per 5 min (internal, health and metrics routes excluded)",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"})))'
    },
    %{
      key: "kura.scw-fr-par-runners.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"region", "scw-fr-par-runners"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",status=~"5..",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) or (sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) * 0)'
    },
    %{
      key: "kura.ap-southeast.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"region", "ap-southeast"},
      units: "public requests per 5 min (internal, health and metrics routes excluded)",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"})))'
    },
    %{
      key: "kura.ap-southeast.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"region", "ap-southeast"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",status=~"5..",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) or (sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) * 0)'
    },
    %{
      key: "kura.eu-east.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"region", "eu-east"},
      units: "public requests per 5 min (internal, health and metrics routes excluded)",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"})))'
    },
    %{
      key: "kura.eu-east.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"region", "eu-east"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",status=~"5..",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) or (sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) * 0)'
    },
    %{
      key: "kura.eu-west.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"region", "eu-west"},
      units: "public requests per 5 min (internal, health and metrics routes excluded)",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"})))'
    },
    %{
      key: "kura.eu-west.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"region", "eu-west"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",status=~"5..",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) or (sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) * 0)'
    },
    %{
      key: "kura.us-central.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"region", "us-central"},
      units: "public requests per 5 min (internal, health and metrics routes excluded)",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"})))'
    },
    %{
      key: "kura.us-central.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"region", "us-central"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",status=~"5..",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) or (sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) * 0)'
    },
    %{
      key: "kura.sa-west.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"region", "sa-west"},
      units: "public requests per 5 min (internal, health and metrics routes excluded)",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"})))'
    },
    %{
      key: "kura.sa-west.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"region", "sa-west"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",status=~"5..",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) or (sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) * 0)'
    },
    %{
      key: "kura.ber1-runners.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"region", "ber1-runners"},
      units: "public requests per 5 min (internal, health and metrics routes excluded)",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"})))'
    },
    %{
      key: "kura.ber1-runners.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"region", "ber1-runners"},
      units: "5xx responses per 5 min",
      promql:
        ~s'sum by (region) (increase(kura_http_requests_total_total{env="production",status=~"5..",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) or (sum by (region) (increase(kura_http_requests_total_total{env="production",route!~"/_internal/.*|/up|/ready|/metrics|/status/.*"}[5m]) * on (namespace, pod) group_left(region) topk by (namespace, pod) (1, max by (namespace, pod, region) (kura_node_info{env="production"}))) * 0)'
    },
    %{
      key: "runners.all.queue_depth",
      phenomenon: :saturation,
      role: :backlog,
      split: nil,
      units: "queued jobs",
      promql: "sum(max by (fleet) (tuist_runners_queue_length{env=\"production\"}))"
    },
    %{
      key: "runners.linux.queue_depth",
      phenomenon: :saturation,
      role: :backlog,
      split: nil,
      units: "queued jobs",
      promql:
        ~s|sum(max by (fleet) (tuist_runners_queue_length{env="production",fleet=~"tuist-tuist-runner-pool-linux-.*"}))|
    },
    %{
      key: "runners.macos.queue_depth",
      phenomenon: :saturation,
      role: :backlog,
      split: nil,
      units: "queued jobs",
      promql:
        ~s|sum(max by (fleet) (tuist_runners_queue_length{env="production",fleet=~"tuist-tuist-runner-pool-macos-.*"}))|
    },
    %{
      key: "runners.linux-2vcpu-8gb.queue_depth",
      phenomenon: :saturation,
      role: :backlog,
      split: {"fleet", "tuist-tuist-runner-pool-linux-2vcpu-8gb"},
      units: "queued jobs",
      promql:
        ~s[max by (fleet) (tuist_runners_queue_length{env="production",fleet=~"tuist-tuist-runner-pool-(linux-2vcpu-8gb|linux-4vcpu-16gb|linux-16vcpu-32gb)"})]
    },
    %{
      key: "runners.linux-4vcpu-16gb.queue_depth",
      phenomenon: :saturation,
      role: :backlog,
      split: {"fleet", "tuist-tuist-runner-pool-linux-4vcpu-16gb"},
      units: "queued jobs",
      promql:
        ~s[max by (fleet) (tuist_runners_queue_length{env="production",fleet=~"tuist-tuist-runner-pool-(linux-2vcpu-8gb|linux-4vcpu-16gb|linux-16vcpu-32gb)"})]
    },
    %{
      key: "runners.linux-16vcpu-32gb.queue_depth",
      phenomenon: :saturation,
      role: :backlog,
      split: {"fleet", "tuist-tuist-runner-pool-linux-16vcpu-32gb"},
      units: "queued jobs",
      promql:
        ~s[max by (fleet) (tuist_runners_queue_length{env="production",fleet=~"tuist-tuist-runner-pool-(linux-2vcpu-8gb|linux-4vcpu-16gb|linux-16vcpu-32gb)"})]
    },
    %{
      key: "postgres.backends_waiting",
      phenomenon: :saturation,
      role: :resource,
      split: nil,
      units: "backends waiting on locks",
      promql: ~s|max(cnpg_backends_waiting_total{env="production",instance_role="primary"})|
    },
    %{
      key: "postgres.connection_utilisation",
      phenomenon: :saturation,
      role: :resource,
      split: nil,
      units: "ratio of max_connections",
      promql:
        ~s|sum(cnpg_backends_total{env="production",instance_role="primary"}) / max(cnpg_pg_settings_setting{env="production",name="max_connections",instance_role="primary"})|
    },
    %{
      key: "postgres.replication_lag",
      phenomenon: :latency,
      role: :resource,
      split: nil,
      units: "seconds",
      promql: "max(cnpg_pg_replication_lag{env=\"production\"})"
    },
    %{
      key: "postgres.pgbouncer_clients_waiting",
      phenomenon: :saturation,
      role: :resource,
      split: nil,
      units: "clients",
      promql: ~s|sum(cnpg_pgbouncer_pools_cl_waiting{env="production",database="tuist"})|
    },
    %{
      key: "postgres.pgbouncer_maxwait",
      phenomenon: :latency,
      role: :resource,
      split: nil,
      units: "seconds",
      promql:
        ~s|max(cnpg_pgbouncer_pools_maxwait{env="production",database="tuist"} + cnpg_pgbouncer_pools_maxwait_us{env="production",database="tuist"} / 1e6)|
    },
    %{
      key: "clickhouse.query_p95",
      phenomenon: :latency,
      role: :resource,
      split: nil,
      units: "milliseconds (client side, Tuist server reads)",
      promql:
        "histogram_quantile(0.95, sum by (le) (rate(tuist_clickhouse_query_duration_milliseconds_bucket{env=\"production\"}[5m])))"
    },
    %{
      key: "clickhouse.concurrent_queries",
      phenomenon: :saturation,
      role: :resource,
      split: nil,
      units: "queries",
      promql: "max(ClickHouseMetrics_Query{env=\"production\"})"
    },
    %{
      key: "clickhouse.failed_queries",
      phenomenon: :request_errors,
      role: :numerator,
      split: nil,
      units: "failed queries per 5 min",
      promql: "sum(increase(ClickHouseProfileEvents_FailedQuery{env=\"production\"}[5m]))"
    }
  ]

  @doc "The default entity list."
  @spec all() :: [map()]
  def all, do: @entities
end
