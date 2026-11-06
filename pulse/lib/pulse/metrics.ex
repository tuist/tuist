defmodule Pulse.Metrics do
  @moduledoc """
  Node-local self-monitoring, exported as Prometheus text without using storage.

  Telemetry handlers update ETS synchronously, with a finite label vocabulary and
  no reporting mailbox. Counters reset when this supervised process restarts.
  """
  use Pulse.Runtime.GenServer

  alias Pulse.PromQL.QuerySlots
  alias Pulse.Runtime.GenServer
  alias Pulse.Runtime.Registry
  alias Pulse.Storage.S3.AppendBuffer
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestRegistry
  alias Pulse.Storage.S3.MetadataCache
  alias Pulse.Storage.S3.ObjectCache

  @table __MODULE__
  @handler {__MODULE__, :metrics}
  @event [:pulse, :operation, :stop]
  @stage_event [:pulse, :ingest, :stage]
  @timeout_event [:pulse, :compaction, :timeout]
  @events [
    @event,
    @stage_event,
    @timeout_event,
    [:phoenix, :endpoint, :start],
    [:phoenix, :endpoint, :stop],
    [:phoenix, :error_rendered]
  ]
  @request_start {__MODULE__, :request_start}
  @buckets [5_000, 10_000, 50_000, 100_000, 500_000, 1_000_000, 5_000_000, 10_000_000]
  @bucket_labels Enum.map(@buckets, &{&1, Float.to_string(&1 / 1_000_000)})
  # Stages are sub-second pieces of one request, so they need finer buckets.
  @stage_buckets [1_000, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000, 2_500_000, 5_000_000]
  @stage_bucket_labels Enum.map(@stage_buckets, &{&1, Float.to_string(&1 / 1_000_000)})
  @signals ["logs", "metrics", "traces"]
  # Request stages (decode, prepare, buffer_wait) are per request; the others
  # are per published segment, which a coalesced flush shares among requests.
  @stages ~w(decode prepare buffer_wait encode summarize segment_put manifest_wait manifest_commit)
  @operations %{
    ingest: ["otlp", "otlp_traces", "otlp_metrics", "loki", "remote_write", "sentry"],
    query: [
      "http_promql",
      "http_logql",
      "http_labels",
      "query_logs",
      "query_metrics",
      "discover_metrics",
      "query_traces",
      "get_trace",
      "search_traces",
      "search_trace_metadata",
      "traceql_metrics",
      "discover_trace_tags",
      "discover_trace_tag_values",
      "alert_tool",
      "query_logql",
      "query_promql",
      "query_errors",
      "list_error_issues",
      "list_error_changes",
      "list_indexed_error_issues",
      "unknown_tool"
    ],
    object: ["put", "put_if_match", "put_if_none_match", "get", "get_if_none_match", "delete", "list", "list_prefixes"],
    compaction: ["compact", "cleanup"],
    retention: ["advance", "cleanup", "cleanup_retired", "sweep"]
  }
  @http_routes %{
    {"POST", ["v1", "logs"]} => {:ingest, "otlp"},
    {"POST", ["v1", "traces"]} => {:ingest, "otlp_traces"},
    {"POST", ["v1", "metrics"]} => {:ingest, "otlp_metrics"},
    {"POST", ["loki", "api", "v1", "push"]} => {:ingest, "loki"},
    {"POST", ["api", "v1", "write"]} => {:ingest, "remote_write"},
    {"GET", ["api", "v1", "query"]} => {:query, "http_promql"},
    {"POST", ["api", "v1", "query"]} => {:query, "http_promql"},
    {"GET", ["api", "v1", "query_range"]} => {:query, "http_promql"},
    {"POST", ["api", "v1", "query_range"]} => {:query, "http_promql"},
    {"GET", ["loki", "api", "v1", "query"]} => {:query, "http_logql"},
    {"POST", ["loki", "api", "v1", "query"]} => {:query, "http_logql"},
    {"GET", ["loki", "api", "v1", "query_range"]} => {:query, "http_logql"},
    {"POST", ["loki", "api", "v1", "query_range"]} => {:query, "http_logql"},
    {"GET", ["loki", "api", "v1", "labels"]} => {:query, "http_labels"}
  }
  @families [
    {"pulse_operations_total", "counter", "Completed node-local operations by bounded operation and outcome."},
    {"pulse_operation_duration_seconds", "histogram", "Duration of completed node-local operations in seconds."},
    {"pulse_ingest_stage_duration_seconds", "histogram",
     "Ingest time by signal and stage: decode, prepare and buffer_wait per request; encode, summarize, " <>
       "segment_put, manifest_wait and manifest_commit per published segment."},
    {"pulse_ingest_records_total", "counter",
     "Known receiver record deliveries accepted or rejected, not unique stored rows."},
    {"pulse_object_bytes_total", "counter",
     "Successful logical object body bytes, excluding native retries and headers."},
    {"pulse_object_requests_total", "counter",
     "Logical object requests by billing class (A: PUT/LIST, B: GET; free: DELETE, 304 and 412 responses) " <>
       "and purpose, excluding native retries."},
    {"pulse_compaction_segments_total", "counter",
     "Source segments merged or retirement deletions confirmed by successful maintenance calls."},
    {"pulse_compaction_timeouts_total", "counter",
     "Background worker deadlines exceeded, including still-running native work."},
    {"pulse_manifest_commit_duration_seconds", "histogram",
     "Manifest publications by signal, root format and encoded root size bucket (root_bytes_le): " <>
       "build, encode, page writes and the conditional root write, including conflict retries."}
  ]
  @root_size_labels Enum.map([65_536, 262_144, 1_048_576, 4_194_304, 16_777_216], &{&1, Integer.to_string(&1)})
  @purposes ["none", "segment", "manifest", "metadata_page", "backup", "other"]
  @outcomes ["ok", "error", "exception", "conflict", "not_modified", "not_found", "rejected"]
  @gauge_help %{
    "pulse_manifest_mailbox_messages" => "Messages in node-local manifest-owner mailboxes.",
    "pulse_manifest_pending_segments" => "Segments in node-local publication batches, including in-flight batches.",
    "pulse_manifest_waiting_requests" => "Requests waiting in node-local manifest publication batches.",
    "pulse_ingest_buffers" => "Active node-local unkeyed ingest buffers.",
    "pulse_ingest_buffer_reserved_calls" => "Queued and executing requests reserved in unkeyed ingest buffers.",
    "pulse_ingest_buffer_input_bytes" =>
      "Estimated external-term bytes reserved in unkeyed ingest buffers, not heap size.",
    "pulse_ingest_buffer_rows" => "Queued and executing rows reserved in unkeyed ingest buffers.",
    "pulse_query_occupied_slots" => "Registered node-local PromQL tenant query slots.",
    "pulse_retention_root_capacity_ratio" =>
      "Worst metadata capacity ratio among locally cached managed scopes, without tenant labels.",
    "pulse_retention_pending_buckets" => "Expired buckets awaiting reclamation in locally cached managed scopes.",
    "pulse_retention_managed_scopes" => "Retention-managed tenant/signal scopes cached on this node.",
    "pulse_vm_memory_bytes" => "Total BEAM-reported memory in bytes.",
    "pulse_ingest_inflight_requests" => "Ingest requests holding a node-local admission slot.",
    "pulse_ingest_max_concurrent_requests" => "Node-local ingest admission slots.",
    "pulse_query_inflight" => "Interactive queries holding a node-local slot.",
    "pulse_query_max_concurrent" => "Node-local interactive query slots.",
    "pulse_memory_budget_bytes" => "Memory budget that sized this node's slots; 0 when fixed defaults apply.",
    "pulse_vm_run_queue" => "BEAM scheduler run-queue length.",
    "pulse_memory_pressure" => "1 while this node sheds caches and refuses new interactive queries for memory.",
    "pulse_memory_pressure_limit_bytes" =>
      "Memory limit the pressure monitor compares resident memory with; 0 when disabled or unknown.",
    "pulse_manifest_cache_max_bytes" => "Byte bound on encoded manifest roots cached on this node.",
    "pulse_manifest_page_cache_entries" => "Immutable manifest pages in this node's bounded page cache.",
    "pulse_manifest_page_cache_bytes" =>
      "Accounted bytes of this node's bounded manifest page cache (16 MiB ceiling), including table memory.",
    "pulse_object_cache_bytes" => "Bytes of segment objects in this node's read cache, by tier.",
    "pulse_object_cache_entries" => "Segment objects in this node's read cache, by tier.",
    "pulse_object_cache_reads_total" =>
      "Segment reads through the node-local object cache by result: memory/disk hits, misses that issued a GET, " <>
        "and reads that shared a concurrent GET."
  }

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # Every table operation goes through the current runtime's instance name.
  defp table, do: Pulse.Runtime.table(@table)

  @impl true
  def init(_opts) do
    :ets.new(table(), [:named_table, :public, :set, write_concurrency: true])
    # Handlers are node-global and route each event to the emitting process's
    # runtime instance, so attach once and never re-attach under concurrent events.
    case :telemetry.attach_many(@handler, @events, &__MODULE__.handle_event/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end

    {:ok, nil}
  end

  # Owned (scoped) instances must not detach the handlers other instances share.
  @impl true
  def terminate(_reason, _state) do
    if Pulse.Runtime.name(__MODULE__) == __MODULE__, do: :telemetry.detach(@handler), else: :ok
  end

  @doc "Measure an operation without changing its result or exception semantics."
  def measure(kind, operation, fun, measurements \\ fn _ -> %{} end, purpose \\ "none") do
    started = System.monotonic_time()

    try do
      result = fun.()
      report(kind, operation, purpose, outcome(result), started, measurements.(result))
      result
    catch
      kind_of_error, reason ->
        report(kind, operation, purpose, "exception", started, %{})
        :erlang.raise(kind_of_error, reason, __STACKTRACE__)
    end
  end

  @doc "Append a decoded receiver batch; count accepted records only after durable success."
  def append(signal, tenant, records, rejected, opts) do
    # Storage owns accepted/failed canonical counts; decoder rejections are
    # known here, before append. The detailed delivery view has its own family.
    :ok = Pulse.SelfMetrics.records(signal, :rejected, rejected)
    # Count first: a caller waiting for durable publication must not keep its
    # records alive (see Pulse.IngestAdmission.handoff/1).
    count = length(records)

    try do
      result = Pulse.Storage.append(signal, tenant, records, opts)
      record_counts(signal, if(result == :ok, do: count, else: 0), rejected + if(result == :ok, do: 0, else: count))
      result
    catch
      kind, reason ->
        record_counts(signal, 0, rejected + count)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp record_counts(signal, accepted, rejected) when signal in [:logs, :metrics, :traces] do
    increment({"pulse_ingest_records_total", [{"signal", to_string(signal)}, {"outcome", "accepted"}]}, accepted)
    increment({"pulse_ingest_records_total", [{"signal", to_string(signal)}, {"outcome", "rejected"}]}, rejected)
  end

  defp report(kind, operation, purpose, outcome, started, measurements) do
    :telemetry.execute(@event, Map.put(measurements, :duration, System.monotonic_time() - started), %{
      kind: kind,
      operation: operation,
      purpose: purpose,
      outcome: outcome
    })
  end

  @doc """
  Report one ingest stage of `signal` that began at `started` (native monotonic
  time). Signals and stages outside the fixed vocabulary are ignored.
  """
  def stage(signal, stage, started),
    do:
      :telemetry.execute(@stage_event, %{duration: System.monotonic_time() - started}, %{signal: signal, stage: stage})

  @doc "Run `fun` as one ingest stage of `signal`, returning its result."
  def time_stage(signal, stage, fun) do
    started = System.monotonic_time()

    try do
      fun.()
    after
      stage(signal, stage, started)
    end
  end

  @doc """
  Record one manifest publication of `signal` that began at `started` (native
  monotonic time) and wrote a root of `bytes` in format `version`.
  """
  def manifest_commit(signal, version, bytes, started) when signal in @signals and is_integer(bytes) do
    format =
      case version do
        4 -> "paged"
        3 -> "retention"
        _ -> "flat"
      end

    size = Enum.find_value(@root_size_labels, "+Inf", fn {bound, label} -> if bytes <= bound, do: label end)

    record_histogram(
      "pulse_manifest_commit_duration_seconds",
      [{"signal", signal}, {"format", format}, {"root_bytes_le", size}],
      System.convert_time_unit(System.monotonic_time() - started, :native, :microsecond),
      @stage_bucket_labels
    )
  end

  def manifest_commit(_signal, _version, _bytes, _started), do: :ok

  defp outcome({:error, reason}) when reason in [:already_exists, :precondition_failed], do: "conflict"
  defp outcome({:error, :not_found}), do: "not_found"
  defp outcome({:error, _}), do: "error"
  defp outcome(:not_modified), do: "not_modified"
  defp outcome(_), do: "ok"

  @doc false
  def handle_event(@event, measurements, metadata, _config) do
    kind = metadata[:kind]
    operation = metadata[:operation]
    purpose = metadata[:purpose]
    outcome = metadata[:outcome]

    if valid_event?(measurements, kind, operation, purpose, outcome) do
      labels = [{"kind", to_string(kind)}, {"operation", operation}, {"purpose", purpose}, {"outcome", outcome}]
      increment({"pulse_operations_total", labels}, 1)
      record_duration(labels, System.convert_time_unit(measurements.duration, :native, :microsecond))
      record_work(kind, operation, purpose, measurements)
      if kind == :object, do: increment({"pulse_object_requests_total", request_class(operation, outcome, purpose)}, 1)
    end
  end

  def handle_event(@stage_event, %{duration: duration}, %{signal: signal, stage: stage}, _config)
      when is_integer(duration) and duration >= 0 do
    {signal, stage} = {to_string(signal), to_string(stage)}

    if signal in @signals and stage in @stages do
      record_histogram(
        "pulse_ingest_stage_duration_seconds",
        [{"signal", signal}, {"stage", stage}],
        System.convert_time_unit(duration, :native, :microsecond),
        @stage_bucket_labels
      )
    end
  end

  def handle_event(@stage_event, _measurements, _metadata, _config), do: :ok

  def handle_event(@timeout_event, _measurements, metadata, _config) do
    operation = metadata[:operation]

    if operation in ["merge", "cleanup", "discovery"],
      do: increment({"pulse_compaction_timeouts_total", [{"operation", operation}]}, 1)
  end

  def handle_event([:phoenix, :endpoint, :start], _measurements, metadata, _config) do
    Process.delete(@request_start)
    if http_operation(metadata.conn), do: Process.put(@request_start, System.monotonic_time())
    :ok
  end

  def handle_event(event, _measurements, metadata, config) do
    # Plug's stop hook may run while Phoenix renders an exception, or Phoenix
    # may render from the original conn without that hook. Whichever arrives
    # first completes the request; the other must not double-count it.
    with started when is_integer(started) <- Process.delete(@request_start),
         {kind, operation} <- http_operation(metadata.conn) do
      phase = if event == [:phoenix, :error_rendered], do: :exception, else: :stop
      measurements = %{duration: System.monotonic_time() - started}

      handle_event(
        @event,
        measurements,
        %{kind: kind, operation: operation, purpose: "none", outcome: http_outcome(phase, metadata)},
        config
      )
    else
      _ -> :ok
    end
  end

  # S3 request classes as object stores bill them: writes and listings are
  # Class A, reads Class B. DELETE, 304 Not Modified and 412/409 conflicts are
  # free on Tigris (and its published list of free error responses).
  defp request_class(operation, outcome, purpose) do
    class =
      cond do
        operation == "delete" or outcome in ["conflict", "not_modified"] -> "free"
        operation in ["get", "get_if_none_match"] -> "B"
        true -> "A"
      end

    [{"class", class}, {"purpose", purpose}]
  end

  defp valid_event?(measurements, kind, operation, purpose, outcome) do
    operation in Map.get(@operations, kind, []) and purpose in @purposes and outcome in @outcomes and
      is_integer(measurements[:duration]) and measurements.duration >= 0
  end

  defp record_duration(labels, duration),
    do: record_histogram("pulse_operation_duration_seconds", labels, duration, @bucket_labels)

  defp record_histogram(family, labels, duration, bucket_labels) do
    increment({family <> "_count", labels}, 1)
    increment({family <> "_sum", labels}, duration)

    for {bound, label} <- bucket_labels do
      increment({family <> "_bucket", labels ++ [{"le", label}]}, if(duration <= bound, do: 1, else: 0))
    end

    increment({family <> "_bucket", labels ++ [{"le", "+Inf"}]}, 1)
  end

  defp record_work(:object, operation, purpose, measurements) do
    for direction <- [:read, :write], bytes = Map.get(measurements, direction), is_integer(bytes) and bytes >= 0 do
      increment(
        {"pulse_object_bytes_total",
         [{"operation", operation}, {"purpose", purpose}, {"direction", to_string(direction)}]},
        bytes
      )
    end
  end

  defp record_work(:compaction, operation, _purpose, measurements) do
    count = Map.get(measurements, :segments, 0)

    if is_integer(count) and count >= 0,
      do: increment({"pulse_compaction_segments_total", [{"operation", operation}]}, count)
  end

  defp record_work(_kind, _operation, _purpose, _measurements), do: :ok

  defp http_operation(conn) do
    # Match the router's decoded segments, not a decoded whole request_path:
    # empty segments are discarded upstream, but an encoded slash stays inside
    # its segment and must not become a separator here.
    path = Enum.map(conn.path_info, &URI.decode/1)
    Map.get(@http_routes, {conn.method, path}) || label_operation(conn.method, path)
  end

  defp label_operation("GET", ["loki", "api", "v1", "label", _name, "values"]), do: {:query, "http_labels"}

  defp label_operation("POST", ["api", _project, endpoint]) when endpoint in ["envelope", "store"],
    do: {:ingest, "sentry"}

  defp label_operation(_method, _path), do: nil

  defp http_outcome(:stop, %{conn: %{status: status}}) when status < 400, do: "ok"
  defp http_outcome(:stop, %{conn: %{status: status}}) when status < 500, do: "rejected"
  defp http_outcome(:stop, _), do: "error"

  defp http_outcome(:exception, metadata) do
    reason = metadata[:reason]
    if is_exception(reason) and Plug.Exception.status(reason) < 500, do: "rejected", else: "exception"
  end

  # A metrics process restart must never fail the operation being observed.
  defp increment(key, amount) do
    :ets.update_counter(table(), key, {2, amount}, {key, 0})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Render counters and instantaneous queue gauges, without storage I/O."
  def render do
    families = snapshot() |> Enum.group_by(&counter_family/1)

    [
      Enum.map(@families, fn {name, type, help} ->
        samples = families |> Map.get(name, []) |> Enum.sort_by(&counter_order/1)
        [metric_header(name, type, help), Enum.map(samples, &render_counter/1)]
      end),
      render_gauges()
    ]
    |> IO.iodata_to_binary()
  end

  defp snapshot do
    :ets.tab2list(table())
  rescue
    ArgumentError -> []
  end

  defp counter_family({{name, _labels}, _value}) do
    case name do
      "pulse_operation_duration_seconds_" <> _ -> "pulse_operation_duration_seconds"
      "pulse_ingest_stage_duration_seconds_" <> _ -> "pulse_ingest_stage_duration_seconds"
      "pulse_manifest_commit_duration_seconds_" <> _ -> "pulse_manifest_commit_duration_seconds"
      _ -> name
    end
  end

  # Prometheus requires histogram buckets in numerical order, with +Inf last.
  defp counter_order({{"pulse_operation_duration_seconds_" <> suffix, labels}, _}),
    do: histogram_order("pulse_operation_duration_seconds", suffix, labels, @bucket_labels)

  defp counter_order({{"pulse_ingest_stage_duration_seconds_" <> suffix, labels}, _}),
    do: histogram_order("pulse_ingest_stage_duration_seconds", suffix, labels, @stage_bucket_labels)

  defp counter_order({{"pulse_manifest_commit_duration_seconds_" <> suffix, labels}, _}),
    do: histogram_order("pulse_manifest_commit_duration_seconds", suffix, labels, @stage_bucket_labels)

  defp counter_order({{name, labels}, _}), do: {name, labels, 0}

  defp histogram_order(family, "bucket", labels, bucket_labels) do
    {"le", bound} = List.last(labels)

    rank =
      if bound == "+Inf",
        do: length(bucket_labels),
        else: Enum.find_index(bucket_labels, fn {_, label} -> label == bound end)

    {family, Enum.drop(labels, -1), rank}
  end

  defp histogram_order(family, "count", labels, bucket_labels), do: {family, labels, length(bucket_labels) + 1}
  defp histogram_order(family, "sum", labels, bucket_labels), do: {family, labels, length(bucket_labels) + 2}

  defp exported_name("pulse_operations_total"), do: "pulse_detailed_operations_total"

  defp exported_name("pulse_operation_duration_seconds" <> suffix),
    do: "pulse_detailed_operation_duration_seconds" <> suffix

  defp exported_name("pulse_ingest_records_total"), do: "pulse_ingest_delivery_records_total"
  defp exported_name("pulse_compaction_segments_total"), do: "pulse_detailed_compaction_segments_total"
  defp exported_name(name), do: name

  defp render_counter({{name, labels}, value}) do
    value =
      if name in [
           "pulse_operation_duration_seconds_sum",
           "pulse_ingest_stage_duration_seconds_sum",
           "pulse_manifest_commit_duration_seconds_sum"
         ],
         do: seconds(value),
         else: Integer.to_string(value)

    [
      exported_name(name),
      "{",
      Enum.map_join(labels, ",", fn {key, value} -> "#{key}=\"#{value}\"" end),
      "} ",
      value,
      "\n"
    ]
  end

  defp render_gauges do
    {mailbox, pending, waiters} = manifest_queues()
    {buffers, reserved_calls, input_bytes, input_rows} = AppendBuffer.stats()
    retention = ManifestCache.retention_statistics()
    capacity = Enum.map(retention, & &1.capacity_ratio) |> Enum.max(fn -> 0.0 end)
    expired = Enum.reduce(retention, 0, &(&1.pending_buckets + &2))

    [
      gauge("pulse_manifest_mailbox_messages", mailbox),
      gauge("pulse_manifest_pending_segments", pending),
      gauge("pulse_manifest_waiting_requests", waiters),
      gauge("pulse_ingest_buffers", buffers),
      gauge("pulse_ingest_buffer_reserved_calls", reserved_calls),
      gauge("pulse_ingest_buffer_input_bytes", input_bytes),
      gauge("pulse_ingest_buffer_rows", input_rows),
      gauge("pulse_query_occupied_slots", occupied_queries()),
      gauge("pulse_retention_root_capacity_ratio", capacity),
      gauge("pulse_retention_pending_buckets", expired),
      gauge("pulse_retention_managed_scopes", length(retention)),
      gauge("pulse_vm_memory_bytes", :erlang.memory(:total)),
      # Saturation, for autoscaling on slot occupancy rather than memory.
      gauge("pulse_ingest_inflight_requests", Pulse.IngestAdmission.in_flight()),
      gauge("pulse_ingest_max_concurrent_requests", Pulse.IngestAdmission.limits().max),
      gauge("pulse_query_inflight", Pulse.QueryRunner.interactive_in_flight()),
      gauge("pulse_query_max_concurrent", Pulse.QueryRunner.max_interactive()),
      gauge("pulse_memory_budget_bytes", memory_budget_bytes()),
      gauge("pulse_vm_run_queue", :erlang.statistics(:run_queue)),
      gauge("pulse_memory_pressure", if(Pulse.MemoryPressure.active?(), do: 1, else: 0)),
      gauge("pulse_memory_pressure_limit_bytes", elem(Pulse.MemoryPressure.stats(), 1) || 0),
      gauge("pulse_manifest_cache_max_bytes", ManifestCache.max_bytes()),
      manifest_size_gauges(),
      Pulse.MemoryStats.render()
    ]
  end

  # Flat roots are rewritten whole on every publication, so their size is the
  # main driver of manifest commit time. Paged roots list only their tail and
  # reference the rest through immutable pages.
  defp manifest_size_gauges do
    sizes = ManifestCache.sizes()
    {page_entries, page_bytes} = MetadataCache.stats()

    [
      for {name, index, help} <- [
            {"pulse_manifest_segments", 0, "Segments listed in cached manifest roots, summed over tenants."},
            {"pulse_manifest_bytes", 1, "Encoded bytes of cached manifest roots, summed over tenants."},
            {"pulse_manifest_referenced_segments", 2,
             "Active segments cached roots reference, including through manifest pages, summed over tenants. " <>
               "Retention-managed roots count only their inline tail."}
          ] do
        [
          metric_header(name, "gauge", help),
          for signal <- @signals do
            value = sizes |> Map.get(signal, %{}) |> Map.get(index, 0)
            [name, "{signal=\"", signal, "\"} ", Integer.to_string(value), "\n"]
          end
        ]
      end,
      metric_header(
        "pulse_manifest_roots",
        "gauge",
        "Cached manifest roots by signal and format (flat, paged, retention)."
      ),
      for signal <- @signals, format <- ["flat", "paged", "retention"] do
        value = sizes |> Map.get(signal, %{}) |> Map.get(format, 0)
        ["pulse_manifest_roots{signal=\"", signal, "\",format=\"", format, "\"} ", Integer.to_string(value), "\n"]
      end,
      gauge("pulse_manifest_page_cache_entries", page_entries),
      gauge("pulse_manifest_page_cache_bytes", page_bytes),
      object_cache_gauges(),
      stored_bytes_gauges()
    ]
  end

  defp object_cache_gauges do
    stats = ObjectCache.stats()

    [
      for {name, index} <- [{"pulse_object_cache_entries", 0}, {"pulse_object_cache_bytes", 1}] do
        [
          metric_header(name, "gauge", Map.fetch!(@gauge_help, name)),
          for tier <- [:memory, :disk] do
            [
              name,
              "{tier=\"",
              Atom.to_string(tier),
              "\"} ",
              stats |> Map.fetch!(tier) |> elem(index) |> Integer.to_string(),
              "\n"
            ]
          end
        ]
      end,
      metric_header(
        "pulse_object_cache_reads_total",
        "counter",
        Map.fetch!(@gauge_help, "pulse_object_cache_reads_total")
      ),
      for {result, key} <- [memory_hit: :memory_hits, disk_hit: :disk_hits, miss: :misses, shared: :shared] do
        [
          "pulse_object_cache_reads_total{result=\"",
          Atom.to_string(result),
          "\"} ",
          Integer.to_string(stats[key]),
          "\n"
        ]
      end
    ]
  end

  defp stored_bytes_gauges do
    stored = ManifestCache.stored_bytes()
    totals = &Map.get(stored, &1, %{"0-30d" => 0, "30-90d" => 0, "90d+" => 0, unknown: 0})

    [
      metric_header(
        "pulse_manifest_referenced_bytes",
        "gauge",
        "Stored bytes of the active segments cached roots reference, by signal and record age, summed over tenants. " <>
          "Excludes manifests, pages and retired objects awaiting deletion; retention-managed roots count only their tail."
      ),
      for signal <- @signals, age <- ["0-30d", "30-90d", "90d+"] do
        value = totals.(signal) |> Map.fetch!(age) |> Integer.to_string()
        ["pulse_manifest_referenced_bytes{signal=\"", signal, "\",age=\"", age, "\"} ", value, "\n"]
      end,
      metric_header(
        "pulse_manifest_referenced_unsized_segments",
        "gauge",
        "Referenced segments whose size the cached roots do not record (pages written before 1.30), summed over tenants."
      ),
      for signal <- @signals do
        value = totals.(signal) |> Map.fetch!(:unknown) |> Integer.to_string()
        ["pulse_manifest_referenced_unsized_segments{signal=\"", signal, "\"} ", value, "\n"]
      end
    ]
  end

  defp memory_budget_bytes do
    case Keyword.get(Pulse.Runtime.get_env(:pulse, Pulse.ResourceBudget, []), :budget_mb) do
      mb when is_integer(mb) -> mb * 1_048_576
      _ -> 0
    end
  end

  defp manifest_queues do
    registry = ManifestRegistry

    if Pulse.Runtime.whereis(registry) do
      registry
      |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$2", :"$3"}}]}])
      |> Enum.reduce({0, 0, 0}, &add_manifest_queue/2)
    else
      {0, 0, 0}
    end
  rescue
    ArgumentError -> {0, 0, 0}
  end

  defp add_manifest_queue({pid, info}, {mailbox, pending, waiters}) do
    len =
      case Process.info(pid, :message_queue_len) do
        {:message_queue_len, len} -> len
        _ -> 0
      end

    info = if is_map(info), do: info, else: %{}
    {mailbox + len, pending + Map.get(info, :pending, 0), waiters + Map.get(info, :waiters, 0)}
  end

  defp occupied_queries do
    if Pulse.Runtime.whereis(QuerySlots) do
      QuerySlots
      |> Registry.select([{{:_, :"$1", :_}, [], [:"$1"]}])
      |> Enum.uniq()
      |> length()
    else
      0
    end
  rescue
    ArgumentError -> 0
  end

  defp gauge(name, value),
    do: [
      metric_header(name, "gauge", Map.fetch!(@gauge_help, name)),
      name,
      " ",
      if(is_float(value), do: Float.to_string(value), else: Integer.to_string(value)),
      "\n"
    ]

  defp metric_header(name, type, help) do
    name = exported_name(name)
    ["# HELP ", name, " ", help, "\n# TYPE ", name, " ", type, "\n"]
  end

  defp seconds(value), do: Float.to_string(value / 1_000_000)
end
