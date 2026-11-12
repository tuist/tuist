defmodule Pulse.Storage.S3.MetricTiers do
  @moduledoc """
  Hour finalization of metric segments.

  Once a UTC hour has settled, `finalize/3` reads every segment overlapping it
  and replaces them, in one conditional manifest transition, with:

    * the hour's rows grouped by metric name into `-final-` segments of about
      `:target_rows` rows, so a selector's manifest name summary skips every
      other metric's rows;
    * the rows outside the hour from segments straddling its edges, written
      back as raw `-edge-` segments (distinct from ingested keys, so manifest
      recovery never adopts them);
    * hourly rollup objects (`-rollup-`), one row per series with float
      samples in the hour, that PromQL composes into long range functions.

  Every row is kept, including duplicates and typed metadata; nothing is
  aggregated away. Late writes into a finalized hour make it raw again for
  queries (they ignore its rollups while any raw or grouped segment overlaps
  it) until the next finalization rewrites it. Prefixes with enforced
  retention (format 3 manifests) are not finalized yet.

  An hour holding more than `:max_rows` rows is finalized in passes, one per
  equal range of metric-name hashes (`name_partition/2`): each pass keeps only
  its metrics' rows and reads only the segments whose listed names can fall in
  its range, and one manifest transition publishes every pass. A single
  metric with more than `:max_rows` rows in an hour cannot be finalized.

  Before an hour ends, `consolidate/3` rewrites its settled raw segments,
  newest hour first, into `-group-` segments grouped and ordered the same way, so
  a selector reads only the segments holding its metric instead of every
  ingested segment, and a partitioned finalization reads each one once.
  A bounded batch qualifies at 32 sources or `:consolidate_min_rows` rows,
  so low-volume hours also stay below query object limits. Selection skips
  sources that do not fit the remaining row budget and keeps considering
  later sources, stopping when either the row or source cap is full.

  If no raw batch qualifies, consolidation also packs small `-group-`
  fragments with identical complete metric-name sets in the same hour.
  Sources each hold at most half of `min(:target_rows, :consolidate_max_rows)`;
  the batch fits that limit and qualifies at 32 sources or more than half
  the limit in rows. This produces one output without widening the name set.
  Fuller outputs and undersized tails are left for later finalization.

  Outputs whose sources the hour's series catalogs all covered carry their
  lineage, so catalog maintenance and discovery need not read them
  (`Pulse.Storage.S3.MetricCatalog`).

  Options: `:settle_ms` (600_000), `:target_rows` (32_768),
  `:rollup_target_rows` (65_536), `:max_rows` (4_000_000), `:max_sources`
  (8192), `:grace_ms` (3_600_000), `:concurrency` (8). Consolidation:
  `:consolidate_settle_ms` (15_000), `:consolidate_min_rows` (500_000),
  `:consolidate_max_rows` (1_000_000), `:consolidate_max_sources` (512).
  """

  import Bitwise

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.MetricCatalog
  alias Pulse.Storage.S3.ObjectCache
  alias Pulse.Storage.S3.Retention

  @hour_ns 3_600_000_000_000
  @u64 0xFFFF_FFFF_FFFF_FFFF

  @doc """
  The partition, of `count` equal ranges of 64-bit metric-name hashes,
  holding `name`; the native finalizer partitions rows the same way.
  """
  def name_partition(name, count) when is_binary(name) and is_integer(count) and count > 0,
    do: (name_hash(name) * count) >>> 64

  # FNV-1a finished with MurmurHash3's fmix64, as `metric_tiers.rs` does.
  defp name_hash(name) do
    hash =
      for <<byte <- name>>, reduce: 0xCBF2_9CE4_8422_2325 do
        hash -> bxor(hash, byte) * 0x0000_0100_0000_01B3 &&& @u64
      end

    hash = bxor(hash, hash >>> 33) * 0xFF51_AFD7_ED55_8CCD &&& @u64
    hash = bxor(hash, hash >>> 33) * 0xC4CE_B9FE_1A85_EC53 &&& @u64
    bxor(hash, hash >>> 33)
  end

  @doc "Start of the UTC hour holding `ts`."
  def hour(ts), do: Integer.floor_div(ts, @hour_ns) * @hour_ns
  def hour_ns, do: @hour_ns

  @doc """
  Finalize the oldest settled hour that still has raw segments among the
  bounded compaction candidates, except `:skip_hours`. Returns
  `{:ok, %{hour: start | nil, ...}}`, or `{:error, {hour, reason}}`.
  """
  def finalize(tenant, config, opts \\ []) do
    Pulse.Metrics.measure(:compaction, "finalize", fn -> do_finalize(tenant, config, opts) end, fn
      {:ok, %{sources: count}} -> %{segments: count}
      _ -> %{}
    end)
  end

  defp do_finalize(tenant, config, opts) do
    with :ok <- S3.validate_tenant(tenant),
         {:ok, root, _etag} <- Retention.load(tenant, "metrics", config) do
      case root.version do
        3 -> {:ok, %{hour: nil, reason: :retention_managed}}
        _ -> finalize_root(root, tenant, config, opts)
      end
    end
  end

  defp finalize_root(root, tenant, config, opts) do
    settle = Keyword.get(opts, :settle_ms, 600_000) * 1_000_000
    settled_before = System.os_time(:nanosecond) - settle
    # Hours that failed recently, so one oversized hour cannot block the rest.
    skip = Keyword.get(opts, :skip_hours, MapSet.new())
    # Hours wholly below the retention floor are expiring, not worth rewriting.
    floor = JournalManifest.retention_floor(root) || 0

    with {:ok, candidates} <- candidates(root, tenant, config) do
      candidates.segments
      |> Enum.filter(&(Segment.metric_tier(&1) in [:raw, :grouped] and is_integer(&1.min_ts) and is_integer(&1.max_ts)))
      |> Enum.map(fn s ->
        first = max(hour(s.min_ts), hour(floor))
        last = min(hour(s.max_ts), hour(settled_before) - @hour_ns)
        first_unskipped_hour(first, last, skip)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> nil end)
      |> finalize_oldest(root, tenant, config, opts)
    end
  end

  # Clamp the interval arithmetically, then visit only explicitly skipped
  # hours. Sparse or malformed timestamps must not allocate their entire span.
  defp first_unskipped_hour(first, last, _skip) when first > last, do: nil

  defp first_unskipped_hour(first, last, skip) do
    if MapSet.member?(skip, first), do: first_unskipped_hour(first + @hour_ns, last, skip), else: first
  end

  defp finalize_oldest(nil, _root, _tenant, _config, _opts), do: {:ok, %{hour: nil}}

  defp finalize_oldest(start, root, tenant, config, opts) do
    case finalize_hour(root, start, tenant, config, opts) do
      {:error, reason} -> {:error, {start, reason}}
      result -> result
    end
  end

  @doc """
  Consolidate a batch of settled raw segments in the newest eligible hour,
  oldest fitting segments first within that hour. The segments must lie inside
  one hour, with at least 32 sources or `:consolidate_min_rows` rows: up to
  `:consolidate_max_rows` rows are rewritten into `-group-` segments grouped
  by metric name, published in one manifest transition. When no raw batch
  qualifies, pack compatible small grouped fragments as described above. Returns
  `{:ok, %{hour: start | nil, ...}}` or `{:error, {hour, reason}}`.
  """
  def consolidate(tenant, config, opts \\ []) do
    Pulse.Metrics.measure(:compaction, "consolidate", fn -> do_consolidate(tenant, config, opts) end, fn
      {:ok, %{sources: count}} -> %{segments: count}
      _ -> %{}
    end)
  end

  defp do_consolidate(tenant, config, opts) do
    with :ok <- S3.validate_tenant(tenant),
         {:ok, root, _etag} <- Retention.load(tenant, "metrics", config) do
      case root.version do
        3 -> {:ok, %{hour: nil, reason: :retention_managed}}
        _ -> consolidate_root(root, tenant, config, opts)
      end
    end
  end

  defp consolidate_root(root, tenant, config, opts) do
    settled_before = System.os_time(:nanosecond) - Keyword.get(opts, :consolidate_settle_ms, 15_000) * 1_000_000
    min_rows = Keyword.get(opts, :consolidate_min_rows, 500_000)
    max_rows = Keyword.get(opts, :consolidate_max_rows, 1_000_000)
    max_sources = Keyword.get(opts, :consolidate_max_sources, 512)

    with {:ok, candidates} <- candidates(root, tenant, config) do
      raw =
        candidates.segments
        |> Enum.filter(&(Segment.metric_tier(&1) == :raw and consolidatable?(&1, settled_before, max_rows)))
        |> Enum.group_by(&hour(&1.min_ts))
        |> Enum.sort_by(&elem(&1, 0), :desc)
        |> Enum.find_value(&hour_batch(&1, min_rows, max_rows, max_sources))

      batch =
        raw ||
          grouped_batch(
            candidates.segments,
            settled_before,
            max_rows,
            max_sources,
            Keyword.get(opts, :target_rows, 32_768)
          )

      consolidate_batch(batch, root, tenant, config, opts)
    end
  end

  # Regroup only underfilled outputs with identical complete names. One batch
  # fits one output; full outputs never re-enter, and small tails wait for
  # enough peers instead of being rewritten on every maintenance pass.
  defp grouped_batch(segments, settled_before, max_rows, max_sources, target_rows) do
    limit = min(max_rows, target_rows)

    segments
    |> Enum.filter(fn segment ->
      Segment.metric_tier(segment) == :grouped and is_list(segment.metric_names) and segment.metric_names != [] and
        consolidatable?(segment, settled_before, limit) and segment.row_count <= div(limit, 2)
    end)
    |> Enum.group_by(&{hour(&1.min_ts), Enum.sort(&1.metric_names)})
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.find_value(fn {{start, _names}, sources} ->
      hour_batch({start, sources}, div(limit, 2) + 1, limit, max_sources)
    end)
  end

  # Keep low-volume flushes below query object limits too, without rewriting
  # tiny batches on every pass. Grouping alone owns these raw sources.
  defp hour_batch({start, segments}, min_rows, max_rows, max_sources) do
    batch = segments |> Enum.sort_by(&{&1.max_ts, &1.key}) |> take_batch(max_rows, max_sources)
    if length(batch) >= 32 or Enum.sum_by(batch, & &1.row_count) >= min_rows, do: {start, batch}
  end

  defp consolidatable?(segment, settled_before, max_rows) do
    is_integer(segment.min_ts) and is_integer(segment.max_ts) and
      hour(segment.min_ts) == hour(segment.max_ts) and segment.max_ts <= settled_before and
      is_integer(segment.row_count) and segment.row_count in 1..max_rows
  end

  defp take_batch(segments, max_rows, max_sources) do
    segments
    |> Enum.reduce_while({[], 0}, fn segment, {batch, rows} ->
      cond do
        length(batch) >= max_sources or rows >= max_rows -> {:halt, {batch, rows}}
        rows + segment.row_count <= max_rows -> {:cont, {[segment | batch], rows + segment.row_count}}
        true -> {:cont, {batch, rows}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp consolidate_batch(nil, _root, _tenant, _config, _opts), do: {:ok, %{hour: nil}}

  defp consolidate_batch({start, sources}, root, tenant, config, opts) do
    max_rows = Keyword.get(opts, :consolidate_max_rows, 1_000_000)
    build_opts = Keyword.put(opts, :max_rows, max_rows)

    case build(tenant, config, start, sources, nil, build_opts, :grouped) do
      {:ok, outputs} ->
        outputs = mark_catalogued(outputs, root, start, sources, tenant, config)

        case publish(tenant, config, Enum.map(sources, & &1.key), outputs, Keyword.get(opts, :grace_ms, 3_600_000)) do
          :ok ->
            {:ok,
             %{
               hour: start,
               sources: length(sources),
               rows: Enum.sum_by(sources, & &1.row_count),
               grouped: length(outputs)
             }}

          {:error, reason} = error when reason in [:compaction_conflict, :cas_retries_exhausted] ->
            {:error, {start, elem(discard(config, outputs, error), 1)}}

          {:error, {:unpublished, reason}} ->
            {:error, {start, elem(discard(config, outputs, {:error, reason}), 1)}}

          {:error, reason} ->
            {:error, {start, reason}}
        end

      {:error, reason} ->
        {:error, {start, reason}}
    end
  end

  defp candidates(%{version: 4} = root, tenant, config), do: JournalManifest.candidates(root, tenant, "metrics", config)
  defp candidates(root, _tenant, _config), do: {:ok, root}

  @doc false
  # Finalize one hour now, whatever its age (tests and maintenance).
  def finalize_hour(tenant, start, config, opts) do
    with {:ok, root, _etag} <- Retention.load(tenant, "metrics", config) do
      if root.version == 3,
        do: {:ok, %{hour: nil, reason: :retention_managed}},
        else: finalize_hour(root, hour(start), tenant, config, opts)
    end
  end

  defp finalize_hour(root, start, tenant, config, opts) do
    finish = start + @hour_ns - 1

    with {:ok, samples} <- segments(root, start, finish, :samples, tenant, config),
         {:ok, rollups} <- segments(root, start, finish, :rollup, tenant, config),
         sources = samples ++ rollups,
         :ok <- check_sources(sources, opts),
         :ok <- if(samples == [], do: {:empty, start}, else: :ok),
         {:ok, count, outputs} <- build_partitions(tenant, config, start, samples, partitions(samples, opts), opts) do
      outputs = mark_catalogued(outputs, root, start, samples, tenant, config)
      grace = Keyword.get(opts, :grace_ms, 3_600_000)

      case publish(tenant, config, Enum.map(sources, & &1.key), outputs, grace) do
        :ok ->
          {:ok,
           %{
             hour: start,
             sources: length(sources),
             partitions: count,
             finals: Enum.count(outputs, &(Segment.metric_tier(&1) == :final)),
             rollups: Enum.count(outputs, &(Segment.metric_tier(&1) == :rollup))
           }}

        {:error, reason} = error when reason in [:compaction_conflict, :cas_retries_exhausted] ->
          discard(config, outputs, error)

        {:error, {:unpublished, reason}} ->
          discard(config, outputs, {:error, reason})

        error ->
          error
      end
    else
      {:empty, start} -> {:ok, %{hour: start, sources: 0, finals: 0, rollups: 0}}
      error -> error
    end
  end

  # Equal name-hash ranges whose expected rows fit `:max_rows` with headroom
  # for uneven ranges; one pass when the hour fits.
  defp partitions(samples, opts) do
    rows = Enum.sum_by(samples, &(&1.row_count || 0))
    budget = max(div(Keyword.get(opts, :max_rows, 4_000_000) * 3, 4), 1)
    max(div(rows + budget - 1, budget), 1)
  end

  # Build and upload each pass in turn, so only one pass's rows are held.
  # Metric names can hash unevenly: a pass over `:max_rows` restarts the hour
  # with twice the partitions, up to 256.
  defp build_partitions(tenant, config, start, samples, count, opts) do
    Enum.reduce_while(0..(count - 1)//1, {:ok, []}, fn index, {:ok, uploaded} ->
      partition = if count > 1, do: {index, count}
      sources = Enum.filter(samples, &partition_source?(&1, partition))

      case build(tenant, config, start, sources, partition, opts) do
        {:ok, outputs} -> {:cont, {:ok, outputs ++ uploaded}}
        error -> {:halt, discard(config, uploaded, error)}
      end
    end)
    |> case do
      {:ok, outputs} -> {:ok, count, outputs}
      {:error, :too_large} when count < 256 -> build_partitions(tenant, config, start, samples, count * 2, opts)
      error -> error
    end
  end

  # Segments with listed metric names are read only by the passes those names
  # fall in; raw segments with many names (a bloom or no summary) by every pass.
  defp partition_source?(_segment, nil), do: true
  defp partition_source?(%{metric_names: nil}, _partition), do: true

  defp partition_source?(%{metric_names: names}, {index, count}),
    do: Enum.any?(names, &(name_partition(&1, count) == index))

  defp check_sources(sources, opts) do
    if length(sources) > Keyword.get(opts, :max_sources, 8192), do: {:error, :too_many_sources}, else: :ok
  end

  @doc false
  # Every active segment of `tier` overlapping the hour, from manifest metadata only.
  def segments(%{version: 4} = root, start, finish, tier, tenant, config) do
    opts = [start_ts: start, end_ts: finish, metrics_filter: Segment.metrics_filter([], tier)]
    JournalManifest.query(root, tenant, "metrics", opts, config)
  end

  def segments(root, start, finish, tier, _tenant, _config) do
    filter = Segment.metrics_filter([], tier)
    {:ok, root |> Manifest.prune_by_time(start, finish) |> Enum.filter(&Segment.matches_metrics?(&1, filter))}
  end

  # Grouped and final outputs hold exactly their sources' rows of the hour,
  # so they are covered wherever every source was (`MetricCatalog`).
  defp mark_catalogued(outputs, root, hour, sources, tenant, config) do
    case MetricCatalog.covering_lineage(root, hour, sources, tenant, config) do
      nil ->
        outputs

      lineage ->
        Enum.map(outputs, &mark_catalogued(&1, lineage))
    end
  end

  defp mark_catalogued(output, lineage) do
    if Segment.metric_tier(output) in [:grouped, :final], do: %{output | catalog: lineage}, else: output
  end

  # Accumulate the sources natively, then encode and upload one output at a
  # time, so only one encoded output is in memory. Returns the uploaded
  # segments; a failure deletes the ones already uploaded.
  defp build(tenant, config, start, sources, partition, opts, tier \\ :final) do
    max_rows = Keyword.get(opts, :max_rows, 4_000_000)
    expected = min(Enum.sum_by(sources, &(&1.row_count || 0)), max_rows)
    target = Keyword.get(opts, :target_rows, 32_768)
    rollup_target = if tier == :final, do: Keyword.get(opts, :rollup_target_rows, 65_536), else: 0

    with :ok <- NIF.ensure_metric_tier_api!(),
         {:ok, finalizer} <- NIF.metric_finalize_new(start, start + @hour_ns, max_rows, expected, partition),
         :ok <- add_sources(finalizer, config, sources, opts),
         :ok <- NIF.metric_finalize_finish(finalizer, target, rollup_target, 128) do
      upload_next(finalizer, tenant, config, tier, [])
    else
      :fallback -> {:error, {:encode_failed, :parquet_encoder_rejected_input}}
      error -> error
    end
  end

  defp add_sources(finalizer, config, sources, opts) do
    sources
    |> Pulse.Runtime.Task.async_stream(&ObjectCache.get(config, &1.key),
      max_concurrency: Keyword.get(opts, :concurrency, 8),
      ordered: false,
      timeout: :infinity
    )
    |> Enum.reduce_while(:ok, fn
      {:ok, {:ok, blob}}, :ok -> blob |> add_source(finalizer) |> then(&{if(&1 == :ok, do: :cont, else: :halt), &1})
      {:ok, {:error, _} = error}, :ok -> {:halt, error}
    end)
  end

  defp add_source(blob, finalizer) do
    case NIF.metric_finalize_add(finalizer, blob) do
      {:ok, _rows} -> :ok
      {:error, _} = error -> error
      :fallback -> {:error, :invalid_segment}
    end
  end

  defp upload_next(finalizer, tenant, config, tier, acc) do
    case NIF.metric_finalize_next(finalizer) do
      {:ok, kind, {payload, min_ts, max_ts, rows, labels}} ->
        segment = output_segment(tenant, output_tier(kind, tier), payload, min_ts, max_ts, rows, labels)

        case ObjectStore.put(config, segment.key, payload) do
          {:ok, _etag} ->
            ObjectCache.put(segment.key, payload)
            upload_next(finalizer, tenant, config, tier, [segment | acc])

          {:error, _} = error ->
            discard(config, acc, error)
        end

      :done ->
        {:ok, Enum.reverse(acc)}

      {:error, _} = error ->
        discard(config, acc, error)

      :fallback ->
        discard(config, acc, {:error, {:encode_failed, :parquet_encoder_rejected_input}})
    end
  end

  defp output_tier(:final, tier), do: tier
  defp output_tier(:rollup, _tier), do: :rollup
  defp output_tier(_edge, _tier), do: :raw

  defp output_segment(tenant, tier, payload, min_ts, max_ts, rows, labels) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    key = S3.object_key(tenant, "metrics", min_ts, max_ts, suffix, nil)
    marker = %{final: "-final-", grouped: "-group-", rollup: "-rollup-", raw: "-edge-"}[tier]
    key = Path.join(Path.dirname(key), String.replace(Path.basename(key), "-rand-", marker))

    key
    |> Segment.build(min_ts, max_ts, rows, byte_size(payload))
    |> Segment.summarize_metrics(Enum.map(labels, &%{labels: &1}))
  end

  # Ambiguous failures keep their uploads: the manifest may reference them.
  defp discard(config, outputs, error) do
    Enum.each(outputs, &ObjectStore.delete(config, &1.key))
    error
  end

  @doc false
  # Replace `sources` with `outputs` in one conditional manifest transition of
  # `signal`, idempotent across a lost response; retired sources are deleted
  # after `grace`. As for compaction (`SignalCompactor`), a format-4
  # replacement is planned outside the manifest owner, which only commits it
  # in memory.
  def publish(tenant, config, sources, outputs, grace, signal \\ "metrics"),
    do: publish(tenant, config, sources, outputs, grace, signal, 2)

  defp publish(tenant, config, sources, outputs, grace, signal, retries) do
    marker = List.first(outputs)

    result =
      with {:ok, plan} <- plan(tenant, signal, config, sources, outputs, grace, retries < 2) do
        transaction = &transaction(&1, {sources, outputs, grace, plan}, tenant, signal, config)

        case ManifestOwner.transact(tenant, signal, config, transaction) do
          {:ok, :ok} ->
            :ok

          {:error, :cas_retries_exhausted} = error ->
            resolve_unconfirmed(tenant, signal, config, marker, plan, error)

          {:error, {:unconfirmed, reason}} ->
            resolve_unconfirmed(tenant, signal, config, marker, plan, {:error, {:unpublished, reason}})

          error ->
            error
        end
      end

    case result do
      # An append or unrelated maintenance can move a journal page while its
      # rewrite is in flight, even though all sources remain active. Replan
      # outside the owner, reusing uploads only after proving they were never
      # published. Missing/replaced sources still fail the fresh plan.
      {:error, {:unpublished, :compaction_conflict}} when retries > 0 ->
        publish(tenant, config, sources, outputs, grace, signal, retries - 1)

      result ->
        result
    end
  end

  defp transaction(current, {sources, outputs, grace, plan}, tenant, signal, config) do
    case published_inline?(current, List.first(outputs), plan, tenant, signal, config) do
      {:ok, true} -> {:done, :ok}
      {:ok, false} -> current |> prepare(sources, outputs, grace, plan, tenant, signal, config) |> write(plan)
      error -> error
    end
  end

  # Planned against the node's cached root, as compaction does.
  defp plan(tenant, signal, config, sources, outputs, grace, fresh?) do
    case ManifestOwner.ensure_loaded(tenant, signal, config, require_fresh_manifest: fresh?) do
      {:ok, %{manifest: %{version: 4} = snapshot}} ->
        deadline = System.system_time(:millisecond) + grace

        case JournalManifest.plan_replace(snapshot, sources, outputs, 1, deadline, tenant, signal, config) do
          {:ok, plan} -> {:ok, plan}
          {:error, reason} -> {:error, {:unpublished, reason}}
        end

      {:ok, _other} ->
        {:ok, nil}

      error ->
        error
    end
  end

  # Inside the owner a planned commit reads only the root: an output in the
  # tail is a lost earlier response, anything else is confirmed outside.
  defp published_inline?(%{version: 4} = current, marker, plan, _tenant, _signal, _config) when plan != nil,
    do: {:ok, Enum.any?(current.segments, &(&1.key == marker.key))}

  defp published_inline?(current, marker, _plan, tenant, signal, config),
    do: published?(current, marker, tenant, signal, config)

  # The last conditional response may have been lost after success.
  defp resolve_unconfirmed(tenant, signal, config, marker, plan, error) do
    with {:ok, current, _etag} <- Retention.load(tenant, signal, config),
         {:ok, published} <- published?(current, marker, tenant, signal, config),
         do: JournalManifest.settle_unconfirmed(published, plan, config, error)
  end

  defp write({:ok, updated}, _plan), do: {:write, updated, updated |> Manifest.encode() |> IO.iodata_to_binary(), :ok}

  defp write({:ok, sealed, payload}, _plan), do: {:write, sealed, payload, :ok}
  defp write({:error, reason}, nil), do: {:error, {:unpublished, reason}}
  defp write({:error, reason}, _plan), do: {:error, {:unconfirmed, reason}}

  defp prepare(%{version: 4} = root, _sources, _outputs, _grace, plan, tenant, signal, config) when plan != nil do
    with {:ok, updated} <- JournalManifest.commit_replace(root, plan, tenant, signal, config),
         {:ok, {sealed, payload, _}} <- JournalManifest.seal(updated, tenant, signal, config),
         do: {:ok, sealed, payload}
  end

  defp prepare(%{version: 4} = root, sources, outputs, grace, nil, tenant, signal, config) do
    deadline = System.system_time(:millisecond) + grace

    with {:ok, updated} <- JournalManifest.replace_all(root, sources, outputs, deadline, tenant, signal, config),
         {:ok, {sealed, payload, _}} <- JournalManifest.seal(updated, tenant, signal, config),
         do: {:ok, sealed, payload}
  end

  defp prepare(%{version: 3}, _sources, _outputs, _grace, _plan, _tenant, _signal, _config),
    do: {:error, :retention_managed}

  defp prepare(root, sources, outputs, grace, _plan, _tenant, _signal, _config),
    do: Manifest.replace_all(root, sources, outputs, System.system_time(:millisecond) + grace)

  defp published?(_root, nil, _tenant, _signal, _config), do: {:ok, false}

  defp published?(%{version: 4} = root, segment, tenant, signal, config) do
    with {:ok, found} <- JournalManifest.lookup(root, segment, tenant, signal, config), do: {:ok, found != :absent}
  end

  defp published?(%{version: 3}, _segment, _tenant, _signal, _config), do: {:ok, false}

  defp published?(root, segment, _tenant, _signal, _config),
    do: {:ok, Enum.any?(root.segments, &(&1.key == segment.key)) or Map.has_key?(root.retired, segment.key)}
end
