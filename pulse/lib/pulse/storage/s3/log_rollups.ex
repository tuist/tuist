defmodule Pulse.Storage.S3.LogRollups do
  @moduledoc """
  Per-minute log rollups: line counts and bytes per stream and minute,
  built by log maintenance from settled minutes and read by LogQL
  `count_over_time`, `bytes_over_time`, `rate` and `bytes_rate` over plain
  stream selectors whose windows and steps fall on minute boundaries.

  A rollup is a `-rollup-` object in the logs manifest whose `log_minutes`
  hold the lines it counted per minute. Every log segment carries the same
  per-minute counts, merged by compaction. A rollup answers a minute only
  while its count equals the sum of the segments' counts for that minute, so
  a late write, a retention deletion or an unknown legacy segment makes that
  minute read lines again until maintenance rebuilds it. Rollups never
  replace log lines; line queries do not see them.

  Each maintenance call (`roll/3`) writes one rollup, in the oldest hour
  within `:lookback_ms` that needs one: its earliest settled minutes without
  a valid rollup, counted from at most `:max_rows` source rows, or, once the
  hour is over, one rollup merging (copying) its several rollups. Minutes in
  `:skip` (minute numbers, `Segment.log_minute/1`) are left alone; a
  failure returns `{:error, {minute, reason}}` so the caller can skip it.
  Options: `:settle_ms` (30_000), `:lookback_ms` (7_200_000), `:max_rows`
  (4_000_000), `:concurrency` (8), `:grace_ms` (3_600_000), `:skip`.
  """

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.ObjectCache
  alias Pulse.Storage.S3.Retention

  @minute 60_000_000_000
  @hour 3_600_000_000_000

  @doc """
  Whether a range over `[start, finish]` consists of whole minute buckets.
  """
  def aligned?(start, finish), do: rem(start - 1, @minute) == 0 and rem(finish, @minute) == 0

  @doc """
  Plan a binned read of `[start, finish]` (`aligned?/2`), of which lines
  before `floor` are not retained. `raws` are every log segment overlapping
  the range, `rollups` every rollup. Returns `%{rollups: [{segment,
  bucket_ends}], gaps: [{from, to}]}`: the rollups answering each covered
  minute, and the line ranges to read from segments.
  """
  def plan(raws, rollups, start, floor, finish) do
    first = Segment.log_minute(start)
    last = Segment.log_minute(finish)
    {totals, unknown} = totals(raws, max(start, floor), finish)
    partial = if floor > start, do: MapSet.new(first..Segment.log_minute(floor)//1), else: MapSet.new()

    # Larger rollups first: a consolidated hour wins over its parts.
    {chosen, _} =
      rollups
      |> Enum.filter(&is_map(&1.log_minutes))
      |> Enum.sort_by(&{-(&1.max_ts - &1.min_ts), &1.key})
      |> Enum.map_reduce(MapSet.new(), fn rollup, taken ->
        minutes =
          for m <- max(first, Segment.log_minute(rollup.min_ts))..min(last, Segment.log_minute(rollup.max_ts))//1,
              Map.get(totals, m, 0) > 0,
              not MapSet.member?(taken, m) and not MapSet.member?(unknown, m) and not MapSet.member?(partial, m),
              Map.get(rollup.log_minutes, m, 0) == Map.fetch!(totals, m),
              do: m

        {{rollup, minutes}, MapSet.union(taken, MapSet.new(minutes))}
      end)

    covered = chosen |> Enum.flat_map(&elem(&1, 1)) |> MapSet.new()

    gaps =
      first..last//1
      |> Enum.filter(fn m ->
        not MapSet.member?(covered, m) and
          (Map.get(totals, m, 0) > 0 or MapSet.member?(unknown, m) or MapSet.member?(partial, m))
      end)
      |> intervals()
      |> Enum.map(fn {a, b} -> {max((a - 1) * @minute + 1, max(start, floor)), b * @minute} end)
      |> Enum.filter(fn {a, b} -> a <= b end)

    %{
      rollups: for({rollup, [_ | _] = minutes} <- chosen, do: {rollup, Enum.map(minutes, &(&1 * @minute))}),
      gaps: gaps
    }
  end

  # Lines per minute of the segments, and minutes a segment of unknown counts
  # may hold lines of.
  defp totals(raws, start, finish) do
    {first, last} = {Segment.log_minute(start), Segment.log_minute(finish)}

    Enum.reduce(raws, {%{}, MapSet.new()}, fn segment, {totals, unknown} ->
      case segment.log_minutes do
        %{} = minutes ->
          {add_minutes(totals, minutes, first, last), unknown}

        nil ->
          {totals, MapSet.union(unknown, MapSet.new(segment_minutes(segment, first, last)))}
      end
    end)
  end

  defp segment_minutes(segment, first, last) do
    from = if is_integer(segment.min_ts), do: max(first, Segment.log_minute(segment.min_ts)), else: first
    to = if is_integer(segment.max_ts), do: min(last, Segment.log_minute(segment.max_ts)), else: last
    from..to//1
  end

  defp add_minutes(totals, minutes, first, last) do
    Enum.reduce(minutes, totals, fn
      {m, count}, acc when m >= first and m <= last -> Map.update(acc, m, count, &(&1 + count))
      _, acc -> acc
    end)
  end

  defp intervals(minutes) do
    minutes
    |> Enum.chunk_while(
      nil,
      fn
        m, nil -> {:cont, {m, m}}
        m, {a, b} when m == b + 1 -> {:cont, {a, m}}
        m, run -> {:cont, run, {m, m}}
      end,
      fn
        nil -> {:cont, nil}
        run -> {:cont, run, nil}
      end
    )
    |> Enum.reject(&is_nil/1)
  end

  # ---- maintenance -------------------------------------------------------------

  @doc """
  Build the next rollup (see the module documentation). Returns
  `{:ok, %{from: start | nil, ...}}` or `{:error, reason}`.
  """
  def roll(tenant, config, opts \\ []) do
    Pulse.Metrics.measure(:compaction, "log_rollup", fn -> do_roll(tenant, config, opts) end, fn
      {:ok, %{sources: count}} -> %{segments: count}
      _ -> %{}
    end)
  end

  defp do_roll(tenant, config, opts) do
    with :ok <- S3.validate_tenant(tenant),
         :ok <- NIF.ensure_metric_tier_api!(),
         {:ok, root, _etag} <- Retention.load(tenant, "logs", config) do
      if root.version == 3,
        do: {:ok, %{from: nil, reason: :retention_managed}},
        else: roll_root(root, tenant, config, opts)
    end
  end

  defp roll_root(root, tenant, config, opts) do
    now = System.os_time(:nanosecond)
    to = Integer.floor_div(now - Keyword.get(opts, :settle_ms, 30_000) * 1_000_000, @minute) * @minute
    from = Integer.floor_div(now - Keyword.get(opts, :lookback_ms, 7_200_000) * 1_000_000, @hour) * @hour

    with {:ok, raws} <- segments(root, from + 1, to, [], tenant, config),
         {:ok, rollups} <- segments(root, from + 1, to, [log_rollups: true], tenant, config) do
      case next_build(raws, rollups, from, to, opts) do
        nil -> {:ok, %{from: nil}}
        work -> run(tenant, config, work, opts)
      end
    end
  end

  defp segments(root, start, finish, extra, tenant, config) do
    opts = Keyword.merge([start_ts: start, end_ts: finish], extra)

    case root.version do
      4 -> JournalManifest.query(root, tenant, "logs", opts, config)
      _ -> {:ok, root |> Manifest.prune_by_time(start, finish) |> Enum.filter(&Segment.matches_log_service?(&1, opts))}
    end
  end

  # The oldest hour needing work: unanswered minutes whose segments all have
  # known counts are rolled up (at most `:max_rows` source rows at a time);
  # a settled hour answered by several rollups is merged into one.
  defp next_build(raws, rollups, from, to, opts) do
    skip = Keyword.get(opts, :skip, MapSet.new())

    from
    |> Stream.iterate(&(&1 + @hour))
    |> Enum.take_while(&(&1 < to))
    |> Enum.find_value(fn hour ->
      finish = min(hour + @hour, to)
      in_hour = Enum.filter(rollups, &(&1.min_ts > hour and &1.max_ts <= hour + @hour))
      hraws = Enum.filter(raws, &overlaps?(&1, hour + 1, finish))
      plan = plan(hraws, in_hour, hour + 1, hour + 1, finish)

      gaps =
        plan.gaps
        |> Enum.flat_map(fn {a, b} -> Enum.to_list(Segment.log_minute(a)..Segment.log_minute(b)//1) end)
        |> Enum.reject(&MapSet.member?(skip, &1))
        |> Enum.filter(&buildable?(&1, hraws))

      cond do
        gaps != [] -> {:build, take_minutes(gaps, hraws, Keyword.get(opts, :max_rows, 4_000_000))}
        finish == hour + @hour and length(in_hour) > 1 -> {:merge, hour, in_hour, plan.rollups}
        true -> nil
      end
    end)
  end

  defp buildable?(minute, raws) do
    {a, b} = {(minute - 1) * @minute + 1, minute * @minute}
    Enum.all?(raws, &(not overlaps?(&1, a, b) or is_map(&1.log_minutes)))
  end

  # Gap minutes in order while their segments' rows fit `max_rows`; the
  # first minute is always taken. Segments without counts (written before
  # 1.33) hold no line of a buildable minute (`buildable?/2`).
  defp take_minutes(minutes, raws, max_rows) do
    raws = Enum.filter(raws, &is_map(&1.log_minutes))

    {taken, sources, _rows} =
      Enum.reduce_while(minutes, {[], %{}, 0}, fn minute, {taken, sources, rows} ->
        new = for s <- raws, Map.has_key?(s.log_minutes, minute), not Map.has_key?(sources, s.key), do: s
        added = Enum.sum_by(new, &(&1.row_count || 0))

        if taken != [] and rows + added > max_rows,
          do: {:halt, {taken, sources, rows}},
          else: {:cont, {[minute | taken], Enum.into(new, sources, &{&1.key, &1}), rows + added}}
      end)

    {Enum.reverse(taken), Map.values(sources)}
  end

  defp overlaps?(segment, a, b),
    do:
      not (is_integer(segment.max_ts) and segment.max_ts < a) and
        not (is_integer(segment.min_ts) and segment.min_ts > b)

  defp run(tenant, config, {:build, {minutes, sources}}, opts) do
    {first, last} = Enum.min_max(minutes)
    start = (first - 1) * @minute + 1
    buckets = Enum.map(minutes, &(&1 * @minute))

    case produce(tenant, config, start, last * @minute, buckets, Enum.map(sources, &{&1, []}), [], opts) do
      {:ok, result} -> {:ok, Map.put(result, :minutes, length(minutes))}
      {:error, reason} -> {:error, {first, reason}}
    end
  end

  defp run(tenant, config, {:merge, hour, replaced, chosen}, opts) do
    buckets = Enum.flat_map(chosen, &elem(&1, 1))
    # Each rollup contributes only the minutes it validly answers.
    inputs = Enum.map(chosen, fn {rollup, minutes} -> {rollup, minutes} end)

    case produce(tenant, config, hour + 1, hour + @hour, buckets, inputs, replaced, opts) do
      {:ok, result} -> {:ok, Map.put(result, :merged, length(replaced))}
      {:error, reason} -> {:error, {Segment.log_minute(hour + 1), reason}}
    end
  end

  defp produce(tenant, config, start, finish, buckets, inputs, replaced, opts) do
    builder = NIF.log_rollup_new(start, finish, buckets)

    with :ok <- add_inputs(builder, config, inputs, opts),
         {:ok, payload, cells, totals} <- finish(builder),
         {:ok, segment} <- upload(tenant, config, payload, cells, totals, start, finish),
         :ok <- publish(tenant, config, segment, replaced, opts) do
      {:ok, %{from: start, to: finish, sources: length(inputs), rows: cells}}
    end
  end

  defp add_inputs(builder, config, inputs, opts) do
    inputs
    |> Pulse.Runtime.Task.async_stream(fn {segment, buckets} -> {ObjectCache.get(config, segment.key), buckets} end,
      max_concurrency: Keyword.get(opts, :concurrency, 8),
      ordered: false,
      timeout: :infinity
    )
    |> Enum.reduce_while(:ok, fn
      # Segments come with no bucket list; rollups with the buckets they give.
      {:ok, {{:ok, blob}, buckets}}, :ok ->
        case NIF.log_rollup_add(builder, blob, buckets == [], buckets) do
          {:ok, _rows} -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
          :fallback -> {:halt, {:error, :unsupported_log_rows}}
        end

      {:ok, {{:error, _} = error, _}}, :ok ->
        {:halt, error}
    end)
  end

  defp finish(builder) do
    case NIF.log_rollup_finish(builder, []) do
      {:ok, payload, cells, totals} -> {:ok, payload, cells, totals}
      {:error, _} = error -> error
      :fallback -> {:error, {:encode_failed, :log_rollup_rejected}}
    end
  end

  defp upload(tenant, config, payload, cells, totals, start, finish) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    key = S3.object_key(tenant, "logs", start, finish, suffix, nil)
    key = Path.join(Path.dirname(key), String.replace(Path.basename(key), "-rand-", "-rollup-"))
    minutes = Map.new(totals, fn {bucket, count} -> {div(bucket, @minute), count} end)
    segment = %{Segment.build(key, start, finish, cells, byte_size(payload)) | log_minutes: minutes}

    case ObjectStore.put(config, key, payload) do
      {:ok, _etag} ->
        ObjectCache.put(key, payload)
        {:ok, segment}

      error ->
        error
    end
  end

  defp publish(tenant, config, segment, [], _opts) do
    case ManifestOwner.register_segments(tenant, "logs", [segment], config) do
      :ok -> :ok
      error -> error
    end
  end

  defp publish(tenant, config, segment, replaced, opts) do
    grace = Keyword.get(opts, :grace_ms, 3_600_000)

    case MetricTiers.publish(tenant, config, Enum.map(replaced, & &1.key), [segment], grace, "logs") do
      :ok ->
        :ok

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
end
