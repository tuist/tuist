defmodule Pulse.Storage.S3.TraceCompactor do
  @moduledoc """
  Native trace compaction through shared signal maintenance.

  On flat and format-4 manifests each call rewrites one batch of an hour's
  settled ingested segments, oldest first, together with the hour's outputs
  that are not full yet. The native merge splits the rows into outputs that
  each hold one service, one class (spans with error status or events, or
  the others) and at most `:max_ids` (256) trace IDs in start order
  (`:max_flagged_ids`, 1024, for the error/event class that TraceQL metrics read). Each
  output's manifest summary therefore lists its exact trace-ID hashes, its
  services and attribute value sets, its status codes and whether any span
  has an event, so service, attribute, error, event and trace-ID lookups
  read only the outputs that can hold their rows. Outputs are published in
  one conditional manifest transition and the sources retire with the usual
  grace, backup hold and cleanup (`Pulse.Storage.S3.SignalCompactor`).

  Bounded partial-only batches finish consolidation after fresh inputs run out,
  publishing only when object count decreases. Failed or unproductive immutable
  sets are deferred node-locally for an hour, never their whole hour or individual
  sources. Alternative batches retain the same input/native limits.

  Bucketed (format-3) retention prefixes keep the single-output merge of
  `SignalCompactor`. Retention, retirement cleanup and orphan reclamation are
  shared with logs and metrics.

  Options: `:settle_ms` (30_000), `:max_sources` (512), `:max_rows` (60_000),
  `:max_input_bytes` (32 MiB), `:max_ids` (256), `:max_flagged_ids` (1024),
  `:max_output_rows` (20_000),
  `:small_segment_bytes` (1 MiB), `:grace_ms` (3_600_000).
  """

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.MetadataCache
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.ObjectCache
  alias Pulse.Storage.S3.Retention
  alias Pulse.Storage.S3.SignalCompactor
  alias Pulse.Storage.S3.TraceAttributeSummary
  alias Pulse.Storage.S3.TraceSummary

  @hour_ns 3_600_000_000_000

  def maintain(tenant, config, opts \\ []), do: compact(tenant, config, opts)

  def compact(tenant, config, opts \\ []) do
    config = Map.put(config, :compaction_signal, :traces)

    with :ok <- S3.validate_tenant(tenant),
         {:ok, root, _etag} <- Retention.load(tenant, "traces", config) do
      compact_root(root.version == 3 or Retention.bucketed?(config, "traces"), root, tenant, config, opts)
    end
  end

  defp compact_root(true, _root, tenant, config, opts) do
    if opts[:min_hour],
      do: {:ok, %{merged: 0}},
      else: SignalCompactor.compact(tenant, config, opts)
  end

  defp compact_root(false, root, tenant, config, opts),
    do: SignalCompactor.monitor(:compact, fn -> split(root, tenant, config, opts) end)

  def cleanup(tenant, config, opts \\ []),
    do: SignalCompactor.cleanup(tenant, Map.put(config, :compaction_signal, :traces), opts)

  defp split(root, tenant, config, opts) do
    with {:ok, candidates} <- candidates(root, tenant, config),
         do: merge_batch(select(candidates.segments, opts), root, candidates, tenant, config, opts)
  end

  defp merge_batch(nil, root, candidates, tenant, config, opts) do
    # A recent-only pass did not process the historical window. Only the
    # historical lane may advance it, or alternating passes can skip leaves.
    advance = if opts[:min_hour], do: :ok, else: SignalCompactor.advance_empty_cursor(root, candidates, tenant, config)

    with :ok <- advance,
         do: {:ok, %{segments_before: length(root.segments), merged: 0}}
  end

  defp merge_batch(sources, _root, _candidates, tenant, config, opts), do: merge(sources, tenant, config, opts)

  defp candidates(%{version: 4} = root, tenant, config), do: JournalManifest.candidates(root, tenant, "traces", config)
  defp candidates(root, _tenant, _config), do: {:ok, root}

  @doc false
  # The next batch: the oldest settled ingested segments of the oldest hour
  # holding any, within the input bounds, plus that hour's outputs that are
  # not full. Once fresh inputs are exhausted, bounded partial-only batches
  # finish consolidation, but are published only if they reduce object count.
  def select(segments, opts) do
    settled_before = System.os_time(:nanosecond) - Keyword.get(opts, :settle_ms, 30_000) * 1_000_000

    segments
    |> Enum.filter(&eligible?(&1, settled_before))
    |> Enum.group_by(&hour(&1.min_ts))
    |> Enum.filter(fn {hour, _segments} ->
      (is_nil(opts[:min_hour]) or hour >= opts[:min_hour]) and
        (is_nil(opts[:max_hour]) or hour <= opts[:max_hour])
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(fn {_hour, segments} -> hour_batch(segments, opts) end)
  end

  defp hour_batch(segments, opts) do
    {fresh, partial} = Enum.split_with(segments, &(class(&1, opts) == :fresh))
    partial = partial |> Enum.filter(&(class(&1, opts) == :partial)) |> Enum.sort_by(&order/1) |> Enum.take(64)

    # Prefer fresh sources, but skip non-fitting inputs rather than allowing
    # an oversized source to hide healthy inputs later in the candidate set.
    find_batch(Enum.sort_by(fresh, &order/1) ++ partial, opts)
  end

  defp find_batch([], _opts), do: nil

  defp find_batch(sources, opts) do
    sources
    |> take({0, 0, 0}, opts)
    |> Enum.reverse()
    |> case do
      [] ->
        nil

      [_single] ->
        # A source can fit alone yet leave no room for any partner. Search
        # the bounded candidate pool for a pair rather than keeping it pinned.
        find_pair(sources, opts)

      batch ->
        # Deferral applies only to this exact immutable set, including when
        # every source is a partial output. A different pair may still reduce
        # fragmentation (or fit the decoded native budget).
        if batch_deferred?(batch, opts), do: find_pair(sources, opts), else: batch
    end
  end

  defp find_pair(sources, opts) do
    minimum_rows = sources |> Enum.min_by(& &1.row_count) |> Map.fetch!(:row_count)
    minimum_bytes = sources |> Enum.min_by(& &1.byte_size) |> Map.fetch!(:byte_size)
    maximum_rows = Keyword.get(opts, :max_rows, 60_000)
    maximum_bytes = Keyword.get(opts, :max_input_bytes, 32 * 1024 * 1024)

    # These independent lower bounds can only exclude impossible partners.
    # Avoid quadratic scans through sources that consume the whole budget.
    sources
    |> Enum.filter(fn source ->
      source.row_count + minimum_rows <= maximum_rows and
        source.byte_size + minimum_bytes <= maximum_bytes
    end)
    |> find_pair_in(opts)
  end

  defp find_pair_in([], _opts), do: nil

  defp find_pair_in([first | rest], opts) do
    maximum_rows = Keyword.get(opts, :max_rows, 60_000)
    maximum_bytes = Keyword.get(opts, :max_input_bytes, 32 * 1024 * 1024)

    if Keyword.get(opts, :max_sources, 512) >= 2 do
      partner =
        Enum.find(rest, fn second ->
          first.row_count + second.row_count <= maximum_rows and
            first.byte_size + second.byte_size <= maximum_bytes and
            not batch_deferred?([first, second], opts)
        end)

      if partner, do: [first, partner], else: find_pair_in(rest, opts)
    end
  end

  defp order(segment), do: {segment.min_ts, segment.max_ts, segment.key}

  defp take(segments, used, opts) do
    max_sources = Keyword.get(opts, :max_sources, 512)
    max_rows = Keyword.get(opts, :max_rows, 60_000)
    max_bytes = Keyword.get(opts, :max_input_bytes, 32 * 1024 * 1024)

    segments
    |> Enum.reduce_while({[], used}, fn s, {acc, {count, rows, bytes}} ->
      cond do
        count >= max_sources ->
          {:halt, {acc, {count, rows, bytes}}}

        rows + s.row_count <= max_rows and bytes + s.byte_size <= max_bytes ->
          {:cont, {[s | acc], {count + 1, rows + s.row_count, bytes + s.byte_size}}}

        true ->
          {:cont, {acc, {count, rows, bytes}}}
      end
    end)
    |> elem(0)
  end

  defp eligible?(s, settled_before) do
    is_integer(s.byte_size) and s.byte_size > 0 and is_integer(s.row_count) and s.row_count > 0 and
      is_integer(s.min_ts) and is_integer(s.max_ts) and s.max_ts <= settled_before and Segment.key_tier(s.key) == :raw
  end

  # Ingested segments and the large merges of earlier releases are fresh;
  # outputs below three quarters of the ID and row bounds are partial.
  defp class(s, opts) do
    base = Path.basename(s.key)
    small? = s.byte_size <= Keyword.get(opts, :small_segment_bytes, 1024 * 1024)

    cond do
      String.contains?(base, "-rand-") or String.contains?(base, "-idem-") -> :fresh
      not String.contains?(base, "-compact-") -> :other
      not small? -> :full
      ids(s) == nil -> :fresh
      ids(s) * 4 < id_cap(s, opts) * 3 and s.row_count * 4 < max_output_rows(opts) * 3 -> :partial
      true -> :full
    end
  end

  defp ids(%{trace_summary: %TraceSummary{lookup_hashes: hashes}}) when is_binary(hashes), do: div(byte_size(hashes), 8)
  defp ids(_segment), do: nil

  defp id_cap(%{trace_summary: %TraceSummary{statuses: statuses, events?: events?}}, opts) when is_list(statuses),
    do:
      if(2 in statuses or events?,
        do: Keyword.get(opts, :max_flagged_ids, 1024),
        else: Keyword.get(opts, :max_ids, 256)
      )

  defp id_cap(_segment, opts), do: Keyword.get(opts, :max_ids, 256)

  defp max_output_rows(opts), do: Keyword.get(opts, :max_output_rows, 20_000)
  defp hour(ts), do: Integer.floor_div(ts, @hour_ns) * @hour_ns

  defp merge(sources, tenant, config, opts) do
    # Bound the entire operation, not just each native attempt: at most 16
    # builds and three times the original batch's source count/encoded bytes.
    budget = {16, 3 * length(sources), 3 * Enum.sum_by(sources, & &1.byte_size)}
    merge_batches([sources], tenant, config, opts, budget, {:ok, %{merged: 0}})
  end

  defp merge_batches([], _tenant, _config, _opts, _budget, result), do: result
  defp merge_batches(_batches, _tenant, _config, _opts, {0, _, _}, result), do: result

  defp merge_batches([sources | rest], tenant, config, opts, {attempts, count, bytes} = budget, result) do
    source_count = length(sources)
    source_bytes = Enum.sum_by(sources, & &1.byte_size)

    if source_count > count or source_bytes > bytes or batch_deferred?(sources, opts) do
      merge_batches(rest, tenant, config, opts, budget, result)
    else
      remaining = {attempts - 1, count - source_count, bytes - source_bytes}
      merge_attempt(sources, rest, tenant, config, opts, remaining)
    end
  end

  defp merge_attempt(sources, rest, tenant, config, opts, remaining) do
    case build(sources, tenant, config, opts) do
      {:ok, outputs} ->
        publish(sources, outputs, tenant, config, opts)

      :unchanged ->
        defer_batch(sources, opts)
        merge_batches(rest, tenant, config, opts, remaining, {:ok, %{merged: 0}})

      # Try both halves and a cross-pair with a different partner for the
      # oldest source. Failure of a pair proves neither source individually
      # unmergeable. All retries share the operation's remaining budget.
      {:error, :payload_too_large} = error ->
        defer_batch(sources, opts)
        half = div(length(sources), 2)

        alternatives =
          if length(sources) > 2,
            do: [Enum.take(sources, max(2, half)), [hd(sources), List.last(sources)], Enum.drop(sources, half)],
            else: []

        result = if partial_batch?(sources, opts), do: {:ok, %{merged: 0}}, else: error
        merge_batches(alternatives ++ rest, tenant, config, opts, remaining, result)

      {:error, reason} = error
      when reason in [:trace_projection_invalid, :segment_summary_mismatch, :invalid_segment] ->
        # Leave every source active; the exact failed batch is a local hint,
        # not authority to exclude unrelated sources from the same hour.
        defer_batch(sources, opts)
        merge_batches(rest, tenant, config, opts, remaining, error)

      error ->
        error
    end
  end

  defp build(sources, tenant, config, opts) do
    with :ok <- validate_sources(tenant, sources),
         {:ok, blobs} <- read(config, sources) do
      max_rows = min(Keyword.get(opts, :max_rows, 60_000), 100_000)

      ids = Keyword.get(opts, :max_ids, 256)
      flagged = Keyword.get(opts, :max_flagged_ids, 1024)
      partial? = partial_batch?(sources, opts)

      case NIF.compact_trace_segments_split(blobs, max_rows, ids, flagged, max_output_rows(opts)) do
        {:ok, outputs} when partial? and length(outputs) >= length(sources) ->
          :unchanged

        {:ok, outputs} ->
          upload(outputs, tenant, config)

        {:error, :query_sample_limit} ->
          {:error, :payload_too_large}

        {:error, _} = error ->
          error

        _ ->
          {:error, :invalid_segment}
      end
    end
  end

  defp validate_sources(tenant, sources) do
    scope = "tenants/#{tenant}/v4/signal=traces/"

    if Enum.all?(sources, &(String.starts_with?(&1.key, scope) and String.ends_with?(&1.key, ".parquet"))),
      do: :ok,
      else: {:error, :invalid_segment_key}
  end

  # Eight GETs at a time, each checked against its manifest size and rows.
  defp read(config, sources) do
    sources
    |> Pulse.Runtime.Task.async_stream(&{&1, ObjectCache.get(config, &1.key)}, max_concurrency: 8, timeout: :infinity)
    |> Enum.reduce_while({:ok, []}, fn {:ok, {source, fetched}}, {:ok, blobs} ->
      with {:ok, blob} <- fetched,
           true <- byte_size(blob) == source.byte_size,
           {:ok, count} when count == source.row_count <- NIF.trace_segment_parquet_row_count(blob) do
        {:cont, {:ok, [blob | blobs]}}
      else
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, {:error, :segment_summary_mismatch}}
      end
    end)
    |> case do
      {:ok, blobs} -> {:ok, Enum.reverse(blobs)}
      error -> error
    end
  end

  defp upload(outputs, tenant, config) do
    segments = Enum.map(outputs, &output_segment(&1, tenant))

    outputs
    |> Enum.zip(segments)
    |> Pulse.Runtime.Task.async_stream(
      fn {{blob, _, _, _, _, _}, segment} ->
        with {:ok, _} = ok <- ObjectStore.put(config, segment.key, blob) do
          ObjectCache.put(segment.key, blob)
          ok
        end
      end,
      max_concurrency: 8,
      timeout: :infinity
    )
    |> Enum.find(&(not match?({:ok, {:ok, _}}, &1)))
    |> case do
      nil ->
        {:ok, segments}

      {:ok, error} ->
        discard(config, segments)
        error
    end
  end

  defp output_segment({blob, min_ts, max_ts, rows, {services, ids, proof}, {statuses, events, resource, span}}, tenant) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    key = S3.object_key(tenant, "traces", min_ts, max_ts, suffix, nil)
    key = Path.join(Path.dirname(key), String.replace(Path.basename(key), "-rand-", "-compact-"))
    summary = TraceSummary.from_values(services, ids, proof, {statuses, events}, 1024)

    key
    |> Segment.build(min_ts, max_ts, rows, byte_size(blob))
    |> Map.put(:trace_summary, %{summary | attributes: TraceAttributeSummary.from_native(resource, span)})
  end

  defp publish(sources, outputs, tenant, config, opts) do
    grace = Keyword.get(opts, :grace_ms, 3_600_000)

    case MetricTiers.publish(tenant, config, Enum.map(sources, & &1.key), outputs, grace, "traces") do
      :ok ->
        {:ok, %{merged: length(sources), outputs: length(outputs), replacements: Enum.map(outputs, & &1.key)}}

      # A fresh manifest proved these unique keys were never published.
      {:error, reason} = error when reason in [:compaction_conflict, :cas_retries_exhausted] ->
        discard(config, outputs)
        error

      {:error, {:unpublished, reason}} ->
        discard(config, outputs)
        {:error, reason}

      # Ambiguous failures keep their uploads: the manifest may reference them.
      error ->
        error
    end
  end

  defp discard(config, segments), do: Enum.each(segments, &ObjectStore.delete(config, &1.key))

  defp partial_batch?(sources, opts), do: Enum.all?(sources, &(class(&1, opts) == :partial))

  defp batch_ref(sources, opts) do
    limits = opts |> Keyword.take([:max_rows, :max_ids, :max_flagged_ids, :max_output_rows]) |> Enum.sort()
    digest = :crypto.hash(:sha256, :erlang.term_to_binary({Enum.map(sources, & &1.key), limits}))
    %{"k" => "trace-batch:" <> Base.encode16(digest, case: :lower), "b" => 1}
  end

  defp defer_batch(sources, opts),
    do: MetadataCache.put(batch_ref(sources, opts), System.monotonic_time(:millisecond) + 3_600_000)

  defp batch_deferred?(sources, opts) do
    case MetadataCache.get(batch_ref(sources, opts)) do
      {:ok, until} -> until > System.monotonic_time(:millisecond)
      :miss -> false
    end
  end
end
