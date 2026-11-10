defmodule Pulse.Storage.S3 do
  @moduledoc """
  S3-backed signal storage.

  By default, each `append/4` writes one Parquet object under a tenant- and
  signal-scoped, versioned, time-partitioned prefix:

      tenants/<tenant>/v4/signal=<s>/date=<YYYY-MM-DD>/hour=<HH>/<min_ts>-<max_ts>-<suffix>.parquet

  Tenant isolation is enforced by key construction — tenant names are
  validated against a conservative charset, so a batch cannot land
  outside its own prefix. `<min_ts>` and `<max_ts>` are zero-padded
  20-decimal-digit representations of the smallest and largest
  caller-supplied `timestamp_ns` in the batch (records with `nil` map to
  `0`, which sorts first). The `date=` and `hour=` partition components
  are derived from `min_ts` as UTC, so a batch spanning an hour boundary
  files under the hour of its earliest sample — segments are small
  enough (`~1s` flush cadence, `~10 MiB` size cap) that cross-boundary
  spill is negligible, and the chronological `[min_ts, max_ts]` tail
  still gives the manifest a tight prunable range.

  The trailing `<suffix>` depends on whether the caller supplied an
  `idempotency_key`:

    * **With `idempotency_key`** — the suffix is a deterministic hash of
      `tenant || idempotency_key || caller_content_hash`. Two `append`
      calls with the same key AND the same caller-supplied content
      resolve to the same object; a lost-response retry does not
      duplicate. Uploads use conditional creation, and failed creates verify
      existing exact bytes by streaming before manifest registration. A byte
      mismatch fails permanently rather than overwriting or guessing equality.
    * **Without `idempotency_key`** — the suffix is random, so distinct
      calls always produce distinct objects and no content hash is
      computed.

  ## Signal dispatch

  Every call carries an explicit `signal` (`:logs` | `:metrics` | `:traces`). The
  adapter translates to the corresponding Rust NIF entry point
  (`encode_log_segment_parquet`, `encode_metric_segment_parquet`, or
  `encode_trace_segment_parquet`) and back. Logs and traces sort by
  `(service, timestamp_ns)`, metrics by `(series_id, timestamp_ns)`.
  Traces additionally retain trace/span IDs as sort tiebreakers. See `Pulse.Codec.NIF`.

  ## Optional unkeyed coalescing

  With `ingest_flush_interval_ms` enabled, concurrent unkeyed requests can
  share a segment. Node-local input reservations bound the buffer at 128
  callers, 100,000 rows, and 10 MiB of estimated term bytes. Overflow and
  oversized batches use the unbuffered path. Keyed requests retain their
  original fingerprint/retry semantics and are never combined. Every caller
  still waits for segment PUT and manifest CAS before acknowledgment.

  ## Manifest coordination

  Every accepted append is registered in the per-`(tenant, signal)`
  manifest via `Pulse.Storage.S3.ManifestOwner`. The owner batches
  concurrent registrations into a single S3 CAS per flush window so
  ingest throughput is decoupled from S3 CAS latency. `query/3` reads
  the manifest from the ETS-backed cache
  (`Pulse.Storage.S3.ManifestCache`), prunes by time bounds, and only
  fetches segments that could contribute records.

  Only after both the segment PUT and the manifest CAS succeed does
  `append/4` return `:ok`. That is the load-bearing durability point.

  ## Key format stability

  Every object lives under a versioned prefix (`tenants/<t>/v4/…`).
  Within one schema version, the exact suffix format is deliberately
  not a public API. Any change to the fingerprint, the delimiter, the
  sort-key width, the number of bounds segments, or the partitioning
  scheme bumps the schema version — new writes go to `v5/`, old objects
  stay at `v4/`, and a compaction job migrates at its own pace.
  """

  @behaviour Pulse.Storage

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.QueryLimit
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Record.Span
  alias Pulse.Record.SpanKey
  alias Pulse.Runtime
  alias Pulse.Storage.S3.AppendBuffer
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.KeyedPublication
  alias Pulse.Storage.S3.LogRollups
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.MetadataCache
  alias Pulse.Storage.S3.MetricCatalog
  alias Pulse.Storage.S3.MetricFooterReader
  alias Pulse.Storage.S3.MetricMetadataStore
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.ObjectCache
  alias Pulse.Storage.S3.PagedManifest
  alias Pulse.Storage.S3.Retention
  alias Pulse.Storage.S3.TraceSummary
  alias Pulse.Storage.SortOrder
  alias Pulse.Traces.SearchExpression
  alias Pulse.Traces.TempoDiscovery

  @tenant_regex ~r/\A[A-Za-z0-9_.\-]{1,128}\z/
  # 20 decimal digits fits a u64 nanosecond timestamp (max ~1.84e19). Zero-padding
  # keeps S3's UTF-8 list order chronological by write time (`sort_ns`).
  @sort_key_width 20
  # 16 hex chars = 64 bits from SHA-256. Collision probability is negligible
  # for the volumes any single tenant will produce in a step-2 adapter.
  @content_hash_width 16
  # Schema version segment. Baked into every object key so a future change
  # to the key format can coexist with older objects rather than orphan them.
  @schema_version "v4"

  @impl Pulse.Storage
  def append(signal, tenant, records, opts \\ [])

  def append(signal, tenant, [], _opts) when is_atom(signal) and is_binary(tenant) do
    # Validate even on empty so an adversarial tenant name is rejected on the
    # first attempt, not only once a real record survives decoding.
    validate_tenant(tenant)
  end

  def append(signal, tenant, records, opts) when is_atom(signal) and is_binary(tenant) and is_list(records) do
    config = Map.new(Runtime.get_env(:pulse, __MODULE__) || %{})
    keyed? = opts[:idempotency_key] not in [nil, ""]

    if not keyed? and Map.get(config, :ingest_flush_interval_ms, 0) > 0 do
      append_buffered(signal, tenant, records, opts, config)
    else
      append_unbuffered(signal, tenant, records, opts)
    end
  end

  defp append_buffered(signal, tenant, records, opts, config) do
    with :ok <- validate_tenant(tenant),
         :ok <- check_retention(signal, tenant, records, config) do
      case AppendBuffer.append(signal, tenant, records, config, opts) do
        {:unbuffered, records} -> append_unbuffered(signal, tenant, records, opts, config)
        result -> result
      end
    end
  end

  @doc false
  def append_unbuffered(signal, tenant, records, opts, config \\ nil) do
    idempotency_key = Keyword.get(opts, :idempotency_key)

    with :ok <- validate_tenant(tenant),
         {:ok, payload, min_ts, max_ts, pruning_safe?} <-
           Pulse.Metrics.time_stage(signal, :encode, fn ->
             encode_for_append(signal, records, idempotency_key not in [nil, ""])
           end) do
      config = config || config!()

      key =
        object_key(
          tenant,
          signal_string(signal),
          min_ts,
          max_ts,
          fingerprint(signal, records, idempotency_key),
          idempotency_key
        )

      with :ok <- append_admission(signal, tenant, records, config, opts) do
        segment = Segment.build(key, min_ts, max_ts, length(records), byte_size(payload))
        publish_segment(signal, tenant, segment, records, payload, pruning_safe?, opts, config)
      end
    end
  end

  # The PUT is provider I/O and the payload a shared binary: upload in a task
  # while this process builds the manifest summary, so summary CPU hides under
  # upload latency instead of adding to every acknowledgment. Registration
  # still waits for the upload, so durability is unchanged. `:on_uploaded`
  # lets a coalescing buffer learn how long its flushes take to reach the owner.
  defp publish_segment(signal, tenant, segment, records, payload, pruning_safe?, opts, config) do
    keyed? = opts[:idempotency_key] not in [nil, ""]

    upload =
      Pulse.Runtime.Task.async(fn ->
        Pulse.Metrics.time_stage(signal, :segment_put, fn -> put_segment(config, segment.key, payload, keyed?, opts) end)
      end)

    segment =
      Pulse.Metrics.time_stage(signal, :summarize, fn -> summarize_segment(signal, segment, records, pruning_safe?) end)

    with :ok <- Pulse.Runtime.Task.await(upload, :infinity) do
      if on_uploaded = opts[:on_uploaded], do: on_uploaded.()
      # The owner may hold a registration for up to one flush interval to share its CAS.
      timeout = 15_000 + Map.get(config, :ingest_flush_interval_ms, 0)
      ManifestOwner.register_segments(tenant, signal_string(signal), [segment], config, timeout)
    end
  end

  defp put_segment(config, key, payload, true, opts), do: KeyedPublication.put(config, key, payload, opts)

  defp put_segment(config, key, payload, false, _opts) do
    with {:ok, _etag} <- ObjectStore.put(config, key, payload), do: ObjectCache.put(key, payload)
  end

  defp append_admission(signal, tenant, records, config, opts) do
    result = check_retention(signal, tenant, records, config)

    case result do
      {:error, reason} when reason in [:retention_expired, :timestamp_too_new] ->
        if opts[:split_admission_errors], do: {:error, {:admission_rejected, reason}}, else: result

      _ ->
        result
    end
  end

  @impl Pulse.Storage
  def query_traces_json(tenant, opts, fields) do
    opts = Keyword.put(opts, :native_json_fields, fields)

    # Projected candidates keep digests instead of complete sort keys. Two
    # different stored copies of one span cannot be ordered from digests, so
    # rerun such (rare) queries with complete keys, reading the sources again.
    case query(:traces, tenant, opts) do
      {:error, :trace_projection_tie} -> query(:traces, tenant, Keyword.put(opts, :full_sort_keys, true))
      result -> result
    end
  end

  @impl true
  def get_trace_json(tenant, trace_id, opts) do
    opts =
      opts
      |> Keyword.take([:max_scan_segments, :max_scan_bytes, :max_scan_rows, :deadline_ms])
      |> Keyword.put(:trace_id, trace_id)
      |> Keyword.put(:limit, 5001)
      # Fail at the 5,001st stored span instead of reading every candidate
      # segment of a huge trace first and failing only at finish.
      |> Keyword.put(:max_records, 5000)
      |> Keyword.put(:assemble_trace, trace_id)

    query_traces_json(tenant, opts, nil)
  end

  @impl Pulse.Storage
  def tempo_windowed_discovery_json(tenant, scope, key, query, start, finish, opts),
    do:
      tempo_discovery_json(
        tenant,
        scope,
        key,
        opts |> Keyword.put(:discovery_query, query) |> Keyword.put(:discovery_window, {start, finish})
      )

  @impl true
  def tempo_unscoped_tag_values_json(tenant, key, opts), do: tempo_discovery_json(tenant, "none", key, opts)

  @impl true
  def tempo_unscoped_tag_values_json(tenant, key, query, opts),
    do: tempo_discovery_json(tenant, "none", key, Keyword.put(opts, :discovery_query, query))

  @impl true
  def tempo_windowed_unscoped_tag_values_json(tenant, key, query, start, finish, opts),
    do: tempo_windowed_discovery_json(tenant, "none", key, query, start, finish, opts)

  @impl true
  def tempo_trace_duration_tag_values_json(tenant, query, opts),
    do: tempo_discovery_json(tenant, "intrinsic", "trace:duration", Keyword.put(opts, :discovery_query, query))

  @impl true
  def tempo_windowed_trace_duration_tag_values_json(tenant, query, start, finish, opts),
    do: tempo_windowed_discovery_json(tenant, "intrinsic", "trace:duration", query, start, finish, opts)

  @impl true
  def tempo_root_tag_values_json(tenant, key, query, opts),
    do: tempo_discovery_json(tenant, "intrinsic", key, Keyword.put(opts, :discovery_query, query))

  @impl true
  def tempo_windowed_root_tag_values_json(tenant, key, query, start, finish, opts),
    do: tempo_windowed_discovery_json(tenant, "intrinsic", key, query, start, finish, opts)

  @impl true
  def tempo_event_time_tag_values_json(tenant, key, query, opts),
    do: tempo_discovery_json(tenant, "intrinsic", key, Keyword.put(opts, :discovery_query, query))

  @impl true
  def tempo_windowed_event_time_tag_values_json(tenant, key, query, start, finish, opts),
    do: tempo_windowed_discovery_json(tenant, "intrinsic", key, query, start, finish, opts)

  @impl true
  def tempo_intrinsic_tag_values_json(tenant, key, query, opts),
    do: tempo_discovery_json(tenant, "intrinsic", key, Keyword.put(opts, :discovery_query, query))

  @impl true
  def tempo_default_tag_names_json(tenant, query, opts),
    do: tempo_discovery_json(tenant, "none", "", Keyword.put(opts, :discovery_query, query))

  @impl true
  def tempo_filtered_tag_names_json(tenant, scope, query, opts),
    do: tempo_discovery_json(tenant, scope, "", Keyword.put(opts, :discovery_query, query))

  @impl Pulse.Storage
  def tempo_filtered_discovery_json(tenant, scope, key, query, opts),
    do: tempo_discovery_json(tenant, scope, key, Keyword.put(opts, :discovery_query, query))

  @impl Pulse.Storage
  def tempo_expression_discovery_json(tenant, scope, key, program, opts) do
    with :ok <- TempoDiscovery.validate(scope, key),
         :ok <- TempoDiscovery.validate_window(opts[:discovery_window]),
         :ok <- SearchExpression.validate(program) do
      opts = opts |> Keyword.drop([:start_ts, :end_ts, :limit])
      query(:traces, tenant, discovery_opts(scope, key, {:expression, program}, opts))
    end
  end

  @impl Pulse.Storage
  def tempo_discovery_json(tenant, scope, key, opts) do
    opts =
      opts
      |> Keyword.drop([:start_ts, :end_ts, :limit])
      |> Keyword.put(:max_scan_rows, min(opts[:max_scan_rows] || 1_000_000, 1_000_000))

    with :ok <- TempoDiscovery.validate(scope, key),
         :ok <- TempoDiscovery.validate_window(opts[:discovery_window]),
         {:ok, predicates} <- TempoDiscovery.filter(scope, key, opts[:discovery_query]),
         do: query(:traces, tenant, discovery_opts(scope, key, predicates, opts))
  end

  defp discovery_opts(scope, key, {:expression, _} = predicates, opts) do
    opts
    |> Keyword.take([:max_scan_segments, :max_scan_bytes, :max_scan_rows, :deadline_ms, :discovery_window])
    |> Keyword.put(:max_scan_rows, min(opts[:max_scan_rows] || 1_000_000, 1_000_000))
    |> Keyword.put(:max_scan_bytes, min(opts[:max_scan_bytes] || 33_554_432, 33_554_432))
    |> Keyword.put(:max_scan_segments, min(opts[:max_scan_segments] || 1024, 1024))
    |> Keyword.put(:tempo_discovery, {scope, key, predicates})
  end

  defp discovery_opts("intrinsic", key, predicates, opts)
       when key in ~w(rootName trace:rootName rootServiceName trace:rootService trace:duration) do
    opts
    |> Keyword.take([:max_scan_segments, :max_scan_bytes, :max_scan_rows, :deadline_ms, :discovery_window])
    |> Keyword.put(:max_scan_bytes, min(opts[:max_scan_bytes] || 33_554_432, 33_554_432))
    |> Keyword.put(:max_scan_segments, min(opts[:max_scan_segments] || 1024, 1024))
    |> Keyword.put(:tempo_root_discovery, {key, predicates})
  end

  defp discovery_opts(scope, key, predicates, opts), do: Keyword.put(opts, :tempo_discovery, {scope, key, predicates})

  @impl Pulse.Storage
  def tempo_expression_search_json(tenant, program, opts), do: tempo_search_json(tenant, {:expression, program}, opts)

  @impl Pulse.Storage
  def tempo_traceql_search_json(tenant, program, opts), do: tempo_search_json(tenant, {:expression, program}, opts)

  @impl Pulse.Storage
  def tempo_typed_search_json(tenant, program, opts), do: tempo_search_json(tenant, {:expression, program}, opts)

  @impl Pulse.Storage
  def tempo_context_search_json(tenant, program, opts), do: tempo_search_json(tenant, {:expression, program}, opts)

  @impl Pulse.Storage
  def tempo_scoped_search_json(tenant, program, opts), do: tempo_search_json(tenant, {:expression, program}, opts)

  @impl Pulse.Storage
  def tempo_search_json(tenant, predicates, opts) do
    opts = opts |> Keyword.drop([:start_ts, :end_ts])
    opts = Keyword.put(opts, :max_scan_rows, min(opts[:max_scan_rows] || 1_000_000, 1_000_000))
    opts = Keyword.put(opts, :max_scan_bytes, min(opts[:max_scan_bytes] || 33_554_432, 33_554_432))
    opts = Keyword.put(opts, :max_scan_segments, min(opts[:max_scan_segments] || 1024, 1024))
    query(:traces, tenant, Keyword.put(opts, :tempo_search, predicates))
  end

  @impl Pulse.Storage
  def search_traces_json(tenant, predicates, opts) do
    opts = Keyword.put(opts, :max_scan_rows, min(opts[:max_scan_rows] || 1_000_000, 1_000_000))
    query(:traces, tenant, Keyword.put(opts, :trace_search, predicates))
  end

  @impl Pulse.Storage
  def metric_discovery_json(tenant, mode, key, selectors, opts) do
    # A single selector can reuse proven manifest pruning. OR selectors must
    # never be narrowed to one branch; they share one conservative source scan.
    matchers =
      case selectors do
        [one] -> one
        _ -> []
      end

    opts =
      opts
      |> Keyword.drop([:limit, :matchers])
      |> Keyword.put(:start_ts, opts[:start_ts] || -9_223_372_036_854_775_808)
      |> Keyword.put(:end_ts, opts[:end_ts] || 9_223_372_036_854_775_807)

    opts =
      Enum.reduce([max_scan_segments: 1024, max_scan_bytes: 134_217_728, max_scan_rows: 1_000_000], opts, fn {name, cap},
                                                                                                             acc ->
        Keyword.put(acc, name, min(Keyword.get(acc, name, cap), cap))
      end)

    query(:metrics, tenant, [metric_discovery: {mode, key, selectors}, matchers: matchers] ++ opts)
  end

  @impl Pulse.Storage
  def log_index_stats(tenant, opts) do
    with :ok <- validate_tenant(tenant),
         :ok <- check_deadline(opts[:deadline_ms]) do
      config = config!()

      timeout =
        if opts[:deadline_ms],
          do: max(0, opts[:deadline_ms] - System.monotonic_time(:millisecond)),
          else: Map.get(config, :retention_timeout_ms, 30_000)

      config
      |> Map.put(:retention_timeout_ms, timeout)
      |> PagedManifest.with_budget(fn -> index_stats(tenant, opts, config) end)
      |> budget_result(opts)
    end
  end

  # Manifest metadata only: every retained segment overlapping the range
  # whose service summary can match, counted whole. No segment is read.
  defp index_stats(tenant, opts, config) do
    with {:ok, entry} <- ManifestOwner.ensure_loaded(tenant, "logs", config, opts) do
      start_ts = retained_start(entry.manifest, opts[:start_ts])

      with {:ok, segments} <- query_segments(entry.manifest, :logs, start_ts, opts[:end_ts], opts, tenant, config) do
        {:ok,
         %{
           segments: length(segments),
           entries: Enum.sum_by(segments, &(&1.row_count || 0)),
           bytes: Enum.sum_by(segments, &(&1.byte_size || 0))
         }}
      end
    end
  end

  @impl Pulse.Storage
  def log_metric_scan(tenant, opts, scan) do
    query(:logs, tenant, Keyword.put(Keyword.delete(opts, :limit), :log_metric, scan))
  end

  # Minutes answered by valid log rollups (`LogRollups.plan/5`) are read
  # from them; every other range is read from log lines into the same bins.
  # Scan budgets charge the rollups' rows, segments and bytes plus what the
  # line reads charge. `start_ts - 1` and `end_ts` fall on minutes.
  @impl Pulse.Storage
  def log_binned_scan(tenant, opts, scan) do
    with :ok <- validate_tenant(tenant),
         :ok <- check_deadline(opts[:deadline_ms]) do
      config = config!()

      timeout =
        if opts[:deadline_ms],
          do: max(0, opts[:deadline_ms] - System.monotonic_time(:millisecond)),
          else: Map.get(config, :retention_timeout_ms, 30_000)

      config
      |> Map.put(:retention_timeout_ms, timeout)
      |> PagedManifest.with_budget(fn -> binned_plan(tenant, opts, config) end)
      |> budget_result(opts)
      |> case do
        {:ok, plan} -> binned_read(tenant, plan, opts, scan, config)
        error -> error
      end
    end
  end

  defp binned_plan(tenant, opts, config) do
    {start, finish} = {opts[:start_ts], opts[:end_ts]}

    with {:ok, entry} <- query_manifest(tenant, "logs", config, opts),
         manifest = entry.manifest,
         # Every segment, whatever its streams: rollup counts cover all lines.
         {:ok, raws} <- query_segments(manifest, :logs, start, finish, [], tenant, config),
         {:ok, rollups} <- query_segments(manifest, :logs, start, finish, [log_rollups: true], tenant, config) do
      {:ok, LogRollups.plan(raws, rollups, start, retained_start(manifest, start), finish)}
    end
  end

  defp binned_read(tenant, plan, opts, scan, config) do
    rollups = Enum.map(plan.rollups, &elem(&1, 0))

    # Rows are charged as read: only the planned minutes' rows of a rollup.
    with :ok <- check_scan_budget(rollups, Keyword.delete(opts, :max_scan_rows)),
         {:ok, consumed} <- read_rollups(plan.rollups, opts, scan, config),
         :ok <- check_rollup_rows(consumed.budget.max_scan_rows, opts) do
      plan.gaps
      |> Enum.reduce_while({:ok, consumed}, &read_gap(tenant, opts, scan, &1, &2))
      |> case do
        {:ok, acc} -> {:ok, {acc.selected, acc.kept}}
        error -> error
      end
    end
  end

  # Lines of minutes no rollup answers, within the budget the rollups left.
  defp read_gap(tenant, opts, scan, {from, to}, {:ok, acc}) do
    gap_opts = opts |> remaining_budget(acc.budget) |> Keyword.merge(start_ts: from, end_ts: to)

    case log_metric_scan(tenant, gap_opts, scan) do
      {:ok, {selected, kept}} -> {:cont, {:ok, %{acc | selected: acc.selected + selected, kept: acc.kept + kept}}}
      error -> {:halt, error}
    end
  end

  defp read_rollups(planned, opts, scan, config) do
    service = Keyword.get(opts, :service)
    matchers = Keyword.get(opts, :matchers, [])
    initial = %{selected: 0, kept: 0, budget: %{max_scan_segments: 0, max_scan_bytes: 0, max_scan_rows: 0}}

    planned
    |> Pulse.Runtime.Task.async_stream(fn {rollup, buckets} -> {ObjectCache.get(config, rollup.key), buckets} end,
      max_concurrency: max(Map.get(config, :query_prefetch, 4), 1),
      ordered: false,
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, initial}, fn
      {:ok, {{:ok, blob}, buckets}}, {:ok, acc} ->
        with :ok <- check_deadline(opts[:deadline_ms]),
             {:ok, rows} <- rollup_rows(NIF.log_metric_scan_rollup(scan, blob, buckets, service, matchers)) do
          budget = %{
            max_scan_segments: acc.budget.max_scan_segments + 1,
            max_scan_bytes: acc.budget.max_scan_bytes + byte_size(blob),
            max_scan_rows: acc.budget.max_scan_rows + rows
          }

          {:cont, {:ok, %{acc | selected: acc.selected + rows, kept: acc.kept + rows, budget: budget}}}
        else
          error -> {:halt, error}
        end

      # A rollup retired after planning: the caller evaluates from lines.
      {:ok, {{:error, :not_found}, _}}, _acc ->
        {:halt, {:error, :native_fallback}}

      {:ok, {{:error, _} = error, _}}, _acc ->
        {:halt, error}
    end)
  end

  defp check_rollup_rows(rows, opts) do
    if exceeds_budget?(rows, opts[:max_scan_rows]),
      do: QueryLimit.exceeded(:max_scan_rows, opts[:max_scan_rows], rows, :visited),
      else: :ok
  end

  defp rollup_rows({:ok, rows}), do: {:ok, rows}
  defp rollup_rows({:error, :pipeline_error}), do: {:error, :pipeline_error}
  defp rollup_rows({:error, :query_resource_limit}), do: {:error, :query_resource_limit}
  defp rollup_rows(_), do: {:error, :native_fallback}

  @impl Pulse.Storage
  def put_metric_metadata(tenant, entries, today), do: MetricMetadataStore.put(config!(), tenant, entries, today)

  @impl Pulse.Storage
  def metric_metadata(tenant), do: MetricMetadataStore.get(config!(), tenant)

  @impl Pulse.Storage
  def trace_metrics_scan(tenant, opts, metrics) do
    {program, opts} = Keyword.pop(opts, :trace_program)
    opts = if is_list(program), do: Keyword.merge(opts, TraceSummary.tempo_filters({:expression, program})), else: opts
    query(:traces, tenant, Keyword.put(Keyword.delete(opts, :limit), :trace_metrics, metrics))
  end

  @impl Pulse.Storage
  def fold_logs(tenant, opts, acc, fun) when is_function(fun, 2) do
    query(:logs, tenant, Keyword.put(Keyword.delete(opts, :limit), :log_fold, {fun, acc}))
  end

  # Live tail follows log segments published within this window; older late
  # arrivals are left to queries. Excess unseen originals fail explicitly:
  # a partial cursor could silently lose unread sources to compaction.
  @follow_window_ns 3_600_000_000_000
  @follow_max_segments 64
  # One poll materializes its records in the follower; bound what it may read
  # and expand, as for queries.
  @follow_budget [max_scan_bytes: 134_217_728, max_scan_rows: 1_000_000, max_decoded_bytes: 33_554_432]

  @impl Pulse.Storage
  def follow_logs(tenant, seen) do
    with :ok <- validate_tenant(tenant) do
      config = config!()
      floor = System.os_time(:nanosecond) - @follow_window_ns

      config
      |> PagedManifest.with_budget(fn -> follow_segments(tenant, floor, seen, config) end)
      |> budget_result([])
    end
  end

  defp follow_segments(tenant, floor, seen, config) do
    case ManifestOwner.ensure_loaded(tenant, "logs", config, require_fresh_manifest: true) do
      {:ok, entry} ->
        with {:ok, segments} <- query_segments(entry.manifest, :logs, floor, nil, [], tenant, config),
             do: read_unseen(segments, seen, config)

      {:error, :signal_authority_missing} ->
        {:ok, [], seen || MapSet.new()}

      {:error, _} = error ->
        error
    end
  end

  # The first poll only records what already exists; history is the query
  # path's job. Keys leaving the window are forgotten with it.
  defp read_unseen(segments, nil, _config), do: {:ok, [], MapSet.new(segments, & &1.key)}

  defp read_unseen(segments, seen, config) do
    current = MapSet.new(segments, & &1.key)

    unseen =
      segments
      |> Enum.reject(&(MapSet.member?(seen, &1.key) or compaction_output?(&1.key)))
      |> Enum.sort_by(&{&1.max_ts || 0, &1.key})
      |> Enum.take(@follow_max_segments + 1)

    if length(unseen) > @follow_max_segments do
      {:error, :tail_lag_limit}
    else
      case scan_segments(:logs, config, unseen, nil, nil, @follow_budget, nil) do
        {:ok, records} ->
          {:ok, records, seen |> MapSet.intersection(current) |> MapSet.union(MapSet.new(unseen, & &1.key))}

        # Retrying the same oversized backlog would rescan it every poll; close
        # like any other lag and let reconnects query history instead.
        {:error, reason} when reason in [:query_scan_limit, :query_decoded_limit] ->
          {:error, :tail_lag_limit}

        {:error, _} = error ->
          error
      end
    end
  end

  # Do not replay replacements. Settle is event-time based, not proof that a
  # follower observed originals; late publication/poll failure can still miss rows.
  defp compaction_output?(key) do
    base = Path.basename(key)
    String.contains?(base, "-compact-") or Segment.key_tier(key) in [:grouped, :final]
  end

  @impl Pulse.Storage
  def log_discovery_json(tenant, mode, key, opts) do
    opts =
      opts
      |> Keyword.delete(:limit)
      |> Keyword.put(:start_ts, opts[:start_ts] || -9_223_372_036_854_775_808)
      |> Keyword.put(:end_ts, opts[:end_ts] || 9_223_372_036_854_775_807)

    opts =
      Enum.reduce([max_scan_segments: 1024, max_scan_bytes: 134_217_728], opts, fn {name, cap}, acc ->
        Keyword.put(acc, name, min(Keyword.get(acc, name, cap), cap))
      end)

    query(:logs, tenant, [log_discovery: {mode, key}] ++ opts)
  end

  @impl true
  def query(signal, tenant, opts) when is_atom(signal) and is_binary(tenant) and is_list(opts) do
    # An already expired deadline is a timeout, not a metadata budget overrun.
    with :ok <- validate_tenant(tenant),
         :ok <- check_deadline(opts[:deadline_ms]) do
      config = config!()

      timeout =
        if opts[:deadline_ms],
          do: max(0, opts[:deadline_ms] - System.monotonic_time(:millisecond)),
          else: Map.get(config, :retention_timeout_ms, 30_000)

      budget = Map.put(config, :retention_timeout_ms, timeout)

      budget
      |> PagedManifest.with_budget(fn -> do_query(signal, tenant, opts, config) end)
      |> budget_result(opts)
    end
  end

  @doc """
  Metric samples for several selectors, each `{matchers, start_ts, end_ts}`,
  from one pass over their candidate segments: every segment any selector
  needs is fetched once and decoded natively for each selector that needs it.
  Scan budgets apply to the distinct segments, bytes and rows read, and
  `:max_records` to all selectors' samples together. Returns the samples in
  selector order and the scan cost actually charged. With
  `metric_fold: {fun, initial}`, each selector's result is instead
  `fun.(batch, acc)` folded over its decoded batches, one segment at a time.
  """
  def query_metric_selectors(tenant, selectors, opts) when is_binary(tenant) and is_list(selectors) do
    with :ok <- validate_tenant(tenant),
         :ok <- check_deadline(opts[:deadline_ms]) do
      config = config!()

      case selectors do
        # Footer-first reads prune by one selector's matchers; keep them for
        # single-selector queries. The cost is charged inside that query.
        [{_, _, _} = selector] when config.metric_footer_pruning_enabled == true ->
          query_footer_selector(tenant, selector, opts)

        _ ->
          query_selectors(tenant, selectors, opts, config)
      end
    end
  end

  defp query_selectors(tenant, selectors, opts, config) do
    timeout =
      if opts[:deadline_ms],
        do: max(0, opts[:deadline_ms] - System.monotonic_time(:millisecond)),
        else: Map.get(config, :retention_timeout_ms, 30_000)

    config
    |> Map.put(:retention_timeout_ms, timeout)
    |> PagedManifest.with_budget(fn -> query_selectors(tenant, selectors, opts, config, :cached) end)
    |> budget_result(opts)
  end

  defp query_footer_selector(tenant, {matchers, start, finish}, opts) do
    with {:ok, samples} <-
           query(:metrics, tenant, Keyword.merge(opts, matchers: matchers, start_ts: start, end_ts: finish)),
         do: {:ok, [fold_selector(samples, opts[:metric_fold])], %{records: length(samples)}}
  end

  defp query_selectors(tenant, selectors, opts, config, source) do
    with :ok <- check_deadline(opts[:deadline_ms]),
         {:ok, manifest} <- selector_manifest(tenant, config, opts, source),
         :ok <- check_deadline(opts[:deadline_ms]),
         {:ok, wanted} <- selector_candidates(manifest, selectors, opts, tenant, config),
         union =
           wanted
           |> Enum.flat_map(&(&1.samples ++ &1.rollups))
           |> Enum.uniq_by(& &1.key)
           |> Enum.sort_by(& &1.max_ts, :desc),
         :ok <- check_scan_budget(:metrics, union, opts) do
      scan_selector_segments(union, wanted, config, opts)
    end
    |> case do
      {:error, reason} when source == :cached and reason == :manifest_page_missing ->
        query_selectors(tenant, selectors, opts, config, :fresh)

      {:error, {:segment_missing, consumed}} when source == :cached ->
        # Cleanup can overtake a cached snapshot or an in-flight query. Restart
        # once against a fresh manifest, keeping what was already charged.
        query_selectors(tenant, selectors, remaining_budget(opts, consumed), config, :fresh)

      {:error, {:segment_missing, _}} ->
        {:error, :not_found}

      result ->
        result
    end
  end

  defp selector_manifest(tenant, config, opts, :cached) do
    with {:ok, entry} <- query_manifest(tenant, "metrics", config, opts), do: {:ok, entry.manifest}
  end

  defp selector_manifest(tenant, config, _opts, :fresh) do
    with {:ok, manifest, _etag} <- Retention.load(tenant, "metrics", config), do: {:ok, manifest}
  end

  # Each selector keeps its own matchers and time bounds, so its decode and
  # manifest pruning are exactly those of a single-selector query.
  defp selector_candidates(manifest, selectors, opts, tenant, config) do
    Enum.reduce_while(selectors, {:ok, []}, fn selector, {:ok, acc} ->
      case selector_wanted(manifest, selector, opts, tenant, config) do
        {:ok, wanted} -> {:cont, {:ok, [wanted | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, wanted} -> {:ok, Enum.reverse(wanted)}
      error -> error
    end
  end

  defp selector_wanted(manifest, selector, opts, tenant, config) do
    [matchers, start, finish | tiers] = Tuple.to_list(selector)
    start = retained_start(manifest, start)
    selector_opts = Keyword.put(opts, :matchers, matchers)

    with {:ok, samples} <- query_segments(manifest, :metrics, start, finish, selector_opts, tenant, config) do
      wanted = %{selector: {matchers, start, finish}, samples: samples, rollups: [], served: nil}

      case tiers do
        [{from, to}] when is_integer(from) and is_integer(to) and to > from and manifest.version != 3 ->
          tier_candidates(wanted, manifest, {from, to}, selector_opts, tenant, config)

        _ ->
          {:ok, wanted}
      end
    end
  end

  # Whole hours in [from, to) answered from hourly rollups: those with a
  # matching rollup object and no matching raw or grouped segment (a write
  # that arrived after finalization). Their finalized segments are not read.
  defp tier_candidates(wanted, manifest, {from, to}, opts, tenant, config) do
    rollup_opts = Keyword.put(opts, :metric_tier, :rollup)

    with {:ok, rollups} <- query_segments(manifest, :metrics, from, to - 1, rollup_opts, tenant, config) do
      blocked =
        for s <- wanted.samples,
            Segment.metric_tier(s) in [:raw, :grouped],
            hour <- raw_hours(s, from, to),
            into: MapSet.new(),
            do: hour

      rollups =
        Enum.filter(rollups, fn r ->
          r.min_ts == r.max_ts and r.min_ts >= from and r.min_ts < to and not MapSet.member?(blocked, r.min_ts)
        end)

      served = MapSet.new(rollups, & &1.min_ts)

      samples =
        Enum.reject(wanted.samples, fn s ->
          Segment.metric_tier(s) == :final and MetricTiers.hour(s.min_ts) == MetricTiers.hour(s.max_ts) and
            MapSet.member?(served, MetricTiers.hour(s.min_ts))
        end)

      {:ok, %{wanted | samples: samples, rollups: rollups, served: served}}
    end
  end

  # Hours in [from, to) a raw segment can hold rows of; unknown bounds block all.
  defp raw_hours(%{min_ts: min, max_ts: max}, from, to) when is_integer(min) and is_integer(max),
    do: Enum.to_list(max(MetricTiers.hour(min), from)..min(MetricTiers.hour(max), to - 1)//MetricTiers.hour_ns())

  defp raw_hours(_segment, from, to), do: Enum.to_list(from..(to - 1)//MetricTiers.hour_ns())

  defp scan_selector_segments(union, wanted, config, opts) do
    # Per segment, the selectors (by position) that need it.
    needs =
      wanted
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {selector, index}, acc ->
        acc = Enum.reduce(selector.samples, acc, &Map.update(&2, &1.key, [index], fn i -> [index | i] end))

        Enum.reduce(
          selector.rollups,
          acc,
          &Map.update(&2, &1.key, [{:rollups, index}], fn i -> [{:rollups, index} | i] end)
        )
      end)

    selectors = List.to_tuple(wanted)
    state = %{bytes: 0, rows: 0, segments: 0, count: 0, batches: %{}, rollups: %{}}
    items = Enum.with_index(union)

    {_initial, concurrency} =
      prefetch_depth(%{signal: :metrics, opts: opts}, union, Map.get(config, :query_prefetch, 1))

    visit = &visit_selector_segment(&1, &2, &3, {needs, selectors, config, opts})

    result =
      if concurrency > 1 and length(items) > 1 do
        limit = opts[:max_scan_bytes]

        items
        |> Stream.map(fn {segment, _} -> segment.key end)
        |> Pulse.Runtime.Task.async_stream(&prefetch(config, limit, &1),
          max_concurrency: concurrency,
          ordered: true,
          timeout: :infinity
        )
        |> Stream.zip(items)
        |> Enum.reduce_while({:ok, state}, fn {{:ok, fetched}, item}, acc -> visit.(item, acc, fetched) end)
      else
        Enum.reduce_while(items, {:ok, state}, &visit.(&1, &2, nil))
      end

    with {:ok, state} <- result do
      samples = for index <- 0..(tuple_size(selectors) - 1)//1, do: tiered_result(state, selectors, index, opts)

      {:ok, samples,
       %{
         max_scan_segments: state.segments,
         max_scan_bytes: state.bytes,
         max_scan_rows: state.rows,
         records: state.count
       }}
    end
  end

  defp tiered_result(state, selectors, index, opts) do
    result = selector_result(state.batches, index, opts[:metric_fold])
    if elem(selectors, index).served, do: {:tiered, result, Map.get(state.rollups, index, [])}, else: result
  end

  defp selector_result(batches, index, nil),
    do: batches |> Map.get(index, []) |> Enum.reverse() |> List.flatten() |> SortOrder.sort(:metrics)

  defp selector_result(batches, index, {_fun, initial}), do: Map.get(batches, index, initial)

  defp add_selector_batch(batches, index, batch, nil), do: Map.update(batches, index, [batch], &[batch | &1])

  defp add_selector_batch(batches, index, batch, {fun, initial}),
    do: Map.put(batches, index, fun.(batch, Map.get(batches, index, initial)))

  defp fold_selector(samples, nil), do: samples
  defp fold_selector(samples, {fun, initial}), do: fun.(samples, initial)

  defp visit_selector_segment({segment, index}, {:ok, state}, fetched, {needs, selectors, config, opts}) do
    ctx = %{opts: opts}

    with :ok <- check_visited_budget(index + 1, state.rows, ctx),
         :ok <- check_read_bytes(state.bytes + (segment.byte_size || 0), opts),
         :ok <- check_deadline(opts[:deadline_ms]),
         {:ok, blob} <- fetched || read_segment(%{config: config, opts: opts, signal: :metrics}, segment.key, state),
         :ok <- check_deadline(opts[:deadline_ms]),
         bytes = state.bytes + byte_size(blob),
         :ok <- check_read_bytes(bytes, opts),
         state = %{state | bytes: bytes, segments: index + 1},
         {:ok, decoded} <- decode_for_selectors(blob, Map.fetch!(needs, segment.key), selectors, opts, state),
         {:ok, state} <- charge_matched_rows(decoded, decoded.count - state.count, opts) do
      {:cont, {:ok, state}}
    else
      {:error, :not_found} ->
        consumed = %{max_scan_bytes: state.bytes, max_scan_segments: index + 1, max_scan_rows: state.rows}
        {:halt, {:error, {:segment_missing, consumed}}}

      {:error, _} = error ->
        {:halt, error}
    end
  end

  # Rows of other series (metrics) or streams (logs) in the same segment are
  # skipped natively by their label columns; the bytes and segments budgets
  # bound reading them. The rows budget counts the rows a selector matched
  # and decoded, for logs also after the pushed-down line filters.
  defp charge_matched_rows(state, matched, opts) do
    rows = state.rows + matched

    if exceeds_budget?(rows, opts[:max_scan_rows]),
      do: QueryLimit.exceeded(:max_scan_rows, opts[:max_scan_rows], rows, :visited),
      else: {:ok, %{state | rows: rows}}
  end

  defp decode_for_selectors(blob, indexes, selectors, opts, state) do
    Enum.reduce_while(indexes, {:ok, state}, fn
      {:rollups, index}, {:ok, state} ->
        %{selector: {matchers, _, _}, served: served} = elem(selectors, index)

        case decode_rollups(blob, served, matchers, opts, state) do
          {:ok, rows} ->
            rollups = Map.update(state.rollups, index, rows, &(rows ++ &1))
            {:cont, {:ok, %{state | rollups: rollups, count: state.count + length(rows)}}}

          {:error, _} = error ->
            {:halt, error}
        end

      index, {:ok, state} ->
        case decode_selector(blob, index, elem(selectors, index).selector, opts, state) do
          {:ok, state} ->
            {:cont, {:ok, state}}

          {:error, _} = error ->
            {:halt, error}
        end
    end)
  end

  defp decode_selector(blob, index, {matchers, start, finish}, opts, state) do
    if opts[:metric_fold] do
      case NIF.metric_segment_reader_new(blob, start, finish, matchers) do
        {:ok, reader} -> fold_metric_chunks(reader, index, opts, state)
        :fallback -> {:error, {:decode_failed, :parquet_decoder_rejected_input}}
      end
    else
      decode_opts = Keyword.put(remaining_budget(opts, %{max_records: state.count}), :matchers, matchers)

      with {:ok, batch} <- decode_segment(:metrics, blob, start, finish, decode_opts) do
        batches = add_selector_batch(state.batches, index, batch, nil)
        {:ok, %{state | batches: batches, count: state.count + length(batch)}}
      end
    end
  end

  # Compacted objects may contain an entire selector's sample budget. Fold
  # bounded native batches so decoded records and transient NIF allocations
  # can be collected between calls, rather than holding a whole object.
  defp fold_metric_chunks(reader, index, opts, state) do
    max = if opts[:max_records], do: max(0, opts[:max_records] - state.count), else: 4096

    with :ok <- check_deadline(opts[:deadline_ms]) do
      case NIF.metric_segment_reader_next(reader, max) do
        {:ok, batch} ->
          batches = add_selector_batch(state.batches, index, batch, opts[:metric_fold])
          fold_metric_chunks(reader, index, opts, %{state | batches: batches, count: state.count + length(batch)})

        :done ->
          {:ok, state}

        {:error, _} = error ->
          error

        :fallback ->
          {:error, {:decode_failed, :parquet_decoder_rejected_input}}
      end
    end
  end

  defp decode_rollups(blob, served, matchers, opts, state) do
    case NIF.decode_metric_rollups(blob, Enum.min(served), Enum.max(served), matchers) do
      {:ok, rows} ->
        rows = Enum.filter(rows, &MapSet.member?(served, elem(&1, 1)))
        max = opts[:max_records]
        if max && state.count + length(rows) > max, do: {:error, :query_sample_limit}, else: {:ok, rows}

      _ ->
        {:error, {:decode_failed, :metric_rollup_rejected}}
    end
  end

  # The metadata budget shares the caller's deadline, so exhausting it after
  # that deadline is a timeout rather than an oversized query.
  defp budget_result({:ok, {:error, :metadata_scan_limit}}, opts), do: metadata_limit(opts)
  defp budget_result({:ok, result}, _opts), do: result
  defp budget_result({:error, :metadata_scan_limit}, opts), do: metadata_limit(opts)
  defp budget_result(error, _opts), do: error

  defp metadata_limit(opts) do
    with :ok <- check_deadline(opts[:deadline_ms]), do: QueryLimit.exceeded(:metadata, nil, nil, :planned)
  end

  @doc """
  Strictly fresh committed log inputs, pruned and bounded like a query.

  Returns candidate segments, the retained event-time floor and the root ETag.
  It never reconstructs a missing manifest from bucket listings or serves stale
  cache data. A snapshot is not a publication journal: inputs may expire between
  snapshots, so consumers must not infer uninterrupted coverage from an ETag.
  """
  def log_snapshot(tenant, opts) do
    deadline = System.monotonic_time(:millisecond) + 10_000
    opts = Keyword.merge(Pulse.QueryRunner.storage_opts(deadline), opts)

    with :ok <- validate_tenant(tenant),
         :ok <- check_deadline(opts[:deadline_ms]) do
      config = Map.put(config!(), :retention_bounded_read, true)
      config = Map.put(config, :retention_timeout_ms, max(0, opts[:deadline_ms] - System.monotonic_time(:millisecond)))

      config
      |> PagedManifest.with_budget(fn -> read_log_snapshot(tenant, config, opts) end)
      |> budget_result(opts)
    end
  end

  defp read_log_snapshot(tenant, config, opts) do
    with {:ok, root, etag} <- Retention.load(tenant, "logs", config),
         start = retained_start(root, opts[:start_ts]),
         {:ok, segments} <- query_segments(root, :logs, start, opts[:end_ts], opts, tenant, config),
         :ok <- check_deadline(opts[:deadline_ms]),
         :ok <- check_scan_budget(segments, opts) do
      {:ok, %{segments: segments, floor_ns: retained_start(root, 0), etag: etag}}
    end
  end

  defp do_query(signal, tenant, opts, config) do
    start_ts = Keyword.get(opts, :start_ts)
    end_ts = Keyword.get(opts, :end_ts)
    limit = Keyword.get(opts, :limit)
    native? = opts[:log_metric] != nil or opts[:trace_metrics] != nil
    opts = put_log_window(signal, opts)

    with :ok <- check_deadline(opts[:deadline_ms]),
         {:ok, entry} <- query_manifest(tenant, signal_string(signal), config, opts),
         :ok <- check_deadline(opts[:deadline_ms]) do
      start_ts = retained_start(entry.manifest, start_ts)

      entry.manifest
      |> scan_manifest(signal, start_ts, end_ts, opts, tenant, config, limit)
      |> case do
        {:ok, records} ->
          {:ok, finalize_records(records, signal, limit)}

        # A native range scan has already absorbed the partial pass; rescanning
        # into it would count rows twice. The caller re-evaluates instead.
        {:error, reason} when native? and reason == :manifest_page_missing ->
          {:error, :native_fallback}

        {:error, {:segment_missing, _}} when native? ->
          {:error, :native_fallback}

        {:error, :manifest_page_missing} ->
          retry_scan(signal, tenant, config, start_ts, end_ts, opts, limit)

        {:error, {:segment_missing, consumed}} ->
          # Cleanup can overtake a cached snapshot or an in-flight query.
          # Restart the whole scan against a fresh manifest, never mix generations.
          retry_scan(signal, tenant, config, start_ts, end_ts, remaining_budget(opts, consumed), limit)

        {:error, _} = err ->
          err
      end
    end
  end

  defp finalize_records(json, _signal, _limit) when is_binary(json), do: json
  defp finalize_records({:log_fold, acc}, _signal, _limit), do: acc
  defp finalize_records(records, signal, limit), do: records |> SortOrder.sort(signal) |> take_limit(limit)

  defp query_manifest(tenant, signal, config, opts) do
    config = if opts[:fresh], do: Map.put(config, :retention_bounded_read, true), else: config
    opts = if opts[:fresh], do: Keyword.put(opts, :require_fresh_manifest, true), else: opts

    case ManifestOwner.ensure_loaded(tenant, signal, config, opts) do
      {:error, :signal_authority_missing} = error ->
        if opts[:fresh] && !opts[:distinguish_missing_authority], do: {:error, :not_found}, else: error

      result ->
        result
    end
  end

  @doc false
  def check_retention(signal, tenant, records, config) do
    name = signal_string(signal)

    # Only the cached version is needed; never copy the manifest per append.
    {version, _etag, _token} = ManifestCache.info(tenant, name)

    cond do
      # Managed roots check eligibility and capacity; enforcing nodes also gate
      # legacy roots behind conversion.
      version == 3 or Retention.enforcing?(config, name) ->
        do_check_retention(signal, tenant, records, config)

      version != nil ->
        :ok

      # A cold scope probes the marker so a managed prefix is checked before
      # the segment upload. The probe is advisory: on error the append
      # proceeds, and the owner's marker check and root CAS still refuse to
      # publish into a managed prefix it has not loaded.
      true ->
        case cached_marker(config, tenant, name) do
          {:ok, true} -> do_check_retention(signal, tenant, records, config)
          _ -> :ok
        end
    end
  end

  @doc false
  def retained_traces(tenant, spans) do
    config = config!()
    {version, _etag, _token} = ManifestCache.info(tenant, "traces")

    managed? =
      version == 3 or Retention.enforcing?(config, "traces") or
        (version == nil and cached_marker(config, tenant, "traces") == {:ok, true})

    if managed? do
      with {:ok, entry} <- ManifestOwner.ensure_loaded(tenant, "traces", config),
           {:ok, root} <- ensure_policy(entry.manifest, tenant, "traces", config) do
        filter_retained_spans(root, spans, config)
      end
    else
      {:ok, spans, 0}
    end
  end

  defp filter_retained_spans(%Manifest{version: 3} = root, spans, config) do
    floor = PagedManifest.floor(root)
    latest = System.system_time(:nanosecond) + Map.get(config, :retention_future_skew_ms, 600_000) * 1_000_000
    {kept, expired} = Enum.split_with(spans, &(&1.timestamp_ns >= floor and &1.timestamp_ns <= latest))
    {:ok, kept, length(expired)}
  end

  defp filter_retained_spans(%Manifest{version: 4} = root, spans, config) do
    floor = JournalManifest.retention_floor(root) || 0
    latest = System.system_time(:nanosecond) + Map.get(config, :retention_future_skew_ms, 600_000) * 1_000_000
    {kept, expired} = Enum.split_with(spans, &(&1.timestamp_ns >= floor and &1.timestamp_ns <= latest))
    {:ok, kept, length(expired)}
  end

  defp filter_retained_spans(_root, spans, _config), do: {:ok, spans, 0}

  defp cached_marker(config, tenant, signal) do
    ref = %{"k" => "marker-cache:" <> PagedManifest.scope(tenant, signal), "b" => 1}
    now = System.monotonic_time(:millisecond)

    case MetadataCache.get(ref) do
      {:ok, {checked, exists}} when now - checked < 1000 ->
        {:ok, exists}

      _ ->
        case PagedManifest.managed?(config, tenant, signal) do
          {:ok, exists} = result ->
            MetadataCache.put(ref, {now, exists})
            result

          error ->
            error
        end
    end
  end

  defp do_check_retention(signal, tenant, records, config) do
    name = signal_string(signal)

    with {:ok, entry} <- ManifestOwner.ensure_loaded(tenant, name, config),
         {:ok, root} <- ensure_policy(entry.manifest, tenant, name, config),
         do: check_admission(root, records, config)
  end

  defp check_admission(%Manifest{version: 3} = root, records, config) do
    timestamps = Enum.map(records, &(&1.timestamp_ns || 0))
    segment = Segment.build("", Enum.min(timestamps), Enum.max(timestamps), length(records))

    with :ok <- PagedManifest.eligible(root, segment, System.system_time(:nanosecond), config),
         {:ok, :ok} <- PagedManifest.check_capacity(root, segment, config),
         do: :ok
  end

  # Format-4 retention rejects what the floor already hides, and records too
  # far in the future, as format 3 does. Publication does not re-check the
  # floor: anything published below it is hidden and expires on the next pass.
  defp check_admission(%Manifest{version: 4} = root, records, config) do
    timestamps = Enum.map(records, &(&1.timestamp_ns || 0))
    latest = System.system_time(:nanosecond) + Map.get(config, :retention_future_skew_ms, 600_000) * 1_000_000

    cond do
      timestamps == [] -> :ok
      Enum.min(timestamps) < (JournalManifest.retention_floor(root) || 0) -> {:error, :retention_expired}
      Enum.max(timestamps) > latest -> {:error, :timestamp_too_new}
      true -> :ok
    end
  end

  defp check_admission(_root, _records, _config), do: :ok

  defp ensure_policy(%Manifest{version: 3} = root, _tenant, _signal, _config), do: {:ok, root}

  defp ensure_policy(root, tenant, signal, config) do
    cond do
      not Retention.bucketed?(config, signal) -> {:ok, root}
      Manifest.empty?(root) -> convert_empty(tenant, signal, config)
      true -> {:error, :retention_migration_required}
    end
  end

  defp convert_empty(tenant, signal, config) do
    with {:ok, _} <- Retention.advance(tenant, signal, Map.put(config, :retention_empty_conversion_only, true)),
         {:ok, managed, _} <- Retention.load(tenant, signal, config),
         do: {:ok, managed}
  end

  defp retained_start(%Manifest{version: 3} = root, nil), do: PagedManifest.floor(root)
  defp retained_start(%Manifest{version: 3} = root, start), do: max(start, PagedManifest.floor(root))

  defp retained_start(%Manifest{version: 4} = root, start) do
    case {JournalManifest.retention_floor(root), start} do
      {nil, start} -> start
      {floor, nil} -> floor
      {floor, start} -> max(start, floor)
    end
  end

  defp retained_start(_root, start), do: start

  # A limited log query reads segments in its direction and stops once no
  # further segment can improve its `limit` entries: newest `max_ts` first
  # for backward folds and limited raw queries, oldest `min_ts` first for
  # forward folds. Only the first `max_scan_segments + 1` candidates in that
  # order are planned: a scan that needs the last one exceeds the segment
  # budget anyway, and every unplanned candidate orders after it.
  defp put_log_window(:logs, opts) do
    # Folds, native scans and discovery drop `:limit`; only a fold with a
    # stop condition or a limited raw query can end early.
    order =
      cond do
        opts[:log_fold_stop] -> Keyword.get(opts, :log_fold_order, :backward)
        is_integer(opts[:limit]) and opts[:limit] > 0 -> :backward
        true -> nil
      end

    cond do
      is_nil(order) -> opts
      is_integer(opts[:max_scan_segments]) -> Keyword.put(opts, :log_window, {order, opts[:max_scan_segments] + 1})
      true -> Keyword.put(opts, :log_window, {order, nil})
    end
  end

  defp put_log_window(_signal, opts), do: opts

  # A limited span query visits candidates newest `max_ts` first and stops
  # once its kth span starts after the next candidate's `max_ts`, often
  # within the first few segments. Format-4 manifests plan it a window at a
  # time: the newest @trace_window candidates, reading only the leaves that
  # can hold them, then four times as many whenever the scan needs more
  # (pages already read come from the metadata cache).
  @trace_window 64
  defp put_trace_window(:traces, %Manifest{version: 4} = root, start_ts, end_ts, opts, tenant, config) do
    if limited_span_query?(opts) and is_nil(opts[:trace_metrics]) and is_nil(opts[:assemble_trace]) do
      plan = fn n ->
        query_segments(root, :traces, start_ts, end_ts, Keyword.put(opts, :trace_window, n), tenant, config)
      end

      opts |> Keyword.put(:trace_window, @trace_window) |> Keyword.put(:trace_plan, plan)
    else
      opts
    end
  end

  defp put_trace_window(_signal, _root, _start_ts, _end_ts, opts, _tenant, _config), do: opts

  defp query_segments(manifest, :logs, start_ts, end_ts, opts, tenant, config) do
    opts = Segment.compile_log_matchers(opts)

    with {:ok, segments} <- manifest_segments(manifest, :logs, start_ts, end_ts, opts, tenant, config),
         do: {:ok, window_segments(segments, opts[:log_window])}
  end

  defp query_segments(manifest, signal, start_ts, end_ts, opts, tenant, config),
    do: manifest_segments(manifest, signal, start_ts, end_ts, opts, tenant, config)

  defp window_segments(segments, nil), do: segments
  defp window_segments(segments, {:backward, nil}), do: segments
  defp window_segments(segments, {:backward, n}), do: Enum.take(segments, n)

  # Unknown bounds sort first, so an early stop never skips them.
  defp window_segments(segments, {:forward, n}) do
    segments = Enum.sort_by(segments, &{&1.min_ts != nil, &1.min_ts, &1.key})
    if n, do: Enum.take(segments, n), else: segments
  end

  defp manifest_segments(%Manifest{version: 3} = root, signal, start_ts, end_ts, opts, tenant, config) do
    opts = opts |> Keyword.put(:start_ts, start_ts) |> Keyword.put(:end_ts, end_ts) |> metrics_filter(signal)
    PagedManifest.query(root, tenant, signal_string(signal), opts, config)
  end

  defp manifest_segments(%Manifest{version: 4} = root, signal, start_ts, end_ts, opts, tenant, config) do
    opts = opts |> Keyword.put(:start_ts, start_ts) |> Keyword.put(:end_ts, end_ts) |> metrics_filter(signal)
    JournalManifest.query(root, tenant, signal_string(signal), opts, config)
  end

  defp manifest_segments(manifest, signal, start_ts, end_ts, opts, _tenant, _config) do
    segments = Manifest.prune_by_time(manifest, start_ts, end_ts)
    opts = metrics_filter(opts, signal)

    filtered =
      case signal do
        :metrics -> Enum.filter(segments, &Segment.matches_metrics?(&1, opts[:metrics_filter]))
        :logs -> Enum.filter(segments, &Segment.matches_log_service?(&1, opts))
        :traces -> Enum.filter(segments, &TraceSummary.matches?(&1.trace_summary, opts))
      end

    {:ok, filtered}
  end

  # Compile matcher pruning once per query, not once per manifest entry.
  defp metrics_filter(opts, :metrics),
    do:
      Keyword.put(
        opts,
        :metrics_filter,
        Segment.metrics_filter(
          Keyword.get(opts, :matchers, []),
          Keyword.get(opts, :metric_tier, :samples),
          opts[:metric_catalog_coverage]
        )
      )

  defp metrics_filter(opts, _signal), do: opts

  defp remaining_budget(opts, consumed) do
    Enum.reduce(consumed, opts, fn {key, used}, acc ->
      case Keyword.get(acc, key) do
        nil -> acc
        maximum -> Keyword.put(acc, key, maximum - used)
      end
    end)
  end

  defp retry_scan(signal, tenant, config, start_ts, end_ts, opts, limit) do
    with :ok <- check_deadline(opts[:deadline_ms]),
         {:ok, manifest, _etag} <- Retention.load(tenant, signal_string(signal), config),
         start_ts = retained_start(manifest, start_ts),
         {:ok, records} <- scan_manifest(manifest, signal, start_ts, end_ts, opts, tenant, config, limit) do
      {:ok, finalize_records(records, signal, limit)}
    else
      {:error, {:segment_missing, _}} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp scan_manifest(manifest, signal, start_ts, end_ts, opts, tenant, config, limit) do
    cond do
      signal == :traces and opts[:tempo_search] != nil ->
        tempo_search(manifest, start_ts, opts, tenant, config)

      signal == :metrics and opts[:metric_discovery] != nil ->
        discover_metrics(manifest, start_ts, end_ts, opts, tenant, config)

      true ->
        scan_manifest_segments(manifest, signal, start_ts, end_ts, opts, tenant, config, limit)
    end
  end

  defp scan_manifest_segments(manifest, signal, start_ts, end_ts, opts, tenant, config, limit) do
    opts = put_trace_window(signal, manifest, start_ts, end_ts, opts, tenant, config)

    with {:ok, segments} <- query_segments(manifest, signal, start_ts, end_ts, opts, tenant, config),
         :ok <- check_deadline(opts[:deadline_ms]),
         :ok <- check_scan_budget(signal, segments, opts),
         do: scan_segments(signal, config, segments, start_ts, end_ts, opts, limit)
  end

  # Discovery reads the hourly series catalogs in the window first, then only
  # the sample segments none of them covers (`MetricCatalog`). Catalogs list
  # a series for its whole hour, so an edge hour with a catalog widens the
  # window to the full hour, for its uncovered segments as well.
  defp discover_metrics(manifest, start_ts, end_ts, opts, tenant, config) do
    catalog_opts = opts |> Keyword.put(:metric_tier, :catalog) |> Keyword.put(:matchers, [])

    with {:ok, catalogs} <- query_segments(manifest, :metrics, start_ts, end_ts, catalog_opts, tenant, config) do
      case Enum.filter(catalogs, &MetricCatalog.catalog_hour/1) do
        [] -> scan_manifest_segments(manifest, :metrics, start_ts, end_ts, opts, tenant, config, nil)
        catalogs -> discover_with_catalogs(manifest, catalogs, start_ts, end_ts, opts, tenant, config)
      end
    end
  end

  defp discover_with_catalogs(manifest, catalogs, start_ts, end_ts, opts, tenant, config) do
    # Each catalogued hour with the lineages of its catalogs.
    hours =
      catalogs
      |> Enum.group_by(&MetricCatalog.catalog_hour/1, &MetricCatalog.lineage(&1.key))
      |> Map.new(fn {hour, lineages} -> {hour, MapSet.new(lineages)} end)

    start_ts = if Map.has_key?(hours, MetricTiers.hour(start_ts)), do: MetricTiers.hour(start_ts), else: start_ts

    end_ts =
      if Map.has_key?(hours, MetricTiers.hour(end_ts)),
        do: MetricTiers.hour(end_ts) + MetricTiers.hour_ns() - 1,
        else: end_ts

    with :ok <- NIF.ensure_metric_catalog_api!(),
         :ok <- check_deadline(opts[:deadline_ms]),
         {:ok, native} <- start_native_query(:metrics, start_ts, end_ts, opts) do
      catalogs = Enum.sort_by(catalogs, & &1.key)
      ctx = scan_ctx(:metrics, config, catalogs, start_ts, end_ts, opts, nil, native)
      state = %{batches: [], count: 0, top: [], bytes: 0, decoded_bytes: 0, rows: 0, fold: nil, covers: %{}}

      catalogs
      |> scan_sources(Map.put(ctx, :catalogs?, true), state)
      |> scan_uncovered(manifest, hours, ctx, tenant)
      |> finish_scan(native, nil, :metric_discovery)
    end
  end

  # Continue the same native scan and budgets over every sample segment that
  # some catalog hour in the window does not cover. Apply coverage while
  # planning pages, before their candidate ceiling: covered samples are not
  # sources this query will read, and must not exhaust its segment budget.
  defp scan_uncovered({:ok, state}, manifest, hours, ctx, tenant) do
    visited = length(ctx.segments)
    consumed = %{max_scan_segments: visited, max_scan_bytes: state.bytes, max_scan_rows: state.rows}
    coverage = {hours, state.covers, ctx.start_ts, ctx.end_ts}
    opts = ctx.opts |> remaining_budget(consumed) |> Keyword.put(:metric_catalog_coverage, coverage)

    with {:ok, uncovered} <-
           query_segments(manifest, :metrics, ctx.start_ts, ctx.end_ts, opts, tenant, ctx.config),
         :ok <- check_scan_budget(:metrics, uncovered, opts) do
      ctx = %{ctx | segments: uncovered, indexed: List.to_tuple(uncovered), offset: visited}
      scan_sources(uncovered, ctx, state)
    end
  end

  defp scan_uncovered(error, _manifest, _hours, _ctx, _tenant), do: error

  # Limited traces may stop at a strict timestamp boundary. Actual visited
  # objects are still charged for bytes/rows/segments in scan_segments/7.
  defp check_scan_budget(:traces, segments, opts) do
    if limited_span_query?(opts), do: :ok, else: check_scan_budget(segments, opts)
  end

  # Limited log queries charge only the segments they actually visit. Log
  # reads charge max_scan_rows with the rows their stream selector and line
  # filters select, known only once decoded: compacted segments mix every
  # stream of an hour, and the native reader skips other streams' rows by
  # their columns. Discovery keeps every stored row it reads.
  defp check_scan_budget(:logs, segments, opts) do
    cond do
      opts[:log_window] -> :ok
      opts[:log_discovery] -> check_scan_budget(segments, opts)
      true -> check_scan_budget(segments, Keyword.delete(opts, :max_scan_rows))
    end
  end

  # Metric sample reads charge max_scan_rows with the rows their selectors
  # match, known only once decoded (see charge_matched_rows/3). Discovery
  # keeps every stored row it reads.
  defp check_scan_budget(:metrics, segments, opts) do
    result =
      if opts[:metric_discovery],
        do: check_scan_budget(segments, opts),
        else: check_scan_budget(segments, Keyword.delete(opts, :max_scan_rows))

    # Distinguish ungrouped backlog from expensive grouped reads without
    # exposing source keys or fetching any payload just to diagnose a limit.
    with {:error, :query_scan_limit} <- result,
         %{limit: :max_scan_bytes} = detail <- QueryLimit.peek() do
      tiers =
        Enum.reduce(segments, %{}, fn segment, acc ->
          tier = Segment.metric_tier(segment)
          {count, bytes} = Map.get(acc, tier, {0, 0})
          Map.put(acc, tier, {count + 1, bytes + (segment.byte_size || 0)})
        end)

      QueryLimit.put(Map.put(detail, :metric_tiers, tiers))
    end

    result
  end

  defp limited_span_query?(opts),
    do:
      is_integer(opts[:limit]) and opts[:limit] in 1..5000 and
        Enum.all?([:trace_search, :tempo_search, :tempo_discovery, :tempo_root_discovery], &is_nil(opts[&1]))

  defp check_scan_budget(segments, opts) do
    bytes = Enum.sum(Enum.map(segments, &(&1.byte_size || 0)))
    rows = Enum.sum(Enum.map(segments, &(&1.row_count || 0)))

    cond do
      exceeds_budget?(length(segments), opts[:max_scan_segments]) ->
        QueryLimit.exceeded(:max_scan_segments, opts[:max_scan_segments], length(segments), :candidates)

      exceeds_budget?(bytes, opts[:max_scan_bytes]) ->
        QueryLimit.exceeded(:max_scan_bytes, opts[:max_scan_bytes], bytes, :candidates)

      exceeds_budget?(rows, opts[:max_scan_rows]) ->
        QueryLimit.exceeded(:max_scan_rows, opts[:max_scan_rows], rows, :candidates)

      true ->
        :ok
    end
  end

  defp exceeds_budget?(_, nil), do: false
  defp exceeds_budget?(value, max), do: value > max
  defp check_deadline(nil), do: :ok

  defp check_deadline(deadline) do
    if System.monotonic_time(:millisecond) >= deadline, do: {:error, :query_timeout}, else: :ok
  end

  defp summarize_segment(:metrics, segment, records, _proof), do: Segment.summarize_metrics(segment, records)
  defp summarize_segment(:logs, segment, records, _proof), do: Segment.summarize_logs(segment, records)

  defp summarize_segment(:traces, segment, records, proof) do
    %{segment | trace_summary: TraceSummary.build(records, proof)}
  end

  # -- helpers -----------------------------------------------------------------

  defp signal_string(:logs), do: "logs"
  defp signal_string(:metrics), do: "metrics"
  defp signal_string(:traces), do: "traces"

  # The content fingerprint only matters when an idempotency key makes the
  # object key deterministic. Without one the key is random anyway, so
  # skip hashing the batch.
  defp fingerprint(signal, records, idempotency_key)
       when is_binary(idempotency_key) and byte_size(idempotency_key) > 0 do
    {:ok, hash} = caller_content_hash(signal, records)
    hash
  end

  defp fingerprint(_signal, _records, _idempotency_key), do: rand_hex()

  # Encode for fresh/random object keys only: metric output may add footer
  # postings. Deterministic keyed writers must use append/4, which preserves
  # legacy v2 bytes. Do not PUT this helper's output under an existing key.
  @doc false
  @spec encode_segment(Pulse.Storage.signal(), [Pulse.Storage.signal_record()]) ::
          {:ok, binary(), integer(), integer()} | {:error, term()}
  def encode_segment(:logs, records) do
    with {:ok, normalized} <- normalize_logs(records) do
      case NIF.encode_log_segment_parquet_v2(normalized) do
        {:ok, payload, min_ts, max_ts, _count} ->
          {:ok, payload, min_ts, max_ts}

        {:error, _} = error ->
          error

        :fallback ->
          {:error, {:encode_failed, :parquet_encoder_rejected_input}}
      end
    end
  end

  def encode_segment(:traces, records) do
    with {:ok, payload, min_ts, max_ts, _proof} <- encode_for_append(:traces, records),
         do: {:ok, payload, min_ts, max_ts}
  end

  def encode_segment(:metrics, records), do: encode_metrics(records, true)

  defp encode_metrics(records, indexed?) do
    result =
      if indexed?,
        do: NIF.encode_metric_segment_parquet_indexed_v1(records),
        else: NIF.encode_metric_segment_parquet_v2(records)

    case result do
      {:ok, payload, min_ts, max_ts, _count} ->
        {:ok, payload, min_ts, max_ts}

      {:error, _} = error ->
        error

      :fallback ->
        {:error, {:encode_failed, :parquet_encoder_rejected_input}}
    end
  end

  defp encode_for_append(signal, records, keyed? \\ false)

  defp encode_for_append(:traces, records, _keyed?) do
    case NIF.encode_trace_segment_parquet_v2(Enum.map(records, &Span.to_map/1)) do
      {:ok, payload, min_ts, max_ts, _count, proof} -> {:ok, payload, min_ts, max_ts, proof}
      {:error, _} = error -> error
      :fallback -> {:error, {:encode_failed, :parquet_encoder_rejected_input}}
    end
  end

  # Keep keyed bytes compatible with pre-index objects. Conditional creation
  # now prevents overwrites, but a different footer would become a permanent
  # exact-byte conflict. Fresh compaction keys can safely acquire postings.
  defp encode_for_append(:metrics, records, true) do
    with {:ok, payload, min_ts, max_ts} <- encode_metrics(records, false),
         do: {:ok, payload, min_ts, max_ts, nil}
  end

  defp encode_for_append(signal, records, _keyed?) do
    with {:ok, payload, min_ts, max_ts} <- encode_segment(signal, records),
         do: {:ok, payload, min_ts, max_ts, nil}
  end

  @doc false
  def validate_tenant(tenant) do
    if tenant not in [".", ".."] and Regex.match?(@tenant_regex, tenant) do
      :ok
    else
      {:error, {:invalid_tenant, tenant}}
    end
  end

  defp normalize_logs(records) do
    Enum.reduce_while(records, {:ok, []}, fn
      %Log{} = record, {:ok, acc} ->
        with {:ok, attrs} <- sanitize_map(record.attributes || %{}),
             {:ok, resource} <- sanitize_map(record.resource || %{}) do
          normalized = %{record | attributes: attrs, resource: resource}
          {:cont, {:ok, [normalized | acc]}}
        else
          err -> {:halt, err}
        end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      err -> err
    end
  end

  # Coerce every attribute/resource map key to a string, recursively.
  @doc false
  @spec sanitize_map(map()) :: {:ok, map()} | {:error, {:attribute_key_collision, [String.t()]}}
  def sanitize_map(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, &insert_sanitized/2)
  end

  defp insert_sanitized({k, v}, {:ok, acc}) do
    string_key = stringify_key(k)

    if Map.has_key?(acc, string_key) do
      {:halt, {:error, {:attribute_key_collision, [string_key]}}}
    else
      put_sanitized(acc, string_key, v)
    end
  end

  defp put_sanitized(acc, key, value) do
    case sanitize_value(value) do
      {:ok, sanitized} -> {:cont, {:ok, Map.put(acc, key, sanitized)}}
      err -> {:halt, err}
    end
  end

  defp sanitize_value(v) when is_map(v), do: sanitize_map(v)
  defp sanitize_value(v) when is_list(v), do: sanitize_list(v)
  defp sanitize_value(v), do: {:ok, v}

  defp sanitize_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, &prepend_sanitized/2)
    |> case do
      {:ok, sanitized} -> {:ok, Enum.reverse(sanitized)}
      err -> err
    end
  end

  defp prepend_sanitized(value, {:ok, acc}) do
    case sanitize_value(value) do
      {:ok, sanitized} -> {:cont, {:ok, [sanitized | acc]}}
      err -> {:halt, err}
    end
  end

  defp stringify_key(k) when is_binary(k), do: k
  defp stringify_key(k) when is_atom(k), do: Atom.to_string(k)
  defp stringify_key(k) when is_integer(k), do: Integer.to_string(k)
  defp stringify_key(k), do: inspect(k)

  # Scan segments newest-first, decode each, keep only records inside the
  # requested filter, and short-circuit once we know the running accumulator
  # already dominates every remaining segment. The safety condition:
  #
  #   have >= limit records AND
  #   kth-largest.timestamp_ns > next_segment.max_ts
  #
  # means no future segment can produce a record higher than what we have,
  # so it is safe to stop. Segments whose max_ts is unknown never satisfy
  # the condition, so they always get fetched — that is the price of not
  # knowing their bounds.
  #
  # `opts` is passed through to the per-signal decoder so each signal's
  # pushdowns (service + matchers + line_filters for logs, matchers for
  # metrics) stay typed at the signal boundary rather than fanning into
  # positional args here.
  defp scan_segments(signal, config, segments, start_ts, end_ts, opts, limit) do
    with {:ok, native} <- start_native_query(signal, start_ts, end_ts, opts) do
      scan_ctx(signal, config, segments, start_ts, end_ts, opts, limit, native)
      |> run_scan()
      |> finish_scan(native, limit, scan_mode(opts))
    end
  end

  defp scan_ctx(signal, config, segments, start_ts, end_ts, opts, limit, native) do
    %{
      signal: signal,
      config: config,
      segments: segments,
      # Early-stop checks look at the next segment after every visit; index a
      # tuple instead of walking the list, which is quadratic in the scan.
      indexed: List.to_tuple(segments),
      # Candidates visited in earlier windows, for the visited budget.
      offset: 0,
      start_ts: start_ts,
      end_ts: end_ts,
      opts: opts,
      limit: limit,
      search?:
        not is_nil(opts[:trace_search]) or not is_nil(opts[:tempo_search]) or not is_nil(opts[:tempo_discovery]) or
          not is_nil(opts[:tempo_root_discovery]),
      metric_discovery?: not is_nil(opts[:metric_discovery]),
      log_discovery?: not is_nil(opts[:log_discovery]),
      log_fold: opts[:log_fold],
      log_metric: opts[:log_metric],
      trace_metrics: opts[:trace_metrics],
      discovery?: not is_nil(opts[:tempo_discovery]),
      tempo?: not is_nil(opts[:tempo_search]) or not is_nil(opts[:tempo_root_discovery]),
      # Tempo search rounds: blobs read by earlier rounds, and whether the
      # visited source is an older candidate outside this round's window.
      memo: nil,
      unplanned?: false,
      native: native
    }
  end

  # Decode a segment a bounded chunk at a time: a compacted segment can hold
  # 100k rows, more than one query process may hold as terms at once.
  @fold_chunk_records 4096
  defp fold_segment(blob, ctx, fun, acc, count) do
    service = Keyword.get(ctx.opts, :service)
    matchers = Keyword.get(ctx.opts, :matchers, [])
    line_filters = Keyword.get(ctx.opts, :line_filters, [])
    :ok = validate_decode_args(blob, ctx.start_ts, ctx.end_ts, service, matchers, line_filters)

    case NIF.log_segment_reader_new(blob, ctx.start_ts, ctx.end_ts, service, matchers, line_filters) do
      {:ok, reader} -> fold_chunks(reader, fun, acc, count)
      :fallback -> {:error, {:decode_failed, :parquet_decoder_rejected_input}}
    end
  end

  defp fold_chunks(reader, fun, acc, count) do
    case NIF.log_segment_reader_next(reader, @fold_chunk_records) do
      {:ok, records} -> fold_chunks(reader, fun, fun.(records, acc), count + length(records))
      :done -> {:ok, acc, count}
      :fallback -> {:error, {:decode_failed, :parquet_decoder_rejected_input}}
    end
  end

  defp fold_acc({_fun, acc}), do: acc
  defp fold_acc(nil), do: nil

  # Segments are visited in the fold's order (`:log_fold_order`): newest
  # `max_ts` first by default, oldest `min_ts` first forward. A fold may stop
  # once the next segment cannot contribute, judged from its `{min_ts, max_ts}`
  # bounds (`nil` when no segment remains).
  defp fold_done?(%{opts: opts} = ctx, acc, index) do
    case opts[:log_fold_stop] do
      nil -> false
      stop -> stop.(acc, ctx |> next_segment(index) |> then(&(&1 && {&1.min_ts, &1.max_ts})))
    end
  end

  defp next_segment(%{indexed: indexed}, index) when index + 1 < tuple_size(indexed), do: elem(indexed, index + 1)
  defp next_segment(_ctx, _index), do: nil

  defp run_scan(ctx) do
    fold =
      cond do
        ctx.opts[:log_metric] -> {0, 0}
        ctx.opts[:trace_metrics] -> 0
        true -> fold_acc(ctx.opts[:log_fold])
      end

    state = %{batches: [], count: 0, top: [], bytes: 0, decoded_bytes: 0, rows: 0, fold: fold}
    with {:ok, state} <- scan_sources(ctx.segments, ctx, state), do: next_window(ctx, state)
  end

  # A full window may be followed by older candidates: plan four times as
  # many and visit those after it, unless the kth span already starts after
  # the newest of them. Candidates keep their `{-max_ts, key}` plan order, so
  # a larger window of the same root begins with the smaller one.
  defp next_window(%{opts: opts, offset: offset, segments: segments} = ctx, state) do
    n = opts[:trace_window]
    kth = window_kth(state, ctx)

    # Every later candidate ends no later than this window's last one.
    if is_integer(n) and offset + length(segments) == n and not older_than?(kth, List.last(segments)) do
      with {:ok, planned} <- opts[:trace_plan].(4 * n),
           do: scan_window(Enum.drop(planned, n), kth, ctx, state)
    else
      {:ok, state}
    end
  end

  defp scan_window([], _kth, _ctx, state), do: {:ok, state}

  defp scan_window([next | _] = rest, kth, %{opts: opts} = ctx, state) do
    if older_than?(kth, next) do
      {:ok, state}
    else
      n = opts[:trace_window]
      opts = Keyword.put(opts, :trace_window, 4 * n)
      ctx = %{ctx | segments: rest, indexed: List.to_tuple(rest), offset: n, opts: opts}
      with {:ok, state} <- scan_sources(rest, ctx, state), do: next_window(ctx, state)
    end
  end

  defp older_than?(kth, %{max_ts: max_ts}) when is_integer(kth) and is_integer(max_ts), do: kth > max_ts
  defp older_than?(_kth, _segment), do: false

  # The native path reports its kth start; the record path keeps the top
  # `limit` start times.
  defp window_kth(%{kth: kth}, _ctx), do: kth

  defp window_kth(%{count: count, top: top}, %{limit: limit}) when is_integer(limit) and count >= limit,
    do: Enum.at(top, limit - 1)

  defp window_kth(_state, _ctx), do: nil

  # Object GET latency dominates scans on real object stores. With
  # `query_prefetch` above 1, the next segments are fetched while earlier ones
  # are processed, in order; a halted scan stops outstanding fetches. Budgets
  # are still charged as segments are visited, so up to depth - 1 extra reads
  # can happen past an exhausted budget or an early stop. `query_prefetch: 1`
  # reads strictly one segment at a time.
  defp scan_sources(sources, ctx, state) do
    items = Enum.with_index(sources)
    {initial, maximum} = prefetch_depth(ctx, sources, Map.get(ctx.config, :query_prefetch, 1))

    if maximum > 1 and length(items) > 1 and prefetchable?(ctx) do
      prefetched_scan(items, :queue.new(), 0, {initial, maximum}, fetcher(ctx), ctx, {:ok, state})
    else
      Enum.reduce_while(items, {:ok, state}, &visit_segment(&1, &2, ctx))
    end
  end

  # Fetches run `depth` segments ahead of the one being visited. A scan that
  # can stop early starts at `initial` and reads as far ahead as it has
  # already visited, up to `maximum`: one that keeps going becomes as
  # latency-tolerant as a full scan, while one that stops after a few segments
  # wastes few reads.
  defp prefetched_scan(items, queue, visited, {initial, maximum} = depth, fetch, ctx, acc) do
    {items, queue} = fill_prefetch(items, queue, min(maximum, max(initial, visited)), fetch)

    case :queue.out(queue) do
      {:empty, _} ->
        acc

      {{:value, {task, item}}, queue} ->
        item
        |> visit_segment(acc, ctx, await_fetch(task))
        |> next_prefetched(items, queue, visited + 1, depth, fetch, ctx)
    end
  end

  defp await_fetch({:fetched, result}), do: result
  defp await_fetch(task), do: Pulse.Runtime.Task.await(task, :infinity)

  defp next_prefetched({:cont, acc}, items, queue, visited, depth, fetch, ctx),
    do: prefetched_scan(items, queue, visited, depth, fetch, ctx, acc)

  defp next_prefetched({:halt, acc}, _items, queue, _visited, _depth, _fetch, _ctx) do
    queue
    |> :queue.to_list()
    |> Enum.each(fn
      {{:fetched, _}, _} -> :ok
      {task, _} -> Pulse.Runtime.Task.shutdown(task, :brutal_kill)
    end)

    acc
  end

  # Answers a blob an earlier round already read, or the fetch to run. Each
  # task copies its closure: capture only the config, the byte limit and one
  # key, never `ctx` with its candidate segment list and options.
  defp fetcher(ctx) do
    config = ctx.config
    limit = ctx.opts[:max_scan_bytes]
    memo = ctx.memo || %{}

    fn
      key when is_map_key(memo, key) -> {:fetched, {:ok, Map.fetch!(memo, key)}}
      key -> fn -> prefetch(config, limit, key) end
    end
  end

  defp fill_prefetch([{segment, _} = item | rest] = items, queue, depth, fetch) do
    if :queue.len(queue) < depth do
      pending =
        case fetch.(segment.key) do
          {:fetched, _} = fetched -> fetched
          run -> Pulse.Runtime.Task.async(run)
        end

      fill_prefetch(rest, :queue.in({pending, item}, queue), depth, fetch)
    else
      {items, queue}
    end
  end

  defp fill_prefetch([], queue, _depth, _fetch), do: {[], queue}

  # Small uncompacted segments make scans latency-bound: one GET per push or
  # remote-write batch. Scans read up to @max_prefetch segments ahead while
  # the candidates' sizes keep at most @prefetch_bytes in flight. Metric scans
  # and unlimited log scans start there; log and trace scans that can stop
  # early start at the configured depth and grow towards it.
  @prefetch_bytes 16 * 1024 * 1024
  @max_prefetch 32
  defp prefetch_depth(%{signal: signal, opts: opts} = ctx, sources, configured)
       when configured > 1 and signal in [:logs, :metrics, :traces] do
    offset = Map.get(ctx, :offset, 0)
    largest = sources |> Enum.map(&(&1.byte_size || @prefetch_bytes)) |> Enum.max(fn -> @prefetch_bytes end)
    maximum = max(configured, min(@max_prefetch, div(@prefetch_bytes, max(largest, 1))))
    # A later trace window follows a whole window the scan could not stop in.
    # TraceQL metrics read every candidate, so they prefetch at full depth.
    stops_early? =
      (signal == :traces and offset == 0 and is_nil(opts[:trace_metrics])) or
        (signal == :logs and opts[:log_window] != nil)

    if stops_early?, do: {configured, maximum}, else: {maximum, maximum}
  end

  defp prefetch_depth(_ctx, _sources, configured), do: {configured, configured}

  # Footer-first metric reads issue their own ranged requests.
  defp prefetchable?(%{signal: :metrics, metric_discovery?: false, config: %{metric_footer_pruning_enabled: true}}),
    do: false

  defp prefetchable?(_ctx), do: true

  defp prefetch(config, limit, key) when is_integer(limit), do: read_bounded_segment(config, key, limit)
  defp prefetch(config, _limit, key), do: ObjectCache.get(config, key)

  # -- Tempo search --------------------------------------------------------------
  #
  # The most recent `limit` traces holding a matching span, each with its
  # complete retained context, planned newest first in rounds. A round
  # discovers candidate trace IDs in the newest `n` candidate sources (those
  # whose summaries may hold a matching span: attribute/service sets prune only
  # publication-proven all-rich sources, so legacy sources always remain), then
  # reads every other retained source whose trace-ID summary may hold one of
  # them. A trace a later candidate could still add starts no later than that
  # source's `max_ts`, so once the round's `limit`th trace starts after the
  # newest unread candidate its answer is final. Otherwise the next round plans
  # four times as many; blobs read earlier are reused, not fetched again.
  defp tempo_search(manifest, start_ts, opts, tenant, config) do
    filters = TraceSummary.tempo_filters(opts[:tempo_search])
    # A trace-duration predicate must use every retained span, even when an
    # asymmetric child starts beyond the ordinary context horizon.
    config =
      case opts[:tempo_search] do
        {:expression, program} ->
          if SearchExpression.context?(program), do: Map.put(config, :trace_context_horizon_ms, 0), else: config

        _ ->
          config
      end

    plan = %{
      candidates: tempo_candidates(manifest, start_ts, Keyword.merge(opts, filters), tenant, config),
      context: tempo_context_plan(manifest, start_ts, opts, tenant, config),
      candidate?: &TraceSummary.matches?(&1.trace_summary, filters)
    }

    # One compacted source may already contain every requested trace. Recover
    # its context before admitting more candidates; larger rounds still run
    # unless complete trace starts prove the requested results are final.
    tempo_round(1, plan, {%{}, 0}, start_ts, opts, config)
  end

  # Format-4 manifests read only the leaves that can hold the newest `n`.
  defp tempo_candidates(%Manifest{version: 4} = root, start_ts, opts, tenant, config),
    do: fn n -> query_segments(root, :traces, start_ts, nil, Keyword.put(opts, :trace_window, n), tenant, config) end

  defp tempo_candidates(manifest, start_ts, opts, tenant, config) do
    fn n ->
      with {:ok, segments} <- query_segments(manifest, :traces, start_ts, nil, opts, tenant, config),
           do: {:ok, segments |> Enum.sort_by(&newest_first/1) |> Enum.take(n)}
    end
  end

  # Unknown bounds sort first, so a round never stops before them.
  defp newest_first(%{max_ts: nil, key: key}), do: {0, 0, key}
  defp newest_first(%{max_ts: max_ts, key: key}), do: {1, -max_ts, key}

  # Context needs every retained source within the context horizon of the
  # round's candidate segments that may hold a candidate trace: format-4
  # leaves whose ID blooms hold none of them are not read. A trace's spans
  # start within its duration of each other, so the horizon (one hour by
  # default, `:trace_context_horizon_ms`; 0 reads all retained sources) makes
  # context complete for every trace shorter than it, without reading the
  # whole retained catalog for each search.
  defp tempo_context_plan(%Manifest{version: 4} = root, start_ts, opts, tenant, config) do
    fn hashes, window, native ->
      {from, to} = context_bounds(window, start_ts, config)
      opts = opts |> Keyword.put(:context_hashes, hashes) |> Keyword.put(:tempo_context, native)
      query_segments(root, :traces, from, to, opts, tenant, config)
    end
  end

  defp tempo_context_plan(manifest, start_ts, opts, tenant, config) do
    fn _hashes, window, _native ->
      {from, to} = context_bounds(window, start_ts, config)
      query_segments(manifest, :traces, from, to, opts, tenant, config)
    end
  end

  defp context_bounds(window, start_ts, config) do
    horizon = Map.get(config, :trace_context_horizon_ms, 3_600_000) * 1_000_000

    if horizon > 0 and window != [] and Enum.all?(window, &(is_integer(&1.min_ts) and is_integer(&1.max_ts))) do
      from = Enum.min_by(window, & &1.min_ts).min_ts - horizon
      {if(start_ts, do: max(start_ts, from), else: from), Enum.max_by(window, & &1.max_ts).max_ts + horizon}
    else
      {start_ts, nil}
    end
  end

  defp tempo_round(n, plan, {memo, memo_bytes}, start_ts, opts, config) do
    with {:ok, planned} <- plan.candidates.(n + 1),
         {window, rest} = Enum.split(planned, n),
         :ok <- check_scan_budget(window, opts),
         {:ok, native} <- start_tempo_search(start_ts, opts),
         ctx = %{scan_ctx(:traces, config, window, start_ts, nil, opts, opts[:limit], native) | memo: memo},
         state = %{bytes: 0, decoded_bytes: 0, rows: 0, memo: memo, memo_bytes: memo_bytes},
         {:ok, json, kth, state} <- finish_round(ctx, plan, state) do
      if rest == [] or older_than?(kth, hd(rest)),
        do: {:ok, json},
        else: tempo_round(4 * n, plan, {state.memo, state.memo_bytes}, start_ts, opts, config)
    end
  end

  defp finish_round(ctx, plan, state) do
    with {:ok, state} <- tempo_scan(ctx, plan, state),
         {:ok, {json, kth}} <- native_result(NIF.tempo_search_finish_window(ctx.native)) do
      {:ok, json, kth, state}
    else
      {:error, _} = error ->
        _ = NIF.tempo_search_abort(ctx.native)
        error
    end
  end

  defp tempo_scan(ctx, plan, state) do
    with {:ok, state} <- scan_sources(ctx.segments, ctx, state),
         {:ok, ids} <- native_result(NIF.tempo_search_plan_seal(ctx.native)),
         do: tempo_context(ctx, plan, state, ids)
  end

  defp tempo_context(_ctx, _plan, state, <<>>), do: {:ok, state}

  defp tempo_context(ctx, plan, state, ids) do
    # Only bounded IDs/hashes cross BEAM, never spans. Native owns the candidate
    # intersection, bloom work budget and complete-context aggregation.
    hashes = for <<id::binary-size(32) <- ids>>, into: <<>>, do: :binary.part(:crypto.hash(:sha256, id), 0, 8)
    fetched = MapSet.new(ctx.segments, & &1.key)

    with {:ok, true} <- native_result(NIF.tempo_search_plan_hashes(ctx.native, hashes)),
         {:ok, segments} <- plan.context.(for(<<hash::64 <- hashes>>, do: hash), ctx.segments, ctx.native),
         :ok <- check_catalog(segments),
         {:ok, hits} <- context_hits(Enum.reject(segments, &MapSet.member?(fetched, &1.key)), ctx.native) do
      # Pruned sources prove they hold no potential match; unread candidates
      # may hold older traces, which the round's stop condition accounts for.
      {unplanned, pruned} = Enum.split_with(hits, plan.candidate?)
      offset = length(ctx.segments)

      with {:ok, state} <- scan_sources(unplanned, %{ctx | offset: offset, unplanned?: true}, state),
           do: scan_sources(pruned, %{ctx | offset: offset + length(unplanned)}, state)
    end
  end

  defp context_hits(segments, native) do
    Enum.reduce_while(segments, {:ok, []}, fn segment, {:ok, hits} ->
      {hashes, bits} = TraceSummary.context_filter(segment.trace_summary)

      case native_result(NIF.tempo_search_plan_may_match(native, hashes, bits)) do
        {:ok, false} -> {:cont, {:ok, hits}}
        {:ok, true} -> {:cont, {:ok, [segment | hits]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, hits} -> {:ok, Enum.reverse(hits)}
      error -> error
    end
  end

  defp check_catalog(segments) do
    limit = TraceSummary.plan_catalog_limit()

    if length(segments) > limit,
      do: QueryLimit.exceeded(:trace_catalog_segments, limit, length(segments), :candidates),
      else: :ok
  end

  @log_modes [:log_discovery, :log_fold, :log_metric]
  defp scan_mode(opts) do
    cond do
      opts[:metric_discovery] -> :metric_discovery
      opts[:trace_metrics] -> :trace_metrics
      mode = Enum.find(@log_modes, &opts[&1]) -> mode
      opts[:tempo_root_discovery] -> context_discovery_mode(opts[:tempo_root_discovery])
      opts[:tempo_discovery] -> :tempo_discovery
      opts[:tempo_search] -> :tempo_search
      opts[:trace_search] -> :search
      true -> opts[:assemble_trace]
    end
  end

  defp context_discovery_mode({"trace:duration", _}), do: :tempo_trace_duration_discovery
  defp context_discovery_mode({_root_key, _}), do: :tempo_root_discovery

  defp start_native_query(:traces, start, finish, opts) do
    case opts[:tempo_root_discovery] do
      nil ->
        start_native_trace_query(start, finish, opts)

      {key, predicates} ->
        start_context_discovery(start, key, predicates, opts[:discovery_window] || {0, 0})
    end
  end

  defp start_native_query(:metrics, start, finish, opts) do
    case opts[:metric_discovery] do
      {mode, key, selectors} ->
        case NIF.metric_discovery_new(mode, key, start, finish, selectors) do
          :fallback -> {:error, :invalid_discovery_selector}
          result -> result
        end

      nil ->
        {:ok, nil}
    end
  end

  defp start_native_query(:logs, start, finish, opts) do
    case opts[:log_discovery] do
      {mode, key} ->
        case NIF.log_discovery_new(mode, key, start, finish, opts[:service], opts[:matchers] || []) do
          :fallback -> {:error, :invalid_discovery_selector}
          result -> result
        end

      nil ->
        {:ok, nil}
    end
  end

  defp start_native_query(_signal, _start, _finish, _opts), do: {:ok, nil}

  defp start_context_discovery(floor, "trace:duration", predicates, {start, finish}),
    do: native_result(NIF.tempo_trace_duration_discovery_new(floor || 0, predicates, start, finish))

  defp start_context_discovery(floor, key, predicates, {start, finish}),
    do: native_result(NIF.tempo_root_discovery_new(floor || 0, key, predicates, start, finish))

  defp start_native_trace_query(start, finish, opts) do
    cond do
      opts[:trace_metrics] ->
        {:ok, nil}

      opts[:tempo_discovery] ->
        {scope, key, predicates} = opts[:tempo_discovery]
        start_discovery(start || 0, scope, key, predicates, opts[:discovery_window])

      opts[:tempo_search] ->
        start_tempo_search(start, opts)

      opts[:trace_search] ->
        native_result(
          NIF.trace_search_new(
            start,
            finish,
            opts[:trace_search],
            opts[:limit] || 100,
            opts[:max_trace_groups] || 65_536
          )
        )

      true ->
        start_native_span_query(start, finish, opts)
    end
  end

  defp start_discovery(floor, scope, key, {:expression, program}, window) do
    {start, finish} = window || {0, 0}
    native_result(NIF.tempo_expression_discovery_new(floor, scope, key, program, start, finish))
  end

  defp start_discovery(floor, scope, key, predicates, {start, finish}),
    do: native_result(NIF.tempo_windowed_discovery_new(floor, scope, key, predicates, start, finish))

  defp start_discovery(floor, scope, key, predicates, nil), do: start_discovery(floor, scope, key, predicates)

  defp start_discovery(floor, scope, key, []), do: native_result(NIF.tempo_discovery_new(floor, scope, key))

  defp start_discovery(floor, scope, key, predicates),
    do: native_result(NIF.tempo_filtered_discovery_new(floor, scope, key, predicates))

  defp start_tempo_search(start, opts) do
    {constructor, predicates} =
      case opts[:tempo_search] do
        {:expression, program} -> {&NIF.tempo_expression_search_new/6, program}
        predicates -> {&NIF.tempo_search_new/6, predicates}
      end

    native_result(
      constructor.(start || 0, opts[:trace_start], opts[:trace_end], predicates, opts[:limit] || 100, opts[:spss] || 3)
    )
  end

  defp start_native_span_query(start, finish, opts) do
    if Keyword.has_key?(opts, :native_json_fields) do
      maximum = opts[:max_records] || 9_223_372_036_854_775_807

      result =
        if opts[:assemble_trace] do
          NIF.trace_query_new_trace(opts[:assemble_trace], start, maximum)
        else
          NIF.trace_query_new(start, finish, span_query_filters(opts), opts[:native_json_fields], maximum)
        end

      native_result(result)
    else
      {:ok, nil}
    end
  end

  defp span_query_filters(opts) do
    filters = Map.put_new(trace_filters(opts), "limit", 5001)
    if opts[:full_sort_keys], do: Map.put(filters, "full_sort_keys", true), else: filters
  end

  defp native_result(:fallback), do: {:error, {:decode_failed, :parquet_decoder_rejected_input}}
  defp native_result(result), do: result

  defp finish_scan({:ok, %{fold: acc}}, nil, _limit, :log_fold), do: {:ok, {:log_fold, acc}}
  defp finish_scan({:ok, %{fold: acc}}, nil, _limit, :log_metric), do: {:ok, {:log_fold, acc}}
  defp finish_scan({:ok, %{fold: rows}}, nil, _limit, :trace_metrics), do: {:ok, {:log_fold, rows}}

  defp finish_scan({:ok, %{batches: batches}}, nil, _limit, _trace_id),
    do: {:ok, batches |> Enum.reverse() |> List.flatten()}

  defp finish_scan({:ok, _state}, native, _limit, :metric_discovery),
    do: native_result(NIF.metric_discovery_finish(native))

  defp finish_scan({:ok, _state}, native, _limit, :log_discovery), do: native_result(NIF.log_discovery_finish(native))

  defp finish_scan({:ok, _state}, native, _limit, :tempo_trace_duration_discovery),
    do: native_result(NIF.tempo_trace_duration_discovery_finish(native))

  defp finish_scan({:ok, _state}, native, _limit, :tempo_root_discovery),
    do: native_result(NIF.tempo_root_discovery_finish(native))

  defp finish_scan({:ok, _state}, native, _limit, :tempo_discovery),
    do: native_result(NIF.tempo_discovery_finish(native))

  defp finish_scan({:ok, _state}, native, _limit, :tempo_search), do: native_result(NIF.tempo_search_finish(native))

  defp finish_scan({:ok, _state}, native, _limit, :search), do: native_result(NIF.trace_search_finish(native))

  defp finish_scan({:ok, _state}, native, limit, trace_id) do
    maximum = if limit in [nil, 5001], do: 5000, else: 9_223_372_036_854_775_807

    result =
      if is_nil(trace_id),
        do: NIF.trace_query_finish(native, maximum),
        else: NIF.trace_query_finish_trace(native, maximum, trace_id)

    native_result(result)
  end

  defp finish_scan({:error, _} = error, native, _limit, :metric_discovery) do
    _ = NIF.metric_discovery_abort(native)
    error
  end

  defp finish_scan({:error, _} = error, native, _limit, :log_discovery) do
    _ = NIF.log_discovery_abort(native)
    error
  end

  defp finish_scan({:error, _} = error, native, _limit, mode)
       when mode in [:tempo_search, :tempo_root_discovery, :tempo_trace_duration_discovery] do
    _ = NIF.tempo_search_abort(native)
    error
  end

  defp finish_scan({:error, _} = error, _native, _limit, _trace_id), do: error

  defp visit_segment({segment, index}, {:ok, state}, ctx, fetched \\ nil) do
    with :ok <- check_visited_budget(ctx.offset + index + 1, state.rows + stored_rows(ctx, segment), ctx),
         :ok <- check_read_bytes(state.bytes + (segment.byte_size || 0), ctx.opts),
         :ok <- check_deadline(ctx.opts[:deadline_ms]),
         {:ok, blob} <- fetched || read_segment(ctx, segment.key, state),
         :ok <- check_deadline(ctx.opts[:deadline_ms]),
         bytes = state.bytes + scan_bytes(blob),
         :ok <- check_read_bytes(bytes, ctx.opts),
         {:ok, row_count} <- scan_row_count(ctx, segment, blob),
         rows = state.rows + row_count,
         :ok <- check_visited_budget(ctx.offset + index + 1, rows, ctx) do
      continue_or_halt(remember(%{state | bytes: bytes, rows: rows}, segment.key, blob), blob, index, ctx)
    else
      {:error, {:footer_source_missing, cost, rows}} ->
        {:halt,
         {:error,
          {:segment_missing,
           %{
             max_scan_bytes: state.bytes + cost,
             max_scan_segments: ctx.offset + index + 1,
             max_scan_rows: state.rows + rows
           }}}}

      {:error, :not_found} ->
        consumed = %{
          max_scan_bytes: state.bytes,
          max_decoded_bytes: state.decoded_bytes,
          max_scan_segments: ctx.offset + index + 1,
          max_scan_rows: state.rows
        }

        {:halt, {:error, {:segment_missing, consumed}}}

      {:error, _} = err ->
        {:halt, err}
    end
  end

  # Tempo search rounds keep what they read for later, larger rounds, up to
  # @memo_bytes; other scans carry no memo.
  @memo_bytes 64 * 1024 * 1024
  defp remember(%{memo: memo, memo_bytes: used} = state, key, blob) when is_binary(blob) do
    cond do
      is_map_key(memo, key) -> state
      used + byte_size(blob) > @memo_bytes -> state
      true -> %{state | memo: Map.put(memo, key, blob), memo_bytes: used + byte_size(blob)}
    end
  end

  defp remember(state, _key, _blob), do: state

  # Catalogs charge the rows discovery reads from them, known only once read.
  defp stored_rows(%{catalogs?: true}, _segment), do: 0
  defp stored_rows(%{signal: :metrics, metric_discovery?: false}, _segment), do: 0
  defp stored_rows(%{signal: :logs, log_discovery?: false}, _segment), do: 0
  defp stored_rows(_ctx, segment), do: segment.row_count || 0

  defp scan_bytes(%MetricFooterReader{charge: cost}), do: cost
  defp scan_bytes(blob), do: byte_size(blob)

  defp read_segment(%{memo: %{} = memo}, key, _state) when is_map_key(memo, key), do: {:ok, Map.fetch!(memo, key)}

  defp read_segment(
         %{signal: :metrics, metric_discovery?: false, config: %{metric_footer_pruning_enabled: true}} = ctx,
         key,
         state
       ) do
    # The query's rows budget counts matched rows (charged after decoding), so
    # only the reader's own per-source footer row ceiling applies here.
    opts = Keyword.delete(ctx.opts, :max_scan_rows)

    opts =
      if is_integer(opts[:max_scan_bytes]),
        do: Keyword.put(opts, :max_scan_bytes, opts[:max_scan_bytes] - state.bytes),
        else: opts

    MetricFooterReader.read(ctx.config, key, ctx.start_ts, ctx.end_ts, ctx.opts[:matchers] || [], opts)
  end

  defp read_segment(ctx, key, %{bytes: consumed}) do
    case ctx.opts[:max_scan_bytes] do
      limit when is_integer(limit) ->
        remaining = limit - consumed

        if remaining > 0,
          do: read_bounded_segment(ctx.config, key, remaining),
          else: QueryLimit.exceeded(:max_scan_bytes, limit, consumed, :visited)

      _ ->
        ObjectCache.get(ctx.config, key)
    end
  end

  defp read_bounded_segment(config, key, remaining) do
    case ObjectCache.get_bounded(config, key, remaining) do
      {:ok, body} -> {:ok, body}
      {:error, :response_too_large} -> QueryLimit.exceeded(:max_scan_bytes, remaining, nil, :object)
      error -> error
    end
  end

  defp check_read_bytes(bytes, opts) do
    if exceeds_budget?(bytes, opts[:max_scan_bytes]),
      do: QueryLimit.exceeded(:max_scan_bytes, opts[:max_scan_bytes], bytes, :visited),
      else: :ok
  end

  defp check_visited_budget(count, rows, ctx) do
    cond do
      exceeds_budget?(count, ctx.opts[:max_scan_segments]) ->
        QueryLimit.exceeded(:max_scan_segments, ctx.opts[:max_scan_segments], count, :visited)

      exceeds_budget?(rows, ctx.opts[:max_scan_rows]) ->
        QueryLimit.exceeded(:max_scan_rows, ctx.opts[:max_scan_rows], rows, :visited)

      true ->
        :ok
    end
  end

  defp scan_row_count(%{catalogs?: true}, _segment, _blob), do: {:ok, 0}
  defp scan_row_count(%{signal: :metrics, metric_discovery?: false}, _segment, _blob), do: {:ok, 0}
  # Log reads charge the rows their stream selector and line filters select
  # (charge_matched_rows/3), once known.
  defp scan_row_count(%{signal: :logs, log_discovery?: false}, _segment, _blob), do: {:ok, 0}

  defp scan_row_count(%{signal: :traces} = ctx, segment, blob) do
    # Whole-trace assembly and grouping cannot trust an undercounted manifest.
    # Charge the actual footer before expanding/accumulating native rows.
    if ctx.search? or not is_nil(ctx.opts[:assemble_trace]),
      do: scanned_row_count(:traces, %{segment | row_count: nil}, blob),
      else: scanned_row_count(:traces, segment, blob)
  end

  defp scan_row_count(%{metric_discovery?: true}, _segment, blob),
    do: native_result(NIF.metric_segment_parquet_row_count(blob))

  defp scan_row_count(ctx, segment, blob), do: scanned_row_count(ctx.signal, segment, blob)

  defp scanned_row_count(:traces, %{row_count: count}, blob) when count in [nil, 0] do
    # Legacy/LIST entries lack counts. Recover from the footer so conservative
    # scanning still charges rows instead of treating an unknown count as zero.
    case NIF.trace_segment_parquet_row_count(blob) do
      {:ok, count} -> {:ok, count}
      _ -> {:error, {:decode_failed, :parquet_decoder_rejected_input}}
    end
  end

  defp scanned_row_count(_signal, segment, _blob), do: {:ok, segment.row_count || 0}

  defp continue_or_halt(state, blob, index, %{native: native, catalogs?: true} = ctx) do
    hour = MetricCatalog.catalog_hour(elem(ctx.indexed, index))

    case native_result(NIF.metric_discovery_add_catalog(native, blob)) do
      {:ok, {rows, covers}} ->
        covers =
          Map.update(
            state.covers,
            hour,
            MetricCatalog.parse_covers(covers),
            &MapSet.union(&1, MetricCatalog.parse_covers(covers))
          )

        state = %{state | rows: state.rows + rows, covers: covers}

        case check_visited_budget(ctx.offset + index + 1, state.rows, ctx) do
          :ok -> {:cont, {:ok, state}}
          error -> {:halt, error}
        end

      {:error, _} = error ->
        {:halt, error}
    end
  end

  defp continue_or_halt(state, blob, _index, %{native: native, metric_discovery?: true}) do
    case native_result(NIF.metric_discovery_add(native, blob)) do
      {:ok, _rows} -> {:cont, {:ok, state}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp continue_or_halt(state, blob, _index, %{native: native, log_discovery?: true}) do
    case native_result(NIF.log_discovery_add(native, blob)) do
      {:ok, _rows} -> {:cont, {:ok, state}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp continue_or_halt(state, blob, _index, %{native: native, discovery?: true}) do
    case native_result(NIF.tempo_discovery_add(native, blob)) do
      {:ok, _rows} -> {:cont, {:ok, state}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp continue_or_halt(state, blob, _index, %{native: native, tempo?: true} = ctx) do
    add = if ctx.unplanned?, do: &NIF.tempo_search_add_unplanned/2, else: &NIF.tempo_search_add/2

    case native_result(add.(native, blob)) do
      {:ok, _rows} -> {:cont, {:ok, state}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp continue_or_halt(state, blob, _index, %{native: native, search?: true}) do
    # A trace can acquire an earlier start or its first matching span in ANY
    # remaining object. Span kth floors/early exits would lose whole traces.
    case native_result(NIF.trace_search_add(native, blob)) do
      {:ok, _rows} -> {:cont, {:ok, state}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp continue_or_halt(state, blob, index, %{native: native} = ctx) when not is_nil(native) do
    case native_result(NIF.trace_query_add(native, blob)) do
      {:ok, {count, kth, _rows}} ->
        next = next_segment(ctx, index)
        done? = is_nil(next) or (is_integer(kth) and is_integer(next.max_ts) and kth > next.max_ts)
        state = state |> Map.put(:count, count) |> Map.put(:kth, kth)
        if done?, do: {:halt, {:ok, state}}, else: {:cont, {:ok, state}}

      {:error, _} = error ->
        {:halt, error}
    end
  end

  # TraceQL metrics: the native accumulator reduces each segment's spans.
  defp continue_or_halt(state, blob, _index, %{trace_metrics: metrics} = ctx) when not is_nil(metrics) do
    case NIF.trace_metrics_add(metrics, blob, ctx.start_ts || 0) do
      {:ok, rows} -> {:cont, {:ok, %{state | fold: state.fold + rows}}}
      {:error, _} = error -> {:halt, error}
      :fallback -> {:halt, {:error, {:decode_failed, :invalid_trace_metadata}}}
    end
  end

  defp continue_or_halt(state, blob, _index, %{log_metric: scan} = ctx) when not is_nil(scan) do
    service = Keyword.get(ctx.opts, :service)
    matchers = Keyword.get(ctx.opts, :matchers, [])
    line_filters = Keyword.get(ctx.opts, :line_filters, [])

    case NIF.log_metric_scan_add(scan, blob, ctx.start_ts, ctx.end_ts, service, matchers, line_filters) do
      {:ok, {selected, kept}} ->
        {total_selected, total_kept} = state.fold

        case charge_matched_rows(state, selected, ctx.opts) do
          {:ok, state} -> {:cont, {:ok, %{state | fold: {total_selected + selected, total_kept + kept}}}}
          error -> {:halt, error}
        end

      {:error, _} = error ->
        {:halt, error}

      :fallback ->
        {:halt, {:error, :native_fallback}}
    end
  end

  # Fold each decoded segment into the caller's accumulator and release it,
  # so memory follows one segment rather than the whole result.
  defp continue_or_halt(state, blob, index, %{log_fold: {fun, _initial}} = ctx) do
    with {:ok, acc, count} <- fold_segment(blob, ctx, fun, state.fold, 0),
         {:ok, state} <- charge_matched_rows(state, count, ctx.opts) do
      state = %{state | fold: acc, count: state.count + count}
      if fold_done?(ctx, acc, index), do: {:halt, {:ok, state}}, else: {:cont, {:ok, state}}
    else
      {:error, _} = error -> {:halt, error}
    end
  end

  defp continue_or_halt(state, %MetricFooterReader{body: nil}, index, ctx) do
    if can_short_circuit?(state, ctx.limit, ctx, index), do: {:halt, {:ok, state}}, else: {:cont, {:ok, state}}
  end

  defp continue_or_halt(state, %MetricFooterReader{body: body}, index, ctx),
    do: continue_or_halt(state, body, index, ctx)

  defp continue_or_halt(state, blob, index, ctx) do
    # Dirty NIF term construction cannot reclaim garbage left by the preceding
    # merge. Compact it before expanding another bounded trace candidate set.
    if ctx.signal == :traces, do: :erlang.garbage_collect()

    opts = remaining_budget(ctx.opts, %{max_records: state.count, max_decoded_bytes: state.decoded_bytes})

    with {:ok, batch, decoded_bytes} <- decode_batch(ctx.signal, blob, trace_start_floor(state, ctx), ctx.end_ts, opts),
         {:ok, %{rows: rows}} <- matched_rows(ctx.signal, state, batch, ctx.opts),
         {:ok, batches} <- retain_batches(ctx.signal, [batch | state.batches], ctx.limit) do
      new_state = %{
        bytes: state.bytes,
        decoded_bytes: state.decoded_bytes + decoded_bytes,
        rows: rows,
        batches: batches,
        count: state.count + length(batch),
        top: top_timestamps(state.top, batch, ctx.limit)
      }

      if can_short_circuit?(new_state, ctx.limit, ctx, index),
        do: {:halt, {:ok, new_state}},
        else: {:cont, {:ok, new_state}}
    else
      {:error, _} = err -> {:halt, err}
    end
  end

  defp matched_rows(signal, state, batch, opts) when signal in [:metrics, :logs],
    do: charge_matched_rows(state, length(batch), opts)

  defp matched_rows(_signal, state, _batch, _opts), do: {:ok, state}

  defp trace_start_floor(state, %{signal: :traces, limit: limit, start_ts: start_ts})
       when is_integer(limit) and limit > 0 and state.count >= limit do
    # Anything strictly older than global kth cannot improve the result. Keep
    # the boundary inclusive: ID/metadata ties there still need comparison.
    case Enum.at(state.top, limit - 1) do
      timestamp when is_integer(timestamp) -> max(start_ts || timestamp, timestamp)
      _ -> start_ts
    end
  end

  defp trace_start_floor(_state, ctx), do: ctx.start_ts

  defp retain_batches(:traces, [batch | previous], limit) when is_integer(limit) do
    # Native survivors and the running top-k are already sorted. Merge without
    # re-sorting or allocating a full metadata key for every retained span.
    top = SortOrder.merge_spans(batch, List.flatten(previous), limit)
    bytes = Enum.reduce(top, 0, fn span, sum -> sum + SpanKey.size(span) end)
    if bytes <= 16 * 1024 * 1024, do: {:ok, [top]}, else: {:error, :query_resource_limit}
  end

  defp retain_batches(_signal, batches, _limit), do: {:ok, batches}

  defp decode_batch(signal, blob, start_ts, end_ts, opts) do
    if signal == :logs and opts[:max_decoded_bytes] != nil do
      decode_log_segment_bounded(blob, start_ts, end_ts, opts)
    else
      with {:ok, records} <- decode_segment(signal, blob, start_ts, end_ts, opts), do: {:ok, records, 0}
    end
  end

  defp can_short_circuit?(_state, nil, _ctx, _index), do: false

  defp can_short_circuit?(state, limit, ctx, index) when state.count >= limit do
    case next_segment(ctx, index) do
      nil ->
        true

      %{max_ts: nil} ->
        false

      %{max_ts: next_max} ->
        kth = Enum.at(state.top, limit - 1)
        kth != nil and kth > next_max
    end
  end

  defp can_short_circuit?(_state, _limit, _ctx, _index), do: false

  defp top_timestamps(top, _batch, nil), do: top

  defp top_timestamps(top, batch, limit) do
    batch_ts = for r <- batch, (ts = record_ts(r)) != nil, do: ts
    merge_desc(top, Enum.sort(batch_ts, :desc), limit)
  end

  defp record_ts(%Log{timestamp_ns: ts}), do: ts
  defp record_ts(%MetricSample{timestamp_ns: ts}), do: ts
  defp record_ts(%Span{timestamp_ns: ts}), do: ts

  defp merge_desc(_a, _b, 0), do: []
  defp merge_desc([], b, k), do: Enum.take(b, k)
  defp merge_desc(a, [], k), do: Enum.take(a, k)
  defp merge_desc([x | xs], [y | _] = b, k) when x >= y, do: [x | merge_desc(xs, b, k - 1)]
  defp merge_desc(a, [y | ys], k), do: [y | merge_desc(a, ys, k - 1)]

  defp trace_filters(opts) do
    opts
    |> Keyword.take([
      :service,
      :trace_id,
      :span_id,
      :parent_span_id,
      :name,
      :kind,
      :status_code,
      :attributes,
      :resource,
      :attributes_regex,
      :resource_regex,
      :root_only,
      :min_duration_ns,
      :max_duration_ns,
      :limit
    ])
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  @doc false
  @spec decode_segment(Pulse.Storage.signal(), binary(), term(), term(), keyword()) ::
          {:ok, [Pulse.Storage.signal_record()]} | {:error, term()}
  def decode_segment(:logs, blob, start_ts, end_ts, opts) when is_binary(blob) and is_list(opts) do
    decoded =
      if opts[:max_decoded_bytes] == nil,
        do: decode_log_records(blob, start_ts, end_ts, opts),
        else: decode_log_segment_bounded(blob, start_ts, end_ts, opts)

    case decoded do
      {:ok, records} -> {:ok, records}
      {:ok, records, _bytes} -> {:ok, records}
      {:error, _} = error -> error
      :fallback -> {:error, {:decode_failed, :parquet_decoder_rejected_input}}
    end
  end

  def decode_segment(:traces, blob, start_ts, end_ts, opts) when is_binary(blob) and is_list(opts) do
    max = Keyword.get(opts, :max_records, 9_223_372_036_854_775_807)

    case NIF.decode_trace_segment_parquet(blob, start_ts, end_ts, trace_filters(opts), max) do
      {:ok, records} -> {:ok, Enum.map(records, &Span.from_map/1)}
      {:error, _} = error -> error
      :fallback -> {:error, {:decode_failed, :parquet_decoder_rejected_input}}
    end
  end

  def decode_segment(:metrics, blob, start_ts, end_ts, opts) when is_binary(blob) and is_list(opts) do
    case decode_metrics(blob, start_ts, end_ts, Keyword.get(opts, :matchers, []), opts) do
      {:ok, records} -> {:ok, records}
      {:error, _} = error -> error
      :fallback -> {:error, {:decode_failed, :parquet_decoder_rejected_input}}
    end
  end

  defp decode_metrics(blob, start_ts, end_ts, matchers, opts) do
    case {Keyword.get(opts, :exemplars, false), Keyword.get(opts, :max_records)} do
      {true, _max} ->
        NIF.decode_metric_exemplars_parquet(blob, start_ts, end_ts, matchers)

      {false, nil} ->
        NIF.decode_metric_segment_parquet_v2(blob, start_ts, end_ts, matchers)

      {false, max} when is_integer(max) and max >= 0 ->
        NIF.decode_metric_segment_parquet_bounded_v2(blob, start_ts, end_ts, matchers, max)

      _ ->
        {:error, :invalid_query_limit}
    end
  end

  defp decode_log_records(blob, start_ts, end_ts, opts) do
    service = opts[:service]
    matchers = Keyword.get(opts, :matchers, [])
    line_filters = Keyword.get(opts, :line_filters, [])
    :ok = validate_decode_args(blob, start_ts, end_ts, service, matchers, line_filters)

    case opts[:max_records] do
      nil ->
        NIF.decode_log_segment_parquet(blob, start_ts, end_ts, service, matchers, line_filters)

      max when is_integer(max) and max >= 0 ->
        NIF.decode_log_segment_parquet_bounded(blob, start_ts, end_ts, service, matchers, line_filters, max)

      _ ->
        {:error, :invalid_query_limit}
    end
  end

  @doc """
  Decode logs with an explicit expanded-column budget and report charged bytes.

  `:max_decoded_bytes` is required; `:max_records` is optional. Charges include
  every decoded Arrow buffer, including rows later rejected by filters. Repeated
  string lengths and row bookkeeping are preflighted before Arrow expansion;
  batch sizes are bounded from actual values, not a receiver-specific row cap.
  The entire decode fails with `:query_decoded_limit`, never a partial result,
  when preflight, buffers or a selected row group's uncompressed metadata exceed
  the allowance.
  Callers scanning multiple objects must subtract the returned charge.
  """
  def decode_log_segment_bounded(blob, start_ts, end_ts, opts) do
    service = opts[:service]
    matchers = Keyword.get(opts, :matchers, [])
    line_filters = Keyword.get(opts, :line_filters, [])
    :ok = validate_decode_args(blob, start_ts, end_ts, service, matchers, line_filters)

    case {opts[:max_records], opts[:max_decoded_bytes]} do
      {records, bytes}
      when (is_nil(records) or (is_integer(records) and records >= 0)) and is_integer(bytes) and bytes >= 0 ->
        case NIF.decode_log_segment_parquet_limited(
               blob,
               start_ts,
               end_ts,
               service,
               matchers,
               line_filters,
               records,
               bytes
             ) do
          :fallback -> {:error, {:decode_failed, :parquet_decoder_rejected_input}}
          result -> result
        end

      _ ->
        {:error, :invalid_query_limit}
    end
  end

  defp validate_decode_args(blob, start, finish, service, matchers, line_filters)
       when is_binary(blob) and (is_nil(start) or is_integer(start)) and (is_nil(finish) or is_integer(finish)) and
              (is_nil(service) or is_binary(service)) and is_list(matchers) and is_list(line_filters) do
    :ok
  end

  defp prefix(tenant, signal) when is_binary(tenant) and is_binary(signal),
    do: "tenants/#{tenant}/#{@schema_version}/signal=#{signal}/"

  # Returns `date=<YYYY-MM-DD>/hour=<HH>/` for a nanosecond-epoch timestamp,
  # UTC. Nil `min_ts` maps to `0`, which becomes `date=1970-01-01/hour=00/` —
  # fine for correctness (segments with unknown bounds have always been a
  # degenerate case) and still prunable by the manifest's own bounds.
  defp time_partition(min_ns) when is_integer(min_ns) and min_ns >= 0 do
    seconds = div(min_ns, 1_000_000_000)
    dt = DateTime.from_unix!(seconds, :second)
    date = Date.to_iso8601(dt)
    hour = dt.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    "date=#{date}/hour=#{hour}/"
  end

  defp time_partition(_), do: "date=1970-01-01/hour=00/"

  # `caller_hash` is a 16-hex fingerprint of the pre-normalization records.
  @doc false
  @spec object_key(
          String.t(),
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          String.t(),
          String.t() | nil
        ) :: String.t()
  def object_key(tenant, signal, min_ts, max_ts, caller_hash, idempotency_key)
      when is_binary(tenant) and is_binary(signal) and is_binary(caller_hash) do
    suffix =
      case idempotency_key do
        <<key::binary>> when byte_size(key) > 0 ->
          "idem-" <> stable_hash(tenant <> "\0" <> key <> "\0" <> caller_hash)

        _ ->
          "rand-" <> caller_hash <> "-" <> rand_hex()
      end

    "#{prefix(tenant, signal)}#{time_partition(min_ts)}#{zero_pad(min_ts)}-#{zero_pad(max_ts)}-#{suffix}.parquet"
  end

  # Fingerprint of the raw caller records.
  @doc false
  @spec caller_content_hash(Pulse.Storage.signal(), [Pulse.Storage.signal_record()]) ::
          {:ok, String.t()}
  def caller_content_hash(:logs, records) when is_list(records) do
    canonical =
      Enum.map(records, fn %Log{} = r ->
        %{
          timestamp_ns: r.timestamp_ns,
          observed_timestamp_ns: r.observed_timestamp_ns,
          severity_number: r.severity_number,
          severity_text: r.severity_text,
          service: r.service,
          body: normalize_hash_value(r.body),
          trace_id: r.trace_id,
          span_id: r.span_id,
          attributes: r.attributes,
          resource: r.resource
        }
        |> then(fn fields ->
          # Keep legacy/Loki fingerprints unchanged when no OTLP envelope exists.
          with_log_metadata(fields, r.otlp)
        end)
      end)

    digest_hex(canonical)
  end

  def caller_content_hash(:metrics, records) when is_list(records) do
    canonical =
      Enum.map(records, fn %MetricSample{} = s ->
        fields =
          %{
            timestamp_ns: s.timestamp_ns,
            value: s.value,
            labels: s.labels
          }
          |> with_log_metadata(s.otlp)
          |> with_rich_sample(s)

        if is_nil(s.start_timestamp_ms), do: fields, else: Map.put(fields, :start_timestamp_ms, s.start_timestamp_ms)
      end)

    digest_hex(canonical)
  end

  def caller_content_hash(:traces, records) when is_list(records), do: digest_hex(Enum.map(records, &Span.to_map/1))

  defp with_log_metadata(fields, nil), do: fields
  defp with_log_metadata(fields, otlp), do: Map.put(fields, :otlp, otlp)

  # Histograms and exemplars join the hash only when present, so the keys of
  # plain samples stay what they were.
  defp with_rich_sample(canonical, %MetricSample{histogram: nil, exemplars: nil}), do: canonical

  defp with_rich_sample(canonical, %MetricSample{histogram: histogram, exemplars: exemplars}) do
    # These fixed historical struct tags are part of the deterministic key,
    # not the Parquet encoding. Changing them duplicates rich keyed retries.
    histogram = if histogram, do: Map.put(histogram, :__struct__, :"Elixir.Pulso.Record.NativeHistogram")

    exemplars =
      if exemplars, do: Enum.map(exemplars, &Map.put(&1, :__struct__, :"Elixir.Pulso.Record.Exemplar"))

    Map.merge(canonical, %{histogram: histogram, exemplars: exemplars})
  end

  defp digest_hex(canonical) do
    digest =
      :sha256
      |> :crypto.hash(:erlang.term_to_binary(canonical, [:deterministic]))
      |> Base.encode16(case: :lower)
      |> binary_part(0, @content_hash_width)

    {:ok, digest}
  end

  defp normalize_hash_value(v), do: v

  defp zero_pad(ns) when is_integer(ns) and ns >= 0 do
    ns
    |> Integer.to_string()
    |> String.pad_leading(@sort_key_width, "0")
  end

  defp stable_hash(bin) do
    :sha256
    |> :crypto.hash(bin)
    |> Base.encode16(case: :lower)
    |> binary_part(0, @content_hash_width)
  end

  defp rand_hex do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp take_limit(records, nil), do: records
  defp take_limit(records, limit) when is_integer(limit) and limit > 0, do: Enum.take(records, limit)

  defp config! do
    case Runtime.get_env(:pulse, __MODULE__) do
      nil ->
        raise "Pulse.Storage.S3 is not configured. Set `config :pulse, Pulse.Storage.S3, bucket: ..., endpoint: ..., region: ..., access_key_id: ..., secret_access_key: ..., allow_http: ...`"

      config ->
        Map.new(config)
    end
  end
end
