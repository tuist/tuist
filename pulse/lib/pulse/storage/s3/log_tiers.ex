defmodule Pulse.Storage.S3.LogTiers do
  @moduledoc """
  Stream-grouped log segments.

  Ingested and compacted log segments each hold a slice of time of every
  stream, so a stream selector such as `{service_name="tuist-web"}` reads
  every segment of its range. Log maintenance regroups them by service (by
  whole stream for lines without one): a service with at least
  `:target_rows` rows (or `:target_bytes` of decoded strings) in a rewrite
  fills segments of its own, and smaller services share segments of at
  most `:pack_bytes` in service order. Each output's manifest summaries
  (services, stream labels, per-minute line counts) then let a selector
  skip every other service's segments.

    * `finalize/3` rewrites a settled UTC hour (`:settle_ms` after it ends)
      into `-final-` segments, once: its ingested, compacted and grouped
      segments that start in the hour;
    * before an hour ends, `consolidate/3` rewrites settled raw segments of
      an hour that holds at least `:consolidate_min_rows` of them, oldest
      first and at most `:consolidate_max_rows` at a time, into `-group-`
      segments, so ranges over the last hours of a busy tenant read only
      their services too.

  Every row is kept as stored; nothing is aggregated. Outputs replace their
  sources in one conditional manifest transition (`MetricTiers.publish/6`),
  and the sources are deleted after the grace period. A write that arrives
  after its hour was finalized stays raw until the next pass finalizes it
  with that hour's other late writes. Log compaction never merges grouped
  or final segments, live tail never replays them, and log rollups stay
  valid because every output carries exact per-minute counts. Prefixes with
  format-3 (bucketed) retention manifests are not grouped.

  Options: `:settle_ms` (600_000), `:target_rows` (100_000), `:target_bytes`
  (32 MiB), `:pack_bytes` (8 MiB), `:max_held_bytes` (64 MiB), `:max_sources` (8192),
  `:concurrency` (8), `:grace_ms` (3_600_000), `:skip_hours`. Consolidation:
  `:consolidate_settle_ms` (60_000), `:consolidate_min_rows` (500_000),
  `:consolidate_max_rows` (1_000_000), `:consolidate_max_sources` (512).
  """

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.ObjectCache
  alias Pulse.Storage.S3.Retention

  @hour_ns 3_600_000_000_000

  @doc """
  Finalize the oldest settled hour that still has ungrouped or grouped log
  segments among the bounded compaction candidates, except `:skip_hours`.
  Returns `{:ok, %{hour: start | nil, ...}}` or `{:error, {hour, reason}}`.
  """
  def finalize(tenant, config, opts \\ []) do
    Pulse.Metrics.measure(
      :compaction,
      "log_finalize",
      fn -> with_root(tenant, config, &finalize_root(&1, tenant, config, opts)) end,
      fn
        {:ok, %{sources: count}} -> %{segments: count}
        _ -> %{}
      end
    )
  end

  @doc false
  # Finalize one hour now, whatever its age (tests and benchmarks).
  def finalize_hour(tenant, start, config, opts) do
    with_root(tenant, config, &finalize_hour(&1, MetricTiers.hour(start), tenant, config, opts))
  end

  @doc """
  Consolidate the oldest batch of settled raw log segments that lie inside
  one hour, when the hour holds at least `:consolidate_min_rows` of them.
  Returns `{:ok, %{hour: start | nil, ...}}` or `{:error, {hour, reason}}`.
  """
  def consolidate(tenant, config, opts \\ []) do
    Pulse.Metrics.measure(
      :compaction,
      "log_consolidate",
      fn -> with_root(tenant, config, &consolidate_root(&1, tenant, config, opts)) end,
      fn
        {:ok, %{sources: count}} -> %{segments: count}
        _ -> %{}
      end
    )
  end

  defp with_root(tenant, config, fun) do
    with :ok <- S3.validate_tenant(tenant),
         :ok <- NIF.ensure_log_tier_api!(),
         {:ok, root, _etag} <- Retention.load(tenant, "logs", config) do
      if root.version == 3, do: {:ok, %{hour: nil, reason: :retention_managed}}, else: fun.(root)
    end
  end

  defp finalize_root(root, tenant, config, opts) do
    settled_before = System.os_time(:nanosecond) - Keyword.get(opts, :settle_ms, 600_000) * 1_000_000
    skip = Keyword.get(opts, :skip_hours, MapSet.new())
    # Hours wholly below the retention floor are expiring, not worth rewriting.
    floor = JournalManifest.retention_floor(root) || 0

    with {:ok, candidates} <- candidates(root, tenant, config) do
      candidates.segments
      |> Enum.filter(&((ungrouped?(&1) or Segment.key_tier(&1.key) == :grouped) and is_integer(&1.min_ts)))
      |> Enum.map(&MetricTiers.hour(&1.min_ts))
      |> Enum.filter(&(&1 + @hour_ns <= settled_before and &1 + @hour_ns > floor and not MapSet.member?(skip, &1)))
      |> Enum.min(fn -> nil end)
      |> finalize_oldest(root, tenant, config, opts)
    end
  end

  defp finalize_oldest(nil, _root, _tenant, _config, _opts), do: {:ok, %{hour: nil}}

  defp finalize_oldest(start, root, tenant, config, opts) do
    case finalize_hour(root, start, tenant, config, opts) do
      {:error, reason} -> {:error, {start, reason}}
      result -> result
    end
  end

  defp finalize_hour(root, start, tenant, config, opts) do
    with {:ok, segments} <- segments(root, start, start + @hour_ns - 1, tenant, config) do
      sources =
        Enum.filter(segments, fn s ->
          (ungrouped?(s) or Segment.key_tier(s.key) == :grouped) and is_integer(s.min_ts) and
            MetricTiers.hour(s.min_ts) == start
        end)

      cond do
        sources == [] ->
          {:ok, %{hour: start, sources: 0, outputs: 0}}

        length(sources) > Keyword.get(opts, :max_sources, 8192) ->
          {:error, :too_many_sources}

        true ->
          rewrite(tenant, config, start, sources, :final, opts)
      end
    end
  end

  defp consolidate_root(root, tenant, config, opts) do
    settled_before = System.os_time(:nanosecond) - Keyword.get(opts, :consolidate_settle_ms, 60_000) * 1_000_000
    min_rows = Keyword.get(opts, :consolidate_min_rows, 500_000)
    max_rows = Keyword.get(opts, :consolidate_max_rows, 1_000_000)
    max_sources = Keyword.get(opts, :consolidate_max_sources, 512)

    with {:ok, candidates} <- candidates(root, tenant, config) do
      candidates.segments
      |> Enum.filter(&consolidatable?(&1, settled_before, max_rows))
      |> Enum.group_by(&MetricTiers.hour(&1.min_ts))
      |> Enum.sort()
      |> Enum.find_value(&hour_batch(&1, min_rows, max_rows, max_sources))
      |> consolidate_batch(tenant, config, opts)
    end
  end

  defp consolidate_batch(nil, _tenant, _config, _opts), do: {:ok, %{hour: nil}}

  defp consolidate_batch({start, sources}, tenant, config, opts) do
    case rewrite(tenant, config, start, sources, :grouped, opts) do
      {:ok, result} -> {:ok, Map.put(result, :hour, start)}
      {:error, reason} -> {:error, {start, reason}}
    end
  end

  # The oldest settled segments of an hour, if they hold enough rows.
  defp hour_batch({start, segments}, min_rows, max_rows, max_sources) do
    {batch, rows} =
      segments
      |> Enum.sort_by(&{&1.max_ts, &1.key})
      |> Enum.reduce_while({[], 0}, fn segment, {batch, rows} ->
        if length(batch) < max_sources and rows + segment.row_count <= max_rows,
          do: {:cont, {[segment | batch], rows + segment.row_count}},
          else: {:halt, {batch, rows}}
      end)

    if rows >= min_rows, do: {start, Enum.reverse(batch)}
  end

  defp consolidatable?(segment, settled_before, max_rows) do
    ungrouped?(segment) and is_integer(segment.min_ts) and is_integer(segment.max_ts) and
      MetricTiers.hour(segment.min_ts) == MetricTiers.hour(segment.max_ts) and segment.max_ts <= settled_before and
      is_integer(segment.row_count) and segment.row_count in 1..max_rows
  end

  # Ingested and compacted segments; rollups, grouped and final ones are not.
  defp ungrouped?(segment), do: Segment.key_tier(segment.key) == :raw

  defp candidates(%{version: 4} = root, tenant, config), do: JournalManifest.candidates(root, tenant, "logs", config)
  defp candidates(root, _tenant, _config), do: {:ok, root}

  # Every log segment overlapping `[start, finish]`, from manifest metadata only.
  defp segments(%{version: 4} = root, start, finish, tenant, config),
    do: JournalManifest.query(root, tenant, "logs", [start_ts: start, end_ts: finish], config)

  defp segments(root, start, finish, _tenant, _config) do
    opts = [start_ts: start, end_ts: finish]
    {:ok, root |> Manifest.prune_by_time(start, finish) |> Enum.filter(&Segment.matches_log_service?(&1, opts))}
  end

  # Group `sources` into `tier` outputs and publish them in their place.
  defp rewrite(tenant, config, start, sources, tier, opts) do
    with {:ok, outputs} <- build(tenant, config, sources, tier, opts) do
      grace = Keyword.get(opts, :grace_ms, 3_600_000)

      case MetricTiers.publish(tenant, config, Enum.map(sources, & &1.key), outputs, grace, "logs") do
        :ok ->
          {:ok,
           %{
             hour: start,
             sources: length(sources),
             rows: Enum.sum_by(sources, &(&1.row_count || 0)),
             outputs: length(outputs)
           }}

        {:error, reason} = error when reason in [:compaction_conflict, :cas_retries_exhausted] ->
          discard(config, outputs, error)

        {:error, {:unpublished, reason}} ->
          discard(config, outputs, {:error, reason})

        error ->
          error
      end
    end
  end

  # Add the sources oldest first, so a large service's segments follow time,
  # and upload each output as soon as it is due, so the grouper holds about
  # `:max_held_bytes`. A failure deletes the outputs already uploaded.
  defp build(tenant, config, sources, tier, opts) do
    target_rows = Keyword.get(opts, :target_rows, 100_000)
    target_bytes = Keyword.get(opts, :target_bytes, 32 * 1024 * 1024)
    pack_bytes = Keyword.get(opts, :pack_bytes, 8 * 1024 * 1024)
    max_held = Keyword.get(opts, :max_held_bytes, 64 * 1024 * 1024)

    case NIF.log_group_new(target_rows, target_bytes, pack_bytes, max_held) do
      {:ok, grouper} ->
        with {:ok, uploaded} <- add_sources(grouper, sources, tenant, config, tier, opts),
             do: drain(grouper, true, tenant, config, tier, uploaded)

      _ ->
        {:error, {:encode_failed, :log_group_rejected}}
    end
  end

  defp add_sources(grouper, sources, tenant, config, tier, opts) do
    sources
    |> Enum.sort_by(&{&1.min_ts, &1.key})
    |> Pulse.Runtime.Task.async_stream(&{&1, ObjectCache.get(config, &1.key)},
      max_concurrency: Keyword.get(opts, :concurrency, 8),
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, []}, fn {:ok, {source, fetched}}, {:ok, uploaded} ->
      with {:ok, blob} <- fetched,
           :ok <- add(grouper, source, blob),
           {:ok, uploaded} <- drain(grouper, false, tenant, config, tier, uploaded) do
        {:cont, {:ok, uploaded}}
      else
        {:error, _} = error -> {:halt, discard(config, uploaded, error)}
      end
    end)
  end

  defp add(grouper, source, blob) do
    case NIF.log_group_add(grouper, blob) do
      {:ok, rows} when rows == source.row_count or is_nil(source.row_count) -> :ok
      {:ok, _rows} -> {:error, :segment_summary_mismatch}
      {:error, _} = error -> error
      _ -> {:error, :invalid_segment}
    end
  end

  defp drain(grouper, finish, tenant, config, tier, uploaded) do
    case NIF.log_group_next(grouper, finish) do
      {:ok, {payload, min_ts, max_ts, rows, services, streams, minutes}} ->
        segment = output_segment(tenant, tier, payload, min_ts, max_ts, rows, {services, streams, minutes})

        case ObjectStore.put(config, segment.key, payload) do
          {:ok, _etag} ->
            ObjectCache.put(segment.key, payload)
            drain(grouper, finish, tenant, config, tier, [segment | uploaded])

          {:error, _} = error ->
            discard(config, uploaded, error)
        end

      :none ->
        {:ok, uploaded}

      :done ->
        {:ok, Enum.reverse(uploaded)}

      _ ->
        discard(config, uploaded, {:error, {:encode_failed, :log_group_rejected}})
    end
  end

  defp output_segment(tenant, tier, payload, min_ts, max_ts, rows, {services, streams, minutes}) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    key = S3.object_key(tenant, "logs", min_ts, max_ts, suffix, nil)
    marker = if tier == :final, do: "-final-", else: "-group-"
    key = Path.join(Path.dirname(key), String.replace(Path.basename(key), "-rand-", marker))

    key
    |> Segment.build(min_ts, max_ts, rows, byte_size(payload))
    |> Segment.summarize_log_streams(services, streams, minutes)
  end

  # Ambiguous publication failures keep their uploads: the manifest may
  # reference them; definitive ones are deleted.
  defp discard(config, outputs, error) do
    Enum.each(outputs, &ObjectStore.delete(config, &1.key))
    error
  end
end
