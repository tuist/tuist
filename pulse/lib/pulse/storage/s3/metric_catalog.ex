defmodule Pulse.Storage.S3.MetricCatalog do
  @moduledoc """
  Hourly series catalogs for metric label and series discovery.

  Discovery over samples costs one row per stored sample. A catalog
  (`-rollup-catalog-` key, `native/pulse_codec/src/metric_catalog.rs`) lists the
  distinct series of one UTC hour, with label-name, label-value and
  per-metric label-name sections, and names the sample segments it covers.
  Discovery reads an hour's catalogs plus the segments none of them covers,
  so its cost grows with series rather than samples.

  `build/3` runs on the metrics grouping lane, newest hours first:

    * a delta catalog lists the series of the hour's uncovered segments that
      the hour's catalogs do not list yet, and covers those segments;
    * once an hour holds `:merge_at` catalogs, or has settled with more than
      one, they are merged into one that retires them in the same
      conditional manifest transition.

  An hour's first catalog starts a lineage, named in its key, that its deltas
  and merges keep. Deltas only add series and a merge keeps every series it
  retires, so the union of a lineage's active catalogs never shrinks.
  Consolidation and finalization therefore stamp their outputs with the
  lineage when it covered every source (`Segment.catalog`). A catalog covers a
  segment for its hour when it names the segment's key, or when the segment
  lies inside the hour and carries the lineage of one of its active catalogs.
  Losing every catalog of an hour, as when a release that predates catalogs
  finalizes the hour (it treats `-rollup-` keys as rollups and retires them),
  ends the lineage, so its stamps stop counting and the hour is read again.

  Options: `:max_rows` (2_000_000 sample rows read per pass), `:max_sources`
  (256 segments per catalog), `:max_hours` (24 hours examined per pass),
  `:min_hour` and `:max_hour` (the hours a lane maintains, inclusive),
  `:merge_at` (8), `:settle_ms` (600_000), `:grace_ms` (3_600_000),
  `:concurrency` (8).
  """

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.ObjectCache
  alias Pulse.Storage.S3.Retention

  @hour_ns 3_600_000_000_000

  @doc """
  Catalog the uncovered segments of the newest hours that have them, and
  merge hours with too many catalogs. Returns `{:ok, %{hours: n, sources: n,
  rows: n}}` or `{:error, {hour, reason}}`.
  """
  def build(tenant, config, opts \\ []) do
    Pulse.Metrics.measure(:compaction, "catalog", fn -> do_build(tenant, config, opts) end, fn
      {:ok, %{sources: count}} -> %{segments: count}
      _ -> %{}
    end)
  end

  defp do_build(tenant, config, opts) do
    with :ok <- S3.validate_tenant(tenant),
         :ok <- NIF.ensure_metric_catalog_api!(),
         {:ok, root, _etag} <- Retention.load(tenant, "metrics", config) do
      if root.version == 3,
        do: {:ok, %{hours: 0, sources: 0, rows: 0, reason: :retention_managed}},
        else: build_root(root, tenant, config, opts)
    end
  end

  defp build_root(root, tenant, config, opts) do
    floor = JournalManifest.retention_floor(root) || 0
    now = System.os_time(:nanosecond)

    with {:ok, candidates} <- candidates(root, tenant, config) do
      candidates.segments
      |> Enum.filter(
        &(Segment.metric_tier(&1) in [:raw, :grouped, :final] and is_integer(&1.min_ts) and is_integer(&1.max_ts))
      )
      |> Enum.flat_map(&hours(&1, floor, now))
      |> Enum.uniq()
      |> Enum.filter(&(&1 >= Keyword.get(opts, :min_hour, floor) and &1 <= Keyword.get(opts, :max_hour, now)))
      |> Enum.sort(:desc)
      |> Enum.take(Keyword.get(opts, :max_hours, 24))
      |> build_hours(root, tenant, config, opts)
    end
  end

  defp build_hours(hours, root, tenant, config, opts) do
    max_rows = Keyword.get(opts, :max_rows, 2_000_000)

    Enum.reduce_while(hours, {:ok, %{hours: 0, sources: 0, rows: 0}}, fn
      _hour, {:ok, %{rows: rows} = acc} when rows >= max_rows ->
        {:halt, {:ok, acc}}

      hour, {:ok, acc} ->
        case build_hour(root, hour, tenant, config, opts, max_rows - acc.rows) do
          {:ok, nil} ->
            {:cont, {:ok, acc}}

          {:ok, %{sources: sources, rows: rows}} ->
            {:cont, {:ok, %{acc | hours: acc.hours + 1, sources: acc.sources + sources, rows: acc.rows + rows}}}

          {:error, reason} ->
            {:halt, {:error, {hour, reason}}}
        end
    end)
  end

  # The hours a segment has rows in, at most the newest 48, none expired or
  # in the future.
  defp hours(segment, floor, now) do
    first = max(MetricTiers.hour(segment.min_ts), MetricTiers.hour(floor))
    last = min(MetricTiers.hour(segment.max_ts), MetricTiers.hour(now))
    first = max(first, last - 47 * @hour_ns)
    if first > last, do: [], else: Enum.to_list(first..last//@hour_ns)
  end

  defp build_hour(root, hour, tenant, config, opts, budget) do
    with {:ok, samples} <- MetricTiers.segments(root, hour, hour + @hour_ns - 1, :samples, tenant, config),
         {:ok, catalogs} <- catalogs(root, hour, tenant, config),
         {:ok, blobs} <- fetch(config, catalogs, opts),
         {:ok, covered} <- covered_keys(blobs) do
      lineages = catalogs |> Enum.map(&lineage(&1.key)) |> Enum.reject(&is_nil/1) |> MapSet.new()

      uncovered =
        samples |> Enum.reject(&covered?(&1, hour, covered, lineages)) |> Enum.sort_by(&{&1.max_ts, &1.key})

      settled? = hour + @hour_ns + Keyword.get(opts, :settle_ms, 600_000) * 1_000_000 <= System.os_time(:nanosecond)

      # Concurrent first catalogs can start two lineages; merging keeps one.
      merge? =
        length(catalogs) >= Keyword.get(opts, :merge_at, 8) or MapSet.size(lineages) > 1 or
          (settled? and uncovered == [] and length(catalogs) > 1)

      batch = take_batch(uncovered, budget, Keyword.get(opts, :max_sources, 256))

      lineage =
        if MapSet.size(lineages) == 0,
          do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
          else: Enum.min(lineages)

      if batch == [] and not merge?,
        do: {:ok, nil},
        else: write(tenant, config, {hour, lineage}, {catalogs, blobs}, batch, merge?, {samples, covered}, opts)
    end
  end

  # Oldest segments first; the first is taken even when it alone exceeds the
  # row budget, so a large segment cannot stall its hour.
  defp take_batch(segments, budget, max_sources) do
    segments
    |> Enum.reduce_while({[], 0}, fn segment, {batch, rows} ->
      rows = rows + (segment.row_count || 0)

      if batch == [] or (length(batch) < max_sources and rows <= budget),
        do: {:cont, {[segment | batch], rows}},
        else: {:halt, {batch, rows}}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp write(tenant, config, {hour, lineage}, {catalogs, blobs}, batch, merge?, {samples, covered}, opts) do
    with {:ok, builder} <- native(NIF.metric_catalog_new(hour, hour + @hour_ns)),
         :ok <- add_catalogs(builder, blobs, if(merge?, do: :merge, else: :known)),
         {:ok, rows} <- add_segments(builder, config, batch, opts),
         covers = covers(merge?, samples, covered, batch),
         {:ok, {payload, series}} <- native(NIF.metric_catalog_finish(builder, Enum.join(covers, "\n"))),
         segment = catalog_segment(tenant, hour, lineage, payload, series),
         {:ok, _etag} <- ObjectStore.put(config, segment.key, payload) do
      ObjectCache.put(segment.key, payload)

      with :ok <- publish(tenant, config, catalogs, segment, merge?, opts),
           do: {:ok, %{sources: length(batch), rows: rows, series: series, merged: merge? && length(catalogs)}}
    end
  end

  # A merge names every still-active segment its catalogs covered.
  defp covers(true, samples, covered, batch),
    do:
      Enum.filter(samples, &MapSet.member?(covered, &1.key))
      |> Enum.map(& &1.key)
      |> Enum.concat(Enum.map(batch, & &1.key))
      |> Enum.uniq()

  defp covers(false, _samples, _covered, batch), do: Enum.map(batch, & &1.key)

  defp publish(tenant, config, _catalogs, segment, false, _opts),
    do: ManifestOwner.register_segments(tenant, "metrics", [segment], config)

  defp publish(tenant, config, catalogs, segment, true, opts) do
    grace = Keyword.get(opts, :grace_ms, 3_600_000)

    case MetricTiers.publish(tenant, config, Enum.map(catalogs, & &1.key), [segment], grace) do
      :ok ->
        :ok

      # Ambiguous failures keep the upload: the manifest may reference it.
      {:error, reason} = error when reason in [:compaction_conflict, :cas_retries_exhausted] ->
        ObjectStore.delete(config, segment.key)
        error

      {:error, {:unpublished, reason}} ->
        ObjectStore.delete(config, segment.key)
        {:error, reason}

      error ->
        error
    end
  end

  # `<min>-<max>-rollup-catalog-<lineage>-<random>.parquet`: releases that
  # predate catalogs see a rollup, which they never read as samples. Its time
  # range spans the hour, unlike a rollup's single instant, so their rollup
  # planning skips it too.
  @doc false
  def catalog_segment(tenant, hour, lineage, payload, series) do
    key = S3.object_key(tenant, "metrics", hour, hour + @hour_ns - 1, lineage, nil)
    key = Path.join(Path.dirname(key), String.replace(Path.basename(key), "-rand-", "-rollup-catalog-"))
    Segment.build(key, hour, hour + @hour_ns - 1, series, byte_size(payload))
  end

  @doc "The lineage named in a catalog key."
  def lineage(key) do
    case String.split(Path.basename(key), "-rollup-catalog-", parts: 2) do
      [_, rest] -> rest |> String.split("-", parts: 2) |> hd()
      _ -> nil
    end
  end

  defp add_catalogs(builder, blobs, source) do
    Enum.reduce_while(blobs, :ok, fn {_segment, blob}, :ok ->
      case native(NIF.metric_catalog_add(builder, blob, source)) do
        {:ok, _rows} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp add_segments(builder, config, segments, opts) do
    segments
    |> Pulse.Runtime.Task.async_stream(&ObjectCache.get(config, &1.key),
      max_concurrency: Keyword.get(opts, :concurrency, 8),
      ordered: false,
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, 0}, fn
      {:ok, {:ok, blob}}, {:ok, rows} ->
        case native(NIF.metric_catalog_add(builder, blob, :segment)) do
          {:ok, added} -> {:cont, {:ok, rows + added}}
          error -> {:halt, error}
        end

      {:ok, {:error, _} = error}, _acc ->
        {:halt, error}
    end)
  end

  defp native(:fallback), do: {:error, {:encode_failed, :metric_catalog_rejected_input}}
  defp native(result), do: result

  @doc """
  The lineage of the hour's catalogs in `root` when it is the only one and
  covers every segment of `segments` (`covered?/4`), else nil.
  Consolidation and finalization stamp their outputs with it.
  """
  def covering_lineage(root, hour, segments, tenant, config) do
    with {:ok, [_ | _] = catalogs} <- catalogs(root, hour, tenant, config),
         [lineage] <- catalogs |> Enum.map(&lineage(&1.key)) |> Enum.uniq(),
         {:ok, blobs} <- fetch(config, catalogs, []),
         {:ok, covered} <- covered_keys(blobs),
         true <- Enum.all?(segments, &covered?(&1, hour, covered, MapSet.new([lineage]))) do
      lineage
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Whether an hour's active catalogs, naming `keys` and of `lineages`, cover
  `segment` for `hour`.
  """
  def covered?(segment, hour, keys, lineages) do
    MapSet.member?(keys, segment.key) or
      (is_binary(segment.catalog) and MapSet.member?(lineages, segment.catalog) and is_integer(segment.min_ts) and
         is_integer(segment.max_ts) and
         MetricTiers.hour(segment.min_ts) == hour and MetricTiers.hour(segment.max_ts) == hour)
  end

  @doc "The hour a catalog describes, or nil for an object that is not one."
  def catalog_hour(%Segment{min_ts: min, max_ts: max} = segment) when is_integer(min) and is_integer(max) do
    if Segment.metric_tier(segment) == :catalog and rem(min, @hour_ns) == 0 and max == min + @hour_ns - 1, do: min
  end

  def catalog_hour(_segment), do: nil

  defp catalogs(root, hour, tenant, config) do
    with {:ok, catalogs} <- MetricTiers.segments(root, hour, hour + @hour_ns - 1, :catalog, tenant, config),
         do: {:ok, Enum.filter(catalogs, &(catalog_hour(&1) == hour))}
  end

  defp fetch(config, catalogs, opts) do
    catalogs
    |> Pulse.Runtime.Task.async_stream(&{&1, ObjectCache.get(config, &1.key)},
      max_concurrency: Keyword.get(opts, :concurrency, 8),
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {segment, {:ok, blob}}}, {:ok, acc} -> {:cont, {:ok, [{segment, blob} | acc]}}
      {:ok, {_segment, {:error, _} = error}}, _acc -> {:halt, error}
    end)
    |> case do
      {:ok, blobs} -> {:ok, Enum.reverse(blobs)}
      error -> error
    end
  end

  defp covered_keys(blobs) do
    Enum.reduce_while(blobs, {:ok, MapSet.new()}, fn {_segment, blob}, {:ok, acc} ->
      case NIF.metric_catalog_covers(blob) do
        {:ok, covers} -> {:cont, {:ok, MapSet.union(acc, parse_covers(covers))}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc false
  def parse_covers(""), do: MapSet.new()
  def parse_covers(covers), do: covers |> String.split("\n") |> MapSet.new(&:binary.copy/1)

  defp candidates(%{version: 4} = root, tenant, config), do: JournalManifest.candidates(root, tenant, "metrics", config)
  defp candidates(root, _tenant, _config), do: {:ok, root}
end
