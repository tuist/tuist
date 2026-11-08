import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/pulse start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
alias Pulse.Alerting.GraphPreview
alias Pulse.Alerting.Principal
alias Pulse.Alerting.Targets
alias Pulse.Auth.Issuer
alias Pulse.Auth.SharedSecret
alias Pulse.Auth.WorkloadIdentity
alias Pulse.Errors.Projection
alias Pulse.Loki.Tail
alias Pulse.PromQL.Evaluator
alias Pulse.Storage.S3

# Environment variables are read through Pulse.Runtime so tests can evaluate this
# file against a process-owned environment map instead of mutating the OS
# environment. Without an installed runtime (every normal boot and release), this
# is System.get_env/2.
alias Pulse.Storage.S3.ManifestCache
alias Pulse.Storage.S3.ObjectCache
alias Pulse.Traces.TempoSearch

env_var = fn name, default ->
  if Code.ensure_loaded?(Pulse.Runtime), do: Pulse.Runtime.env(name, default), else: System.get_env(name, default)
end

# Sentry DSNs are ingest-only and never grant tenant query access.
sentry_projects =
  case JSON.decode(env_var.("PULSE_SENTRY_PROJECTS_JSON", "{}")) do
    {:ok, projects} -> Pulse.Sentry.validate_projects!(projects)
    _ -> raise "PULSE_SENTRY_PROJECTS_JSON must be a JSON object"
  end

# Alerting uses separate principal credentials; tenant-shared tokens never grant writes.
alerting_principals = Principal.parse_configured!(env_var.("PULSE_ALERTING_PRINCIPALS_JSON", "[]"))

error_history_days =
  case Integer.parse(env_var.("PULSE_ERROR_HISTORY_DAYS", "1")) do
    {value, ""} when value in 1..365 -> value
    _ -> raise "PULSE_ERROR_HISTORY_DAYS must be an integer in 1..365"
  end

error_projection_interval =
  case Integer.parse(env_var.("PULSE_ERROR_PROJECTION_INTERVAL_MS", "5000")) do
    {value, ""} when value in 1000..60_000 -> value
    _ -> raise "PULSE_ERROR_PROJECTION_INTERVAL_MS must be an integer in 1000..60000"
  end

reliability_enabled = env_var.("PULSE_RELIABILITY_ENABLED", "false") in ["1", "true", "yes"]

reliability_tenants =
  case JSON.decode(env_var.("PULSE_RELIABILITY_TENANTS_JSON", "[]")) do
    {:ok, tenants} when is_list(tenants) and length(tenants) <= 64 ->
      if Enum.all?(
           tenants,
           &(is_binary(&1) and &1 not in [".", ".."] and Regex.match?(~r/\A[A-Za-z0-9_.\-]{1,128}\z/, &1))
         ) and
           length(Enum.uniq(tenants)) == length(tenants),
         do: tenants,
         else: raise("PULSE_RELIABILITY_TENANTS_JSON contains invalid/duplicate tenants")

    _ ->
      raise "PULSE_RELIABILITY_TENANTS_JSON must be an array of at most 64 tenant identifiers"
  end

reliability_integer = fn name, default, maximum ->
  case Integer.parse(env_var.(name, Integer.to_string(default))) do
    {value, ""} when value >= 0 and value <= maximum -> value
    _ -> raise "#{name} must be an integer in 0..#{maximum}"
  end
end

reliability_price_until = env_var.("PULSE_RELIABILITY_PRICE_VALID_UNTIL", "")
reliability_key = env_var.("PULSE_RELIABILITY_OPENAI_API_KEY", "")
investigation_url = env_var.("PULSE_RELIABILITY_INVESTIGATION_URL", "")
investigation_token = env_var.("PULSE_RELIABILITY_INVESTIGATION_TOKEN", "")
reliability_input_price = reliability_integer.("PULSE_RELIABILITY_INPUT_NANO_USD_PER_TOKEN", 110, 1_000_000)

if reliability_input_price == 0,
  do: raise("PULSE_RELIABILITY_INPUT_NANO_USD_PER_TOKEN must be positive")

config :pulse, Projection,
  enabled: env_var.("PULSE_ERROR_PROJECTION_ENABLED", "false") in ["1", "true", "yes"],
  history_days: error_history_days,
  interval_ms: error_projection_interval

if reliability_enabled and
     (reliability_tenants == [] or reliability_key == "" or
        not match?({:ok, _}, Date.from_iso8601(reliability_price_until))),
   do: raise("Reliability requires tenants, an OpenAI API key and an ISO price-valid-until date")

if investigation_url != "" do
  uri = URI.parse(investigation_url)

  if uri.scheme != "https" or uri.host in [nil, ""] or uri.userinfo != nil or uri.fragment != nil or
       investigation_token == "" or String.contains?(investigation_token, ["\r", "\n"]),
     do: raise("Reliability investigation handoff requires a fixed HTTPS URL and bearer token")
end

# Workload identity: trusted Kubernetes ServiceAccount token issuers, each pinned
# to its signing keys and explicit subject => tenant/capability bindings.
workload_trust =
  case JSON.decode(env_var.("PULSE_WORKLOAD_IDENTITY_JSON", "[]")) do
    {:ok, entries} -> WorkloadIdentity.parse!(entries)
    _ -> raise "PULSE_WORKLOAD_IDENTITY_JSON is not valid JSON"
  end

# Trusted credential issuer (Tuist in the hosted product): offline-verified
# tokens whose claims carry tenant and scopes. See docs/issuer-credentials.md.
issuer_config =
  case env_var.("PULSE_ISSUER_JSON", "") do
    "" ->
      nil

    blob ->
      case JSON.decode(blob) do
        {:ok, raw} -> Issuer.parse!(raw)
        _ -> raise "PULSE_ISSUER_JSON is not valid JSON"
      end
  end

alerting_poll_interval_ms =
  case Integer.parse(env_var.("PULSE_ALERTING_POLL_INTERVAL_MS", "5000")) do
    {value, ""} when value in 1000..60_000 -> value
    _ -> raise "PULSE_ALERTING_POLL_INTERVAL_MS must be an integer in 1000..60000"
  end

alerting_targets =
  case JSON.decode(env_var.("PULSE_ALERTING_NOTIFICATION_TARGETS_JSON", "[]")) do
    {:ok, values} when is_list(values) and length(values) <= 256 ->
      Enum.map(values, fn value ->
        case Targets.validate(value) do
          {:ok, target} -> target
          _ -> raise "PULSE_ALERTING_NOTIFICATION_TARGETS_JSON contains an invalid target"
        end
      end)

    _ ->
      raise "PULSE_ALERTING_NOTIFICATION_TARGETS_JSON must be an array of at most 256 targets"
  end

identities = Enum.map(alerting_targets, &{&1["tenant"], &1["id"]})

config :pulse, Issuer, issuer_config

config :pulse, Pulse.Reliability,
  enabled: reliability_enabled,
  tenants: reliability_tenants,
  interval_ms: 1000,
  api_key: reliability_key,
  price_valid_until: reliability_price_until,
  max_input_tokens: 5000,
  input_nano_usd_per_token: reliability_input_price,
  assessment_budget_nano_usd:
    reliability_integer.("PULSE_RELIABILITY_ASSESSMENT_BUDGET_USD", 500, 100_000) * 1_000_000_000,
  object_budget_nano_usd: reliability_integer.("PULSE_RELIABILITY_OBJECT_BUDGET_USD", 100, 100_000) * 1_000_000_000,
  investigation_budget_nano_usd:
    reliability_integer.("PULSE_RELIABILITY_INVESTIGATION_BUDGET_USD", 1000, 100_000) * 1_000_000_000,
  investigation_url: if(investigation_url != "", do: investigation_url),
  investigation_token: investigation_token

config :pulse, Pulse.Sentry, projects: sentry_projects
config :pulse, WorkloadIdentity, trust: workload_trust

if length(Enum.uniq(identities)) != length(identities), do: raise("Duplicate alert notification target IDs")

alerting_source_bindings =
  case JSON.decode(env_var.("PULSE_ALERTING_SOURCE_BINDINGS_JSON", "[]")) do
    {:ok, values} ->
      case GraphPreview.bindings(values) do
        :ok ->
          values

        _ ->
          raise "PULSE_ALERTING_SOURCE_BINDINGS_JSON must contain at most 256 unique tenant/uid native_promql or native_logql bindings"
      end

    _ ->
      raise "PULSE_ALERTING_SOURCE_BINDINGS_JSON is not valid JSON"
  end

config :pulse, Pulse.Alerting,
  source_bindings: alerting_source_bindings,
  principals: alerting_principals,
  notification_targets: alerting_targets,
  notifications_enabled: env_var.("PULSE_ALERTING_NOTIFICATIONS_ENABLED", "false") in ["1", "true", "yes"],
  evaluation_enabled: env_var.("PULSE_ALERTING_EVALUATION_ENABLED", "false") in ["1", "true", "yes"],
  poll_interval_ms: alerting_poll_interval_ms

if env_var.("PHX_SERVER", nil) do
  config :pulse, PulseWeb.Endpoint, server: true
end

# Opt in only after all writers understand compaction retirement metadata.
metrics_compaction_enabled = env_var.("PULSE_METRICS_COMPACTION_ENABLED", "false") in ["1", "true", "yes"]
trace_compaction_enabled = env_var.("PULSE_TRACE_COMPACTION_ENABLED", "true") in ["1", "true", "yes"]
log_compaction_enabled = env_var.("PULSE_LOG_COMPACTION_ENABLED", "false") in ["1", "true", "yes"]
metric_footer_pruning_enabled = env_var.("PULSE_METRICS_FOOTER_PRUNING_ENABLED", "false") in ["1", "true", "yes"]
# With metrics compaction, settled hours are rewritten into metric-grouped
# segments plus hourly rollups for long range functions.
metric_finalize_enabled = env_var.("PULSE_METRICS_FINALIZE_ENABLED", "true") in ["1", "true", "yes"]
# With log compaction, settled minutes get per-stream line/byte rollups that
# answer minute-aligned count_over_time/bytes_over_time/rate/bytes_rate.
log_rollup_enabled = env_var.("PULSE_LOG_ROLLUPS_ENABLED", "true") in ["1", "true", "yes"]
# With log compaction, settled hours (and busy unfinished ones, batch by
# batch) are regrouped by stream so stream selectors read only their streams.
log_finalize_enabled = env_var.("PULSE_LOG_STREAM_GROUPING_ENABLED", "true") in ["1", "true", "yes"]
# Pulse-side manifest backups for buckets without versioning; maintenance
# cleanup waits for a backup that records each retirement.
manifest_backup_enabled = env_var.("PULSE_MANIFEST_BACKUP_ENABLED", "true") in ["1", "true", "yes"]

# paged (default): manifests without retention keep a bounded root and
# immutable pages, converting flat roots on their next publication. Releases
# before 1.27 cannot read paged roots. flat keeps writing flat roots (whose cost
# grows with history) but still reads and extends roots that are already paged.
manifest_format =
  case env_var.("PULSE_MANIFEST_FORMAT", "paged") do
    value when value in ["paged", "flat"] -> value
    _ -> raise "PULSE_MANIFEST_FORMAT must be paged or flat"
  end

# Optional node-local unkeyed coalescing; disabled unless explicitly enabled.
# A nonzero window also spaces each manifest owner's publications at least this
# far apart, so object-store PUTs scale with time, not with pushes.
ingest_flush_interval_ms =
  case Integer.parse(env_var.("PULSE_INGEST_FLUSH_INTERVAL_MS", "0")) do
    {value, ""} when value in 0..10_000 -> value
    _ -> raise "PULSE_INGEST_FLUSH_INTERVAL_MS must be an integer in 0..10000"
  end

# One node memory budget sizes ingest and query concurrency (see
# Pulse.ResourceBudget). PULSE_MEMORY_BUDGET_MB sets it explicitly; production
# releases otherwise read the container's cgroup memory limit. Without either,
# fixed defaults apply. Explicit per-setting variables below always win.
memory_budget_mb =
  case env_var.("PULSE_MEMORY_BUDGET_MB", "") do
    "" ->
      if config_env() == :prod, do: Pulse.ResourceBudget.cgroup_limit_mb()

    raw ->
      case Integer.parse(raw) do
        {value, ""} when value in 256..1_048_576 -> value
        _ -> raise "PULSE_MEMORY_BUDGET_MB must be an integer in 256..1048576"
      end
  end

envelope =
  if memory_budget_mb,
    do: Pulse.ResourceBudget.derive(memory_budget_mb),
    else: %{budget_mb: nil, ingest_slots: 32, query_slots: 3, query_heap_mb: 128}

# Node-local bound on concurrently processed ingest requests (HTTP and gRPC).
# Excess requests receive a retryable 429 / RESOURCE_EXHAUSTED.
ingest_max_concurrent =
  case Integer.parse(env_var.("PULSE_INGEST_MAX_CONCURRENT_REQUESTS", Integer.to_string(envelope.ingest_slots))) do
    {value, ""} when value in 1..100_000 -> value
    _ -> raise "PULSE_INGEST_MAX_CONCURRENT_REQUESTS must be an integer in 1..100000"
  end

# Slots each signal (metrics, logs, traces) keeps for itself; the rest are shared.
# Empty means an eighth of the slots, at least one when there are three or more.
ingest_reserved =
  case env_var.("PULSE_INGEST_RESERVED_REQUESTS_PER_SIGNAL", "") do
    "" ->
      min(max(1, div(ingest_max_concurrent, 8)), div(ingest_max_concurrent, 3))

    raw ->
      case Integer.parse(raw) do
        {value, ""} when value >= 0 and value * 3 <= ingest_max_concurrent ->
          value

        _ ->
          raise "PULSE_INGEST_RESERVED_REQUESTS_PER_SIGNAL must be an integer in 0..PULSE_INGEST_MAX_CONCURRENT_REQUESTS/3"
      end
  end

# Estimated record bytes of requests that released their slot while waiting
# for durable publication of their coalesced segment.
ingest_max_pending_bytes =
  case Integer.parse(env_var.("PULSE_INGEST_MAX_PENDING_BYTES", "67108864")) do
    {value, ""} when value in 0..17_179_869_184 -> value
    _ -> raise "PULSE_INGEST_MAX_PENDING_BYTES must be an integer in 0..17179869184"
  end

# Optional per-request ingest budgets. Only supplied environment values
# override config/config.exs; invalid values fail at startup, not on traffic.
parse_ingest_limit = fn name, raw ->
  case Integer.parse(raw) do
    {value, ""} when value in 1..2_147_483_647 -> value
    _ -> raise "#{name} must be an integer in 1..2147483647"
  end
end

ingest_limits =
  for key <- [
        :max_records,
        :max_attributes,
        :max_key_bytes,
        :max_value_bytes,
        :max_attribute_bytes,
        :max_depth,
        :max_nodes,
        :max_trace_nodes,
        :max_otlp_nodes
      ],
      name = "PULSE_INGEST_" <> String.upcase(Atom.to_string(key)),
      raw = env_var.(name, nil),
      raw != nil do
    {key, parse_ingest_limit.(name, raw)}
  end

# Event-time retention (docs/retention.md). Unlimited retention stays the
# default: all durations are 0 and the background worker is off. Invalid values
# fail at startup instead of falling back to unlimited or immediate deletion.
parse_integer = fn name, default, range ->
  case Integer.parse(env_var.(name, Integer.to_string(default))) do
    {value, ""} -> if value in range, do: value, else: raise("#{name} must be an integer in #{inspect(range)}")
    _ -> raise "#{name} must be an integer in #{inspect(range)}"
  end
end

# Tempo search reads a candidate trace's other spans from sources within this
# horizon of the candidates' segments (0: every retained source).
trace_context_horizon_ms = parse_integer.("PULSE_TRACE_SEARCH_CONTEXT_HORIZON_MS", 3_600_000, 0..604_800_000)

retention_mode =
  case env_var.("PULSE_RETENTION_MODE", "observe") do
    mode when mode in ["observe", "enforce", "paused"] -> mode
    _ -> raise "PULSE_RETENTION_MODE must be one of observe, enforce, paused"
  end

# paged (default): enforced retention keeps format-4 manifests, so manifest
# backups and hour finalization keep working. bucketed: the older format-3
# manifest. Prefixes already in format 3 stay there either way.
retention_manifest_format =
  case env_var.("PULSE_RETENTION_MANIFEST_FORMAT", "paged") do
    value when value in ["paged", "bucketed"] -> value
    _ -> raise "PULSE_RETENTION_MANIFEST_FORMAT must be paged or bucketed"
  end

retention_config =
  [
    retention_manifest_format: retention_manifest_format,
    retention_enabled: env_var.("PULSE_RETENTION_ENABLED", "false") in ["1", "true", "yes"],
    logs_retention_days: parse_integer.("PULSE_LOGS_RETENTION_DAYS", 0, 0..3650),
    metrics_retention_days: parse_integer.("PULSE_METRICS_RETENTION_DAYS", 0, 0..3650),
    traces_retention_days: parse_integer.("PULSE_TRACES_RETENTION_DAYS", 0, 0..3650),
    retention_mode: retention_mode,
    # Reader grace before deletion; never zero, so a committed expiry cannot race in-flight reads.
    retention_delete_grace_ms: parse_integer.("PULSE_RETENTION_DELETE_GRACE_MS", 3_600_000, 60_000..2_592_000_000),
    retention_interval_ms: parse_integer.("PULSE_RETENTION_INTERVAL_MS", 30_000, 1_000..3_600_000),
    retention_delete_limit: parse_integer.("PULSE_RETENTION_DELETE_LIMIT", 512, 1..512),
    retention_timeout_ms: parse_integer.("PULSE_RETENTION_TIMEOUT_MS", 30_000, 1_000..600_000),
    retention_migration_timeout_ms: parse_integer.("PULSE_RETENTION_MIGRATION_TIMEOUT_MS", 600_000, 30_000..3_600_000),
    retention_future_skew_ms: parse_integer.("PULSE_RETENTION_FUTURE_SKEW_MS", 600_000, 0..86_400_000)
  ] ++
    case env_var.("PULSE_RETENTION_SWEEP_HORIZON_DAYS", nil) do
      # Unset keeps the per-root default of 2 * persisted days + 2.
      nil -> []
      _ -> [retention_sweep_horizon_days: parse_integer.("PULSE_RETENTION_SWEEP_HORIZON_DAYS", 0, 1..7302)]
    end

# Per-query budgets shared by PromQL and LogQL. Log metric queries count each
# selected log line as a sample and stream it, so these may be raised for log
# volume; PromQL samples stay bounded by each query's memory ceiling too.
query_budgets =
  for {key, name, default, range} <- [
        {:max_samples, "PULSE_QUERY_MAX_SAMPLES", 100_000, 1..1_000_000_000},
        {:max_log_samples, "PULSE_QUERY_MAX_LOG_SAMPLES", 5_000_000, 1..1_000_000_000},
        {:max_work, "PULSE_QUERY_MAX_WORK", 5_000_000, 1..10_000_000_000},
        {:max_result_points, "PULSE_QUERY_MAX_RESULT_POINTS", 100_000, 1..1_000_000_000},
        {:max_materialized_samples, "PULSE_QUERY_MAX_MATERIALIZED_SAMPLES", 250_000, 1..1_000_000_000},
        {:max_scan_segments, "PULSE_QUERY_MAX_SCAN_SEGMENTS", 1024, 1..1_000_000},
        {:max_scan_rows, "PULSE_QUERY_MAX_SCAN_ROWS", 1_000_000, 1..1_000_000_000},
        {:max_scan_bytes, "PULSE_QUERY_MAX_SCAN_BYTES", 134_217_728, 1..1_099_511_627_776}
      ],
      env_var.(name, nil) not in [nil, ""],
      do: {key, parse_integer.(name, default, range)}

# Wall-clock limit for one query, plus the node's query memory envelope:
# interactive slots (alerting and reliability run one each outside them), each
# with a process heap ceiling. Size slots * heap well below the memory limit.
query_slots = parse_integer.("PULSE_QUERY_MAX_CONCURRENT", envelope.query_slots, 1..64)

# Tenant registry and lifecycle (Pulse.Tenants); see docs/tenants.md.
tenant_registry_enabled = env_var.("PULSE_TENANT_REGISTRY_ENABLED", "false") in ["1", "true", "yes"]
tenant_cache_ttl_ms = parse_integer.("PULSE_TENANT_REGISTRY_CACHE_TTL_MS", 30_000, 1_000..300_000)
tenant_deletion_grace_ms = parse_integer.("PULSE_TENANT_DELETION_GRACE_MS", 600_000, 60_000..2_592_000_000)

# Node memory pressure (Pulse.MemoryPressure): above PULSE_MEMORY_PRESSURE_PERCENT
# of the limit, new interactive queries get a retryable overload error and idle
# manifest roots are evicted, until memory has stayed 10 points lower for 10 s. The limit is
# PULSE_MEMORY_BUDGET_MB when set, otherwise the cgroup limit, re-read every
# 15 s. 0 disables it.
memory_pressure_percent = parse_integer.("PULSE_MEMORY_PRESSURE_PERCENT", 85, 0..99)

memory_pressure_limit =
  cond do
    memory_pressure_percent == 0 -> nil
    env_var.("PULSE_MEMORY_BUDGET_MB", "") != "" -> envelope.budget_mb * 1_048_576
    config_env() == :prod -> :cgroup
    true -> nil
  end

# Disposable node-local read cache of immutable segment objects: a memory
# tier, plus a disk tier when PULSE_OBJECT_CACHE_DIR names a writable
# directory (for example an emptyDir volume). Off by default in tests, which
# count object reads; cache tests enable it explicitly.
object_cache_memory_mb = if config_env() == :test, do: 0, else: 64

# Disposable cache of encoded manifest roots, bounded by bytes (LRU eviction).
config :pulse, ManifestCache,
  max_bytes: parse_integer.("PULSE_MANIFEST_CACHE_MAX_BYTES", 134_217_728, 1_048_576..68_719_476_736)

config :pulse, ObjectCache,
  memory_bytes: parse_integer.("PULSE_OBJECT_CACHE_MEMORY_MB", object_cache_memory_mb, 0..1_048_576) * 1_048_576,
  disk_dir: env_var.("PULSE_OBJECT_CACHE_DIR", nil),
  disk_bytes: parse_integer.("PULSE_OBJECT_CACHE_DISK_MB", 4096, 0..104_857_600) * 1_048_576

config :pulse, Pulse.IngestAdmission,
  max_concurrent: ingest_max_concurrent,
  reserved_per_signal: ingest_reserved,
  max_pending_bytes: ingest_max_pending_bytes

config :pulse, Pulse.IngestLimits, ingest_limits
config :pulse, Pulse.MemoryPressure, high_percent: memory_pressure_percent, limit: memory_pressure_limit

config :pulse, Pulse.QueryRunner,
  timeout_ms: parse_integer.("PULSE_QUERY_TIMEOUT_MS", 10_000, 1_000..300_000),
  max_interactive: query_slots,
  # Interactive slots plus the alerting and reliability workers.
  max_global: query_slots + 2,
  max_heap_words: div(parse_integer.("PULSE_QUERY_MAX_HEAP_MB", envelope.query_heap_mb, 16..16_384) * 1_048_576, 8)

config :pulse, Pulse.ResourceBudget, budget_mb: envelope.budget_mb

# Which work this instance takes on; all roles by default. See docs/scaling.md.
config :pulse, Pulse.Roles, roles: Pulse.Roles.parse!(env_var.("PULSE_ROLES", "ingest,query,maintenance"))

# Per-tenant admission limits; see Pulse.TenantLimits and docs/scaling.md.
config :pulse, Pulse.TenantLimits, limits: Pulse.TenantLimits.parse!(env_var.("PULSE_TENANT_LIMITS_JSON", "{}"))

if tenant_deletion_grace_ms < 2 * tenant_cache_ttl_ms,
  do: raise("PULSE_TENANT_DELETION_GRACE_MS must be at least twice PULSE_TENANT_REGISTRY_CACHE_TTL_MS")

# Admin API credentials: a JSON array of "sha256$<hex>" digests of admin tokens.
admin_token_hashes =
  case JSON.decode(env_var.("PULSE_ADMIN_TOKENS", "[]")) do
    {:ok, hashes} when is_list(hashes) ->
      if Enum.all?(hashes, &(is_binary(&1) and Regex.match?(~r/\Asha256\$[0-9a-f]{64}\z/, &1))),
        do: hashes,
        else: raise("PULSE_ADMIN_TOKENS entries must be sha256$<64 lowercase hex> digests")

    _ ->
      raise "PULSE_ADMIN_TOKENS must be a JSON array of sha256$<hex> digests"
  end

config :pulse, Pulse.Tenants,
  enabled: tenant_registry_enabled,
  cache_ttl_ms: tenant_cache_ttl_ms,
  deletion_grace_ms: tenant_deletion_grace_ms,
  purge_interval_ms: parse_integer.("PULSE_TENANT_PURGE_INTERVAL_MS", 60_000, 1_000..3_600_000),
  max_lookups_per_second: parse_integer.("PULSE_TENANT_REGISTRY_MAX_LOOKUPS_PER_SECOND", 100, 1..100_000)

# Per-tenant usage metering (Pulse.Usage); see docs/tenants.md#usage-metering.
config :pulse, Pulse.Usage,
  enabled: env_var.("PULSE_USAGE_ENABLED", "false") in ["1", "true", "yes"],
  flush_interval_ms: parse_integer.("PULSE_USAGE_FLUSH_INTERVAL_MS", 60_000, 1_000..3_600_000)

config :pulse, PulseWeb.AdminController, token_hashes: admin_token_hashes
config :pulse, PulseWeb.Endpoint, http: [port: String.to_integer(env_var.("PORT", "4000"))]

# Browser origins allowed to call POST /mcp, comma-separated
# (e.g. "https://atlas.example.com"). Requests without an Origin header are
# always accepted; any other origin is rejected with 403.
config :pulse, PulseWeb.MCPController,
  allowed_origins:
    "PULSE_MCP_ALLOWED_ORIGINS"
    |> env_var.("")
    # Concurrent Loki live tails per tenant on each instance, and how often an
    # instance with tails reads the tenant's log manifest for other instances' pushes.
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)

config :pulse, Tail,
  max_per_tenant: parse_integer.("PULSE_LOKI_TAIL_MAX_PER_TENANT", 10, 1..1000),
  poll_interval_ms: parse_integer.("PULSE_LOKI_TAIL_POLL_INTERVAL_MS", 1_000, 100..60_000)

if query_budgets != [] do
  config :pulse, Evaluator, query_budgets
  config :pulse, Pulse.QueryRunner, Keyword.take(query_budgets, [:max_scan_rows, :max_scan_bytes, :max_scan_segments])
end

# OTLP/gRPC receiver for logs, metrics and traces. Disabled unless a port is
# set; 4317 is the conventional OTLP/gRPC port.
config :pulse, PulseWeb.OTLPGRPC,
  enabled: env_var.("PULSE_OTLP_GRPC_PORT", nil) not in [nil, ""],
  port: parse_integer.("PULSE_OTLP_GRPC_PORT", 4317, 0..65_535),
  ip: env_var.("PULSE_OTLP_GRPC_IP", "0.0.0.0"),
  max_message_bytes: parse_integer.("PULSE_OTLP_GRPC_MAX_MESSAGE_BYTES", 16_777_216, 1..268_435_456),
  max_in_flight: parse_integer.("PULSE_OTLP_GRPC_MAX_IN_FLIGHT", 64, 1..4096),
  timeout_ms: parse_integer.("PULSE_OTLP_GRPC_TIMEOUT_MS", 30_000, 1..600_000)

# Full retained-context scans are experimental until trace postings exist.
config :pulse, TempoSearch, enabled: env_var.("PULSE_TEMPO_SEARCH_ENABLED", "false") in ["1", "true", "yes"]

# Log storage adapter. Tests keep the in-memory adapter (see config/test.exs);
# dev and prod use the S3 adapter against any S3-compatible endpoint. RustFS
# runs locally via docker-compose.yml — the dev defaults below match its
# out-of-the-box credentials. Prod requires the env vars to be set explicitly.
case config_env() do
  :dev ->
    config :pulse, Pulse.Storage, adapter: S3

    config :pulse, S3,
      compaction_enabled: metrics_compaction_enabled,
      trace_compaction_enabled: trace_compaction_enabled,
      trace_context_horizon_ms: trace_context_horizon_ms,
      log_compaction_enabled: log_compaction_enabled,
      metric_finalize_enabled: metric_finalize_enabled,
      log_rollup_enabled: log_rollup_enabled,
      log_finalize_enabled: log_finalize_enabled,
      manifest_backup_enabled: manifest_backup_enabled,
      manifest_backup_interval_ms: parse_integer.("PULSE_MANIFEST_BACKUP_INTERVAL_MS", 900_000, 60_000..86_400_000),
      query_prefetch: parse_integer.("PULSE_QUERY_PREFETCH", 4, 1..64),
      ingest_flush_interval_ms: ingest_flush_interval_ms,
      metric_footer_pruning_enabled: metric_footer_pruning_enabled,
      manifest_format: manifest_format,
      bucket: env_var.("PULSE_S3_BUCKET", "pulse"),
      # mise/utilities/dev_instance_env.sh sets PULSE_S3_ENDPOINT per worktree.
      # The fallback matches the docker-compose default host port when mise
      # is not in the loop.
      endpoint: env_var.("PULSE_S3_ENDPOINT", "http://localhost:11100"),
      region: env_var.("PULSE_S3_REGION", "us-east-1"),
      access_key_id: env_var.("PULSE_S3_ACCESS_KEY_ID", "rustfsadmin"),
      secret_access_key: env_var.("PULSE_S3_SECRET_ACCESS_KEY", "rustfsadmin"),
      allow_http: env_var.("PULSE_S3_ALLOW_HTTP", "true") in ["1", "true", "yes"]

  :prod ->
    require_env = fn name ->
      case env_var.(name, nil) do
        value when is_binary(value) and value != "" ->
          value

        _ ->
          raise """
          environment variable #{name} is missing or empty.
          Pulse.Storage.S3 requires bucket/region/credentials in prod.
          """
      end
    end

    # Tenant tokens. Expected shape: a JSON object mapping tenant name to
    # "sha256$<hex-of-sha256-of-token>". Deployments compute the hash offline
    # and store only the digest in env, never the plaintext token.
    tokens =
      case env_var.("PULSE_TENANT_TOKENS", nil) do
        blob when is_binary(blob) and blob != "" ->
          case JSON.decode(blob) do
            {:ok, map} when is_map(map) ->
              map

            {:ok, _} ->
              raise "PULSE_TENANT_TOKENS must decode to a JSON object"

            {:error, reason} ->
              raise "PULSE_TENANT_TOKENS is not valid JSON: #{inspect(reason)}"
          end

        _ when workload_trust != [] or tenant_registry_enabled or issuer_config != nil ->
          %{}

        _ ->
          raise """
          environment variable PULSE_TENANT_TOKENS is missing or empty.
          Pulse.Auth.SharedSecret requires at least one tenant token in prod
          unless PULSE_WORKLOAD_IDENTITY_JSON configures workload identity,
          PULSE_TENANT_REGISTRY_ENABLED provisions tenants through the admin API,
          or PULSE_ISSUER_JSON configures a trusted issuer.
          """
      end

    config :pulse, Pulse.Auth,
      module: SharedSecret,
      tokens: tokens

    config :pulse, Pulse.Storage, adapter: S3

    config :pulse, S3,
      compaction_enabled: metrics_compaction_enabled,
      trace_compaction_enabled: trace_compaction_enabled,
      trace_context_horizon_ms: trace_context_horizon_ms,
      log_compaction_enabled: log_compaction_enabled,
      metric_finalize_enabled: metric_finalize_enabled,
      log_rollup_enabled: log_rollup_enabled,
      log_finalize_enabled: log_finalize_enabled,
      manifest_backup_enabled: manifest_backup_enabled,
      manifest_backup_interval_ms: parse_integer.("PULSE_MANIFEST_BACKUP_INTERVAL_MS", 900_000, 60_000..86_400_000),
      query_prefetch: parse_integer.("PULSE_QUERY_PREFETCH", 4, 1..64),
      ingest_flush_interval_ms: ingest_flush_interval_ms,
      metric_footer_pruning_enabled: metric_footer_pruning_enabled,
      manifest_format: manifest_format,
      bucket: require_env.("PULSE_S3_BUCKET"),
      endpoint: env_var.("PULSE_S3_ENDPOINT", nil),
      region: require_env.("PULSE_S3_REGION"),
      access_key_id: require_env.("PULSE_S3_ACCESS_KEY_ID"),
      secret_access_key: require_env.("PULSE_S3_SECRET_ACCESS_KEY"),
      allow_http: env_var.("PULSE_S3_ALLOW_HTTP", "false") in ["1", "true", "yes"]

  :test ->
    :noop
end

# Shared by dev and prod; merged into the S3 adapter configuration above.
if config_env() in [:dev, :prod] do
  # Tests keep immediate refusal unless they configure a queue themselves.
  config :pulse, Pulse.QueryRunner, queue_ms: parse_integer.("PULSE_QUERY_QUEUE_MS", 5_000, 0..60_000)
  config :pulse, S3, retention_config
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    env_var.("SECRET_KEY_BASE", nil) ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = env_var.("PHX_HOST", nil) || "example.com"

  config :pulse, PulseWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :pulse, :dns_cluster_query, env_var.("DNS_CLUSTER_QUERY", nil)

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :pulse, PulseWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :pulse, PulseWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
