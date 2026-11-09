defmodule Pulse.SelfMetrics do
  @moduledoc """
  Disposable, node-local operational counters. Writes use ETS directly, never a
  process mailbox. Dimensions are fixed enums, not tenants, keys, or expressions.
  Scraping never queries signal storage or waits for manifest owners.
  """
  use Pulse.Runtime.GenServer

  alias Pulse.OTLP.Rejections
  alias Pulse.Runtime.GenServer
  alias Pulse.Runtime.Registry
  alias Pulse.Storage.S3.ManifestRegistry

  @table __MODULE__
  @operations %{
    ingest: [:otlp, :otlp_traces, :otlp_metrics, :loki, :remote_write, :sentry],
    query: [:storage_logs, :storage_metrics, :storage_traces, :promql, :logql_log, :logql_metric, :mcp, :http],
    object: [:put, :put_if_match, :put_if_none_match, :get, :get_if_none_match, :delete, :list, :list_prefixes],
    compaction: [
      :compact,
      :cleanup,
      :worker_merge,
      :worker_cleanup,
      :worker_discovery,
      :worker_finalize,
      :worker_consolidate,
      :worker_catalog,
      :worker_log_rollup,
      :worker_log_finalize,
      :worker_log_consolidate,
      :worker_backup
    ]
  }
  @alert_skip_reasons [:authority_missing, :freshness_unavailable, :capacity, :timeout, :budget, :overrun]
  @definitions [
    {"pulse_keyed_publication_conflicts_total", "counter",
     "Keyed appends rejected because existing object bytes differ."},
    {"pulse_alert_evaluation_skips_total", "counter", "Native alert ticks not published, by bounded reason."},
    {"pulse_operations_total", "counter", "Completed operations by layer and outcome."},
    {"pulse_operation_duration_seconds", "summary", "Operation latency; count and sum only, no quantiles."},
    {"pulse_ingest_records_total", "counter", "Decoded records accepted, rejected, or failed at publication."},
    {"pulse_ingest_rejected_records_total", "counter", "Records dropped from accepted requests, by bounded reason."},
    {"pulse_object_payload_bytes_total", "counter",
     "Successful object payload bytes, excluding wire overhead and internal retries."},
    {"pulse_compaction_segments_total", "counter", "Source segments merged by successful compaction."},
    {"pulse_compaction_deleted_objects_total", "counter", "Retired objects deleted by successful cleanup."},
    {"pulse_usage_dropped_total", "counter",
     "Usage counts dropped because an instance already tracks its maximum tenant-hours."},
    {"pulse_tenant_purged_objects_total", "counter", "Objects deleted while purging deleted tenants."},
    {"pulse_manifest_cache_evictions_total", "counter",
     "Cached manifest roots evicted to stay within the manifest cache byte bound."},
    {"pulse_manifest_cache_evicted_bytes_total", "counter", "Encoded root bytes evicted from the manifest cache."},
    {"pulse_memory_pressure_transitions_total", "counter",
     "Node memory-pressure state changes, by the state entered (on, off)."},
    {"pulse_admission_rejections_total", "counter",
     "Requests refused with a retryable overload error, by layer and bounded reason."}
  ]
  @admission_reasons %{ingest: [:tenant_concurrency, :tenant_rate], query: [:node, :tenant, :class, :memory]}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # Every table operation goes through the current runtime's instance name.
  defp table, do: Pulse.Runtime.table(@table)

  @impl true
  def init(_opts) do
    :ets.new(table(), [:named_table, :public, :set, write_concurrency: true, read_concurrency: true])

    for {kind, dimensions} <- @operations, dimension <- dimensions, outcome <- [:success, :error, :exception] do
      labels = operation_labels(kind, dimension, outcome)

      for name <- [
            "pulse_operations_total",
            "pulse_operation_duration_seconds_count",
            "pulse_operation_duration_seconds_sum"
          ] do
        increment(name, labels, 0)
      end
    end

    for signal <- [:logs, :metrics, :traces],
        outcome <- [:accepted, :rejected, :failed],
        do: records(signal, outcome, 0)

    for reason <- Rejections.reasons(:traces), do: rejected_records(:traces, reason, 0)
    for reason <- @alert_skip_reasons, do: increment("pulse_alert_evaluation_skips_total", ~s(reason="#{reason}"), 0)
    increment("pulse_keyed_publication_conflicts_total", "", 0)
    increment("pulse_usage_dropped_total", "", 0)
    increment("pulse_tenant_purged_objects_total", "", 0)
    seed_memory_counters()

    seed_admission_rejections()

    for direction <- [:read, :write], do: object_bytes(direction, 0)
    compaction(:compact, {:ok, %{merged: 0}})
    compaction(:cleanup, {:ok, 0})

    # Handlers are node-global and route each event to the emitting process's
    # runtime instance, so attach once and never re-attach under concurrent events.
    case :telemetry.attach_many(
           __MODULE__,
           [[:phoenix, :endpoint, :start], [:phoenix, :endpoint, :stop], [:phoenix, :error_rendered]],
           &PulseWeb.SelfMetrics.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end

    {:ok, nil}
  end

  defp seed_memory_counters do
    increment("pulse_manifest_cache_evictions_total", "", 0)
    increment("pulse_manifest_cache_evicted_bytes_total", "", 0)
    for state <- [:on, :off], do: increment("pulse_memory_pressure_transitions_total", ~s(state="#{state}"), 0)
  end

  defp seed_admission_rejections do
    for {layer, reasons} <- @admission_reasons,
        reason <- reasons,
        do: increment("pulse_admission_rejections_total", ~s(layer="#{layer}",reason="#{reason}"), 0)
  end

  # Owned (scoped) instances must not detach the handlers other instances share.
  @impl true
  def terminate(_reason, _state) do
    if Pulse.Runtime.name(__MODULE__) == __MODULE__, do: :telemetry.detach(__MODULE__), else: :ok
  end

  @doc "Measure a completed operation without changing its return value or exception."
  def track(kind, dimension, fun) when is_function(fun, 0) do
    start = System.monotonic_time()

    try do
      result = fun.()
      outcome = if match?({:error, _}, result), do: :error, else: :success
      operation(kind, dimension, outcome, System.monotonic_time() - start)
      result
    catch
      class, reason ->
        operation(kind, dimension, :exception, System.monotonic_time() - start)
        :erlang.raise(class, reason, __STACKTRACE__)
    end
  end

  @doc "Object-store operations on this node that returned without an error, of every kind."
  def object_successes do
    Enum.sum_by(Map.fetch!(@operations, :object), fn dimension ->
      case :ets.lookup(table(), {"pulse_operations_total", operation_labels(:object, dimension, :success)}) do
        [{_, count}] -> count
        [] -> 0
      end
    end)
  rescue
    ArgumentError -> 0
  end

  def operation(kind, dimension, outcome, duration)
      when outcome in [:success, :error, :exception] and is_integer(duration) and duration >= 0 do
    if dimension in Map.get(@operations, kind, []) do
      labels = operation_labels(kind, dimension, outcome)
      increment("pulse_operations_total", labels, 1)
      increment("pulse_operation_duration_seconds_count", labels, 1)

      increment(
        "pulse_operation_duration_seconds_sum",
        labels,
        System.convert_time_unit(duration, :native, :microsecond)
      )
    end

    :ok
  end

  defp operation_labels(kind, dimension, outcome) do
    ~s(layer="#{kind}",operation="#{dimension}",outcome="#{outcome}")
  end

  def records(signal, outcome, count)
      when signal in [:logs, :metrics, :traces] and outcome in [:accepted, :rejected, :failed] and is_integer(count) and
             count >= 0 do
    increment("pulse_ingest_records_total", ~s(signal="#{signal}",outcome="#{outcome}"), count)
  end

  @doc "Count records dropped for a fixed-vocabulary reason; no tenant, service or payload data."
  def rejected_records(signal, reason, count)
      when signal in [:logs, :metrics, :traces] and is_atom(reason) and is_integer(count) and count >= 0 do
    increment("pulse_ingest_rejected_records_total", ~s(signal="#{signal}",reason="#{reason}"), count)
  end

  @doc """
  True at most once per `interval_ms` for `key` on this node. Racing callers
  may both see true; this only rate-limits diagnostics.
  """
  def due?(key, interval_ms) do
    now = System.monotonic_time(:millisecond)
    slot = {:due, key}

    case :ets.lookup(table(), slot) do
      [{_, last}] when now - last < interval_ms ->
        false

      _ ->
        :ets.insert(table(), {slot, now})
        true
    end
  rescue
    ArgumentError -> false
  end

  def object_bytes(direction, count) when direction in [:read, :write] and is_integer(count) and count >= 0 do
    increment("pulse_object_payload_bytes_total", ~s(direction="#{direction}"), count)
  end

  def compaction(:compact, {:ok, %{merged: count}}) do
    increment("pulse_compaction_segments_total", "", count)
  end

  def compaction(:cleanup, {:ok, count}) when is_integer(count) do
    increment("pulse_compaction_deleted_objects_total", "", count)
  end

  def compaction(_operation, _result), do: :ok

  @doc "Count a request refused for capacity; reasons are a fixed vocabulary, never tenants."
  def admission_rejection(layer, reason) do
    if reason in Map.get(@admission_reasons, layer, []),
      do: increment("pulse_admission_rejections_total", ~s(layer="#{layer}",reason="#{reason}"), 1),
      else: :ok
  end

  @doc "Count a byte-conflicting keyed append without retaining tenant/key/content data."
  def keyed_publication_conflict, do: increment("pulse_keyed_publication_conflicts_total", "", 1)

  def usage_dropped, do: increment("pulse_usage_dropped_total", "", 1)

  def manifest_cache_evicted(count, bytes) do
    increment("pulse_manifest_cache_evictions_total", "", count)
    increment("pulse_manifest_cache_evicted_bytes_total", "", bytes)
  end

  def memory_pressure(state) when state in [:on, :off],
    do: increment("pulse_memory_pressure_transitions_total", ~s(state="#{state}"), 1)

  def tenant_purged_objects(count), do: increment("pulse_tenant_purged_objects_total", "", count)

  @doc "Record a skipped native tick without retaining tenant/rule/query/provider data."
  def alert_evaluation_skip(reason) when reason in @alert_skip_reasons do
    increment("pulse_alert_evaluation_skips_total", ~s(reason="#{reason}"), 1)
  end

  def alert_evaluation_skip(_), do: :ok

  defp increment(name, labels, value) do
    :ets.update_counter(table(), {name, labels}, {2, value}, {{name, labels}, 0})
    :ok
  rescue
    # Supervision can briefly remove the table. Monitoring must not fail work.
    ArgumentError -> :ok
  end

  @doc "Render Prometheus text format 0.0.4 using only node-local state."
  def render do
    samples = snapshot()

    families = Enum.map(@definitions, &render_family(&1, samples))

    [
      families,
      "# HELP pulse_manifest_queue_depth Pending publication callers plus owner mailbox messages.\n",
      "# TYPE pulse_manifest_queue_depth gauge\n",
      "pulse_manifest_queue_depth #{manifest_queue_depth()}\n",
      render_admission(Pulse.IngestAdmission.stats())
    ]
    |> IO.iodata_to_binary()
  end

  # Node-local ingest admission by signal class; outcomes are a fixed enum.
  defp render_admission(stats) do
    [
      "# HELP pulse_ingest_admission_total Ingest requests admitted, rejected (429; tenant_limited is the subset refused for exceeding a tenant share), or handed off from a slot.\n",
      "# TYPE pulse_ingest_admission_total counter\n",
      for {signal, row} <- stats, outcome <- [:admitted, :rejected, :tenant_limited, :handed_off] do
        ~s(pulse_ingest_admission_total{signal="#{signal}",outcome="#{outcome}"} #{Map.fetch!(row, outcome)}\n)
      end,
      "# HELP pulse_ingest_admission_in_flight Ingest requests holding an admission slot.\n",
      "# TYPE pulse_ingest_admission_in_flight gauge\n",
      for({signal, row} <- stats, do: ~s(pulse_ingest_admission_in_flight{signal="#{signal}"} #{row.in_flight}\n)),
      "# HELP pulse_ingest_admission_active_tenants Tenants holding or recently requesting a slot, per signal.\n",
      "# TYPE pulse_ingest_admission_active_tenants gauge\n",
      for(
        {signal, row} <- stats,
        do: ~s(pulse_ingest_admission_active_tenants{signal="#{signal}"} #{row.active_tenants}\n)
      ),
      "# HELP pulse_ingest_admission_pending_bytes Estimated bytes of slot-free requests awaiting durable publication.\n",
      "# TYPE pulse_ingest_admission_pending_bytes gauge\n",
      "pulse_ingest_admission_pending_bytes #{Pulse.IngestAdmission.pending_bytes()}\n"
    ]
  end

  defp render_family({name, type, help}, samples) do
    names = if type == "summary", do: [name <> "_count", name <> "_sum"], else: [name]

    values =
      samples
      |> Enum.filter(fn
        {{sample_name, _labels}, _value} -> sample_name in names
        _ -> false
      end)
      |> Enum.sort()
      |> Enum.map(&render_sample/1)

    ["# HELP #{name} #{help}\n# TYPE #{name} #{type}\n", values]
  end

  defp render_sample({{name, labels}, value}) do
    value = if String.ends_with?(name, "_seconds_sum"), do: value / 1_000_000, else: value
    labels = if labels == "", do: "", else: "{#{labels}}"
    "#{name}#{labels} #{value}\n"
  end

  defp snapshot do
    :ets.tab2list(table())
  rescue
    ArgumentError -> []
  end

  defp manifest_queue_depth do
    if Pulse.Runtime.whereis(ManifestRegistry) do
      Registry.select(ManifestRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$2", :"$3"}}]}])
      |> Enum.reduce(0, fn owner, total -> total + owner_queue_depth(owner) end)
    else
      0
    end
  rescue
    ArgumentError -> 0
  end

  # Read both legacy integer snapshots and the detailed owner snapshot. Count
  # publication callers here, not segments, to preserve the canonical gauge.
  defp pending_waiters(%{waiters: count}) when is_integer(count), do: count
  defp pending_waiters(count) when is_integer(count), do: count
  defp pending_waiters(_), do: 0

  defp owner_queue_depth({pid, pending}) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, count} -> count + pending_waiters(pending)
      nil -> 0
    end
  end
end
