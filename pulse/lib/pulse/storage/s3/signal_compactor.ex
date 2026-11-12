defmodule Pulse.Storage.S3.SignalCompactor do
  @moduledoc """
  Bounded signal compaction and restart-safe cleanup.

  `compact/3` merges at most one hour's small segments per call. Readers and
  ingesters keep running while native codecs merge data.
  The replacement is uploaded before a conditional manifest update. Conflicts
  reload the manifest and preserve concurrent appends; overlapping compactions
  fail rather than publish the same samples twice.

  Retired keys and wall-clock deletion deadlines live in the manifest. Cleanup
  is repeatable across nodes and restarts. Tombstones are retained permanently
  to preserve ingest idempotency. The default grace period is one hour; queries
  overtaken by cleanup restart against the current manifest.

  Segments whose newest record is younger than `:settle_ms` are left alone;
  log compaction sets it so live tail followers read every live segment
  before it is merged (`Pulse.Loki.TailFollower`).

  Options: `:max_segments` (32), `:max_input_bytes` (8 MiB), `:max_rows`
  (100_000), `:small_segment_bytes` (1 MiB), `:settle_ms` (0), `:grace_ms` (3_600_000).
  Unknown segment sizes/counts are skipped rather than bypassing the bounds.
  """

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.MetadataCache
  alias Pulse.Storage.S3.ObjectCache
  alias Pulse.Storage.S3.PagedManifest
  alias Pulse.Storage.S3.Retention
  alias Pulse.Storage.S3.TraceAttributeSummary
  alias Pulse.Storage.S3.TraceSummary

  def compact(tenant, config, opts \\ []) do
    monitor(:compact, fn -> do_compact(tenant, config, opts) end)
  end

  defp do_compact(tenant, config, opts) do
    with :ok <- S3.validate_tenant(tenant),
         :ok <- validate_options(opts),
         {:ok, manifest, _etag} <- load(tenant, config),
         :ok <- migration_gate(manifest, config),
         :ok <- validate_retained_grace(manifest, config, opts),
         {:ok, candidates} <- compaction_candidates(manifest, tenant, config) do
      mergeable = %{candidates | segments: Enum.reject(candidates.segments, &unmergeable?(&1.key))}
      compact_mergeable(mergeable, candidates, manifest, tenant, config, opts, {3, nil})
    end
  end

  # A merge whose sources cannot fit together (log text can decode to many
  # times its stored size) sets them aside and selects again, a few times per
  # call, so one oversized group never stops the prefix's other merges. When
  # nothing else merges, the call still reports the oversized group's error.
  defp compact_mergeable(mergeable, candidates, manifest, tenant, config, opts, {attempts, failure}) do
    case select(mergeable, opts) do
      [] ->
        with :ok <- advance_empty_cursor(manifest, candidates, tenant, config),
             do: failure || {:ok, %{segments_before: length(manifest.segments), merged: 0}}

      sources ->
        case merge_and_publish(tenant, config, manifest, sources, opts) do
          {:error, :payload_too_large} = error when attempts > 1 ->
            keys = MapSet.new(sources, & &1.key)
            rest = %{mergeable | segments: Enum.reject(mergeable.segments, &MapSet.member?(keys, &1.key))}
            compact_mergeable(rest, candidates, manifest, tenant, config, opts, {attempts - 1, failure || error})

          # Rotation is only an optimization. Never mask the original failure if a
          # competing writer prevents progress; publication remains independently CAS-fenced.
          {:error, _} = error ->
            advance_empty_cursor(manifest, candidates, tenant, config)
            error

          result ->
            result
        end
    end
  end

  @doc false
  def select(manifest, opts) do
    max_segments = Keyword.get(opts, :max_segments, 32)
    max_bytes = Keyword.get(opts, :max_input_bytes, 8 * 1024 * 1024)
    max_rows = Keyword.get(opts, :max_rows, 100_000)
    small_bytes = Keyword.get(opts, :small_segment_bytes, 1024 * 1024)
    settle_ns = Keyword.get(opts, :settle_ms, 0) * 1_000_000
    settled_before = System.os_time(:nanosecond) - settle_ns

    manifest.segments
    |> Enum.filter(&(mergeable?(&1, small_bytes) and settled?(&1, settle_ns, settled_before)))
    |> Enum.group_by(fn s ->
      if manifest.version == 3, do: PagedManifest.bucket_start(manifest.paging, s.max_ts), else: Path.dirname(s.key)
    end)
    |> Enum.sort_by(fn {hour, _} -> hour end)
    |> Enum.find_value([], fn {_hour, segments} ->
      segments
      |> Enum.sort_by(&{&1.row_count, &1.byte_size, &1.key})
      |> select_group(max_segments, max_bytes, max_rows, 32)
    end)
  end

  # Finalized segments and rollups are rewritten only by hour finalization.
  defp mergeable?(s, small_bytes) do
    is_integer(s.byte_size) and s.byte_size > 0 and s.byte_size <= small_bytes and
      is_integer(s.row_count) and s.row_count > 0 and Segment.key_tier(s.key) == :raw
  end

  defp settled?(_s, 0, _settled_before), do: true
  defp settled?(s, _settle_ns, settled_before), do: is_integer(s.max_ts) and s.max_ts <= settled_before

  # Try a bounded number of starting points: a full-sized replacement at the
  # front must not prevent smaller original segments from being merged.
  defp select_group([], _max_segments, _max_bytes, _max_rows, _attempts), do: nil
  defp select_group(_segments, _max_segments, _max_bytes, _max_rows, 0), do: nil

  defp select_group([_first | rest] = segments, max_segments, max_bytes, max_rows, attempts) do
    {selected, _, _} = Enum.reduce(segments, {[], 0, 0}, &select_segment(&1, &2, max_segments, max_bytes, max_rows))

    if length(selected) >= 2 do
      Enum.reverse(selected)
    else
      select_group(rest, max_segments, max_bytes, max_rows, attempts - 1)
    end
  end

  defp select_segment(segment, {selected, bytes, rows} = acc, max_segments, max_bytes, max_rows) do
    if length(selected) < max_segments and bytes + segment.byte_size <= max_bytes and
         rows + segment.row_count <= max_rows do
      {[segment | selected], bytes + segment.byte_size, rows + segment.row_count}
    else
      acc
    end
  end

  defp merge_and_publish(tenant, config, manifest, sources, opts) do
    with :ok <- validate_sources(tenant, sources, config),
         {:ok, records} <- read_sources(config, sources),
         {:ok, payload, min_ts, max_ts, row_count, summary, sources} <-
           encode_replacement(config, records, sources, opts) do
      # A distinct suffix prevents prefix migration from adopting an unpublished
      # replacement after a crash. A manifest must exist before compaction starts.
      suffix = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
      original_key = S3.object_key(tenant, signal_string(config), min_ts, max_ts, suffix, nil)
      key = Path.join(Path.dirname(original_key), String.replace(Path.basename(original_key), "-rand-", "-compact-"))

      replacement =
        key
        |> Segment.build(min_ts, max_ts, row_count, byte_size(payload))
        |> summarize_replacement(config, records, summary)
        |> merge_source_summaries(config, sources)

      source_keys = Enum.map(sources, & &1.key)
      grace = Keyword.get(opts, :grace_ms, 3_600_000)

      with {:ok, _etag} <- ObjectStore.put(config, key, payload),
           :ok <- ObjectCache.put(key, payload),
           :ok <- publish_replacement(tenant, config, source_keys, replacement, grace) do
        {:ok, %{segments_before: length(manifest.segments), merged: length(sources), replacement: key}}
      end

      # Ambiguous publications retain their upload: the manifest may reference it.
      # Definitive conflicts are reclaimed by publish_replacement/5.
    else
      # Log merges choose the subset that fits themselves (merge_logs/2).
      {:error, reason} = error when reason in [:payload_too_large, :query_sample_limit] ->
        if length(sources) > 2 and not (reason == :payload_too_large and signal(config) == :logs) do
          # Encoding failed before any upload. Shrink the source set, never
          # truncate rows. A compressed-byte estimate cannot bound metadata.
          merge_and_publish(tenant, config, manifest, Enum.take(sources, max(2, div(length(sources), 2))), opts)
        else
          error
        end

      error ->
        error
    end
  end

  defp publish_replacement(tenant, config, sources, replacement, grace) do
    case publish(tenant, config, sources, replacement, grace) do
      {:error, {:unpublished_replacement, reason}} ->
        discard_replacement(config, replacement, {:error, reason})

      {:error, reason} = error when reason in [:compaction_conflict, :cas_retries_exhausted] ->
        # A fresh manifest proved this unique key was never published. Unlike
        # network failures, this definitive loss is safe to clean up immediately.
        discard_replacement(config, replacement, error)

      result ->
        result
    end
  end

  defp discard_replacement(config, replacement, error) do
    case ObjectStore.delete(config, replacement.key) do
      :ok -> error
      {:error, :not_found} -> error
      {:error, reason} -> {:error, {:replacement_cleanup_failed, replacement.key, reason}}
    end
  end

  defp signal(config), do: Map.get(config, :compaction_signal, :metrics)
  defp signal_string(config), do: Atom.to_string(signal(config))

  defp validate_sources(tenant, sources, config) do
    if signal(config) in [:metrics, :logs, :traces] and Enum.all?(sources, &valid_segment_key?(tenant, &1.key, config)),
      do: :ok,
      else: {:error, :invalid_segment_key}
  end

  defp valid_segment_key?(tenant, key, config) do
    String.starts_with?(key, "tenants/#{tenant}/v4/signal=#{signal_string(config)}/") and
      String.ends_with?(key, ".parquet") and
      Enum.all?(String.split(key, "/"), &(&1 not in [".", ".."]))
  end

  # Sources are fetched eight at a time: one GET each at object-store latency
  # otherwise dominates a merge. They stay within the merge's input bounds.
  defp read_sources(config, sources) do
    sources
    |> Pulse.Runtime.Task.async_stream(&{&1, ObjectCache.get(config, &1.key)}, max_concurrency: 8, timeout: :infinity)
    |> Enum.reduce_while({:ok, []}, fn {:ok, {source, fetched}}, {:ok, batches} ->
      with {:ok, blob} <- fetched,
           true <- byte_size(blob) == source.byte_size,
           {:ok, records} <- read_records(config, blob, source.row_count) do
        {:cont, {:ok, [records | batches]}}
      else
        false -> {:halt, {:error, :segment_summary_mismatch}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, batches} -> {:ok, batches |> Enum.reverse() |> List.flatten()}
      error -> error
    end
  end

  defp read_records(%{compaction_signal: :traces}, blob, count) do
    case NIF.trace_segment_parquet_row_count(blob) do
      {:ok, ^count} -> {:ok, [blob]}
      _ -> {:error, :segment_summary_mismatch}
    end
  end

  defp read_records(%{compaction_signal: :logs}, blob, count) do
    case NIF.log_segment_parquet_row_count(blob) do
      {:ok, ^count} -> {:ok, [blob]}
      _ -> {:error, :segment_summary_mismatch}
    end
  end

  defp read_records(config, blob, count) do
    with {:ok, records} <- S3.decode_segment(signal(config), blob, nil, nil, []) do
      if length(records) == count, do: {:ok, records}, else: {:error, :segment_summary_mismatch}
    end
  end

  defp encode_replacement(%{compaction_signal: :traces}, blobs, sources, opts) do
    case NIF.compact_trace_segments_v2(blobs, min(100_000, Keyword.get(opts, :max_rows, 100_000))) do
      {:ok, payload, min, max, count, {services, ids, proof}} ->
        {:ok, payload, min, max, count, TraceSummary.from_values(services, ids, proof), sources}

      {:error, _} = error ->
        error

      _ ->
        {:error, {:encode_failed, :parquet_encoder_rejected_input}}
    end
  end

  defp encode_replacement(%{compaction_signal: :logs}, blobs, sources, opts),
    do: merge_logs(Enum.zip(blobs, sources), min(100_000, Keyword.get(opts, :max_rows, 100_000)))

  defp encode_replacement(_config, records, sources, _opts) do
    with {:ok, payload, min, max} <- S3.encode_segment(:metrics, records),
         do: {:ok, payload, min, max, length(records), nil, sources}
  end

  # Selection bounds compressed bytes, but the native merge bounds decoded
  # strings (32 MiB), and log text often compresses tenfold or more. The merge
  # takes the sources that fit, in order, and reports which; it needs two. A
  # source that pairs with none of the others is set aside and the rest are
  # tried again from the blobs already read. Sources left without any partner
  # are remembered node-locally, so later passes select other merges instead
  # of reading and failing on the same ones every interval.
  defp merge_logs(pairs, _max_rows) when length(pairs) < 2 do
    Enum.each(pairs, fn {_blob, source} -> remember_unmergeable(source.key) end)
    {:error, :payload_too_large}
  end

  defp merge_logs(pairs, max_rows) do
    case NIF.compact_log_segments(Enum.map(pairs, &elem(&1, 0)), max_rows) do
      {:ok, payload, min, max, count, services, included} when length(included) >= 2 ->
        {:ok, payload, min, max, count, services, Enum.map(included, &elem(Enum.at(pairs, &1), 1))}

      {:ok, _payload, _min, _max, _count, _services, [alone]} ->
        {_blob, source} = Enum.at(pairs, alone)
        remember_unmergeable(source.key)
        merge_logs(List.delete_at(pairs, alone), max_rows)

      # No source fits even alone.
      {:error, :payload_too_large} ->
        Enum.each(pairs, fn {_blob, source} -> remember_unmergeable(source.key) end)
        {:error, :payload_too_large}

      {:error, _} = error ->
        error

      _ ->
        {:error, {:encode_failed, :parquet_encoder_rejected_input}}
    end
  end

  @unmergeable_ms 3_600_000
  defp unmergeable_ref(key), do: %{"k" => "unmergeable:" <> key, "b" => 1}

  defp remember_unmergeable(key),
    do: MetadataCache.put(unmergeable_ref(key), System.monotonic_time(:millisecond) + @unmergeable_ms)

  defp unmergeable?(key) do
    case MetadataCache.get(unmergeable_ref(key)) do
      {:ok, until} -> until > System.monotonic_time(:millisecond)
      :miss -> false
    end
  end

  defp summarize_replacement(segment, %{compaction_signal: :traces}, _records, summary),
    do: %{segment | trace_summary: summary}

  defp summarize_replacement(segment, %{compaction_signal: :logs}, _records, services),
    do: %{segment | log_services: services}

  defp summarize_replacement(segment, _config, records, _summary), do: Segment.summarize_metrics(segment, records)

  # A replacement holds exactly its sources' rows, so the union of their
  # complete stream-label sets is complete for it too.
  defp merge_source_summaries(segment, %{compaction_signal: :logs}, sources),
    do: %{
      segment
      | log_labels: Segment.merge_log_labels(Enum.map(sources, & &1.log_labels)),
        log_minutes: Segment.merge_log_minutes(Enum.map(sources, & &1.log_minutes))
    }

  # Likewise for trace attribute value sets.
  defp merge_source_summaries(
         %{trace_summary: %TraceSummary{} = summary} = segment,
         %{compaction_signal: :traces},
         sources
       ) do
    attributes =
      TraceAttributeSummary.merge(Enum.map(sources, &(&1.trace_summary && &1.trace_summary.attributes)), :segment)

    %{segment | trace_summary: %{summary | attributes: attributes}}
  end

  defp merge_source_summaries(segment, _config, _sources), do: segment

  # Through the manifest owner, so local appends cannot slip in between the
  # read of the root and its conditional write. A format-4 replacement is
  # planned first against a fresh snapshot, outside the owner: its page reads
  # and rewritten page writes would otherwise hold every append of the prefix
  # for their whole duration (at object-store latency each). The owner only
  # commits the plan in memory. Every attempt first checks for an earlier
  # publication whose response was lost.
  defp publish(tenant, config, sources, replacement, grace) do
    signal = signal_string(config)

    with {:ok, plan} <- plan_publication(tenant, config, sources, replacement, grace) do
      transaction = &replacement_write(&1, tenant, config, sources, replacement, grace, plan)

      case ManifestOwner.transact(tenant, signal, config, transaction) do
        {:ok, :ok} ->
          :ok

        {:error, :cas_retries_exhausted} = error ->
          resolve_unconfirmed(tenant, config, replacement, plan, error)

        {:error, {:unconfirmed, reason}} ->
          resolve_unconfirmed(tenant, config, replacement, plan, {:error, {:unpublished_replacement, reason}})

        error ->
          error
      end
    end
  end

  # Planned against the node's cached root: a stale one only makes the commit
  # conflict, never publish the wrong change.
  defp plan_publication(tenant, config, sources, replacement, grace) do
    case ManifestOwner.ensure_loaded(tenant, signal_string(config), config) do
      {:ok, %{manifest: %{version: 4} = snapshot}} ->
        deadline = System.system_time(:millisecond) + grace
        signal = signal_string(config)

        case JournalManifest.plan_replace(snapshot, sources, [replacement], 2, deadline, tenant, signal, config) do
          {:ok, plan} -> {:ok, plan}
          {:error, reason} -> {:error, {:unpublished_replacement, reason}}
        end

      {:ok, _other} ->
        {:ok, nil}

      error ->
        error
    end
  end

  # A format-4 commit only reads the root in memory: the replacement listed in
  # the tail is a lost earlier response; anything else is confirmed outside.
  defp replacement_write(%{version: 4} = current, tenant, config, _sources, replacement, _grace, plan)
       when plan != nil do
    signal = signal_string(config)

    if Enum.any?(current.segments, &(&1.key == replacement.key)) do
      {:done, :ok}
    else
      with {:ok, updated} <- JournalManifest.commit_replace(current, plan, tenant, signal, config),
           {:ok, {sealed, payload, _}} <- JournalManifest.seal(updated, tenant, signal, config) do
        {:write, sealed, payload, :ok}
      else
        {:error, reason} -> {:error, {:unconfirmed, reason}}
      end
    end
  end

  defp replacement_write(current, tenant, config, sources, replacement, grace, _plan) do
    case published?(current, replacement.key, tenant, config) do
      {:ok, true} ->
        {:done, :ok}

      # Prepared before the conditional write: a failure here proves this
      # unique key was never published.
      {:ok, false} ->
        current |> prepare_replacement(sources, replacement, grace, tenant, config) |> prepared_write()

      error ->
        error
    end
  end

  defp prepared_write({:ok, updated}), do: {:write, updated, updated |> Manifest.encode() |> IO.iodata_to_binary(), :ok}
  defp prepared_write({:ok, sealed, payload}), do: {:write, sealed, payload, :ok}
  defp prepared_write({:error, reason}), do: {:error, {:unpublished_replacement, reason}}

  # The last conditional response can also have been lost after success.
  # Resolve it against a fresh root before reclaiming this unique upload and
  # the pages planned for it, which no published root references then.
  defp resolve_unconfirmed(tenant, config, replacement, plan, error) do
    with {:ok, current, _etag} <- load(tenant, config),
         {:ok, published} <- published?(current, replacement.key, tenant, config),
         do: JournalManifest.settle_unconfirmed(published, plan, config, error)
  end

  defp published?(%{version: 3} = root, key, tenant, config) do
    result =
      PagedManifest.with_budget(config, fn ->
        {:ok, segment} = ManifestOwner.segment_from_key(key)
        # Once wholly expired, even an unpublished upload belongs to retention.
        # Do not erase a possibly committed replacement ahead of its grace.
        segment.max_ts < PagedManifest.floor(root) or
          PagedManifest.lookup(root, segment, tenant, signal_string(config), config) != :absent
      end)

    if result == {:error, :retention_expired}, do: {:ok, false}, else: result
  end

  defp published?(%{version: 4} = root, key, tenant, config) do
    {:ok, segment} = ManifestOwner.segment_from_key(key)

    with {:ok, found} <- JournalManifest.lookup(root, segment, tenant, signal_string(config), config),
         do: {:ok, found != :absent}
  end

  defp published?(manifest, key, _tenant, _config),
    do: {:ok, Enum.any?(manifest.segments, &(&1.key == key)) or Map.has_key?(manifest.retired, key)}

  defp validate_retained_grace(%{version: 3}, config, opts) do
    if Keyword.get(opts, :grace_ms, 3_600_000) <= Retention.effective_grace(config, signal_string(config)),
      do: :ok,
      else: {:error, :unsupported_compaction_grace}
  end

  defp validate_retained_grace(_manifest, _config, _opts), do: :ok
  defp migration_gate(%{version: 3}, _config), do: :ok

  defp migration_gate(_root, config) do
    if Retention.bucketed?(config, signal_string(config)),
      do: {:error, :retention_migration_required},
      else: :ok
  end

  @doc false
  def advance_empty_cursor(%{version: 3}, candidates, tenant, config) do
    case candidates.paging["compaction_candidate"] do
      nil ->
        :ok

      start ->
        case Retention.transact(
               tenant,
               signal_string(config),
               config,
               &{%{&1 | paging: Map.put(&1.paging, "compaction_bucket", start)}, :ok}
             ) do
          {:ok, :ok} -> :ok
          error -> error
        end
    end
  end

  def advance_empty_cursor(%{version: 4}, candidates, tenant, config) do
    next = candidates.paging["compaction_candidate"]

    advance = fn root ->
      if root.version == 4, do: {JournalManifest.advance_cursor(root, next), :ok}, else: {root, :ok}
    end

    case Retention.transact(tenant, signal_string(config), config, advance) do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  def advance_empty_cursor(_root, _candidates, _tenant, _config), do: :ok

  defp compaction_candidates(%{version: 3} = root, tenant, config),
    do: PagedManifest.candidates(root, tenant, signal_string(config), config)

  defp compaction_candidates(%{version: 4} = root, tenant, config),
    do: JournalManifest.candidates(root, tenant, signal_string(config), config)

  defp compaction_candidates(root, _tenant, _config), do: {:ok, root}

  defp prepare_replacement(%{version: 3} = root, sources, replacement, grace, tenant, config) do
    segments =
      Enum.map(sources, fn key ->
        {:ok, segment} = ManifestOwner.segment_from_key(key)
        segment
      end)

    PagedManifest.replace(
      root,
      segments,
      replacement,
      System.system_time(:millisecond) + grace,
      tenant,
      signal_string(config),
      config
    )
  end

  defp prepare_replacement(%{version: 4} = root, sources, replacement, grace, tenant, config) do
    deadline = System.system_time(:millisecond) + grace
    signal = signal_string(config)

    with {:ok, updated} <- JournalManifest.replace(root, sources, replacement, deadline, tenant, signal, config),
         {:ok, {sealed, payload, _}} <- JournalManifest.seal(updated, tenant, signal, config),
         do: {:ok, sealed, payload}
  end

  defp prepare_replacement(root, sources, replacement, grace, _tenant, _config),
    do: Manifest.replace(root, sources, replacement, System.system_time(:millisecond) + grace)

  @doc """
  Delete up to max_deletions (128) expired objects; persist progress and retry
  failed keys on later passes. `:now_ms` overrides the clock deadlines are
  compared with.
  """
  def cleanup(tenant, config, opts \\ []) do
    monitor(:cleanup, fn -> do_cleanup(tenant, config, opts) end)
  end

  @doc false
  def monitor(operation, fun) do
    Pulse.Metrics.measure(
      :compaction,
      Atom.to_string(operation),
      fn ->
        Pulse.SelfMetrics.track(:compaction, operation, fn ->
          result = fun.()
          Pulse.SelfMetrics.compaction(operation, result)
          result
        end)
      end,
      fn
        {:ok, %{merged: count}} -> %{segments: count}
        {:ok, count} when is_integer(count) -> %{segments: count}
        _ -> %{}
      end
    )
  end

  defp do_cleanup(tenant, config, opts) do
    maximum = Keyword.get(opts, :max_deletions, 128)

    with :ok <- S3.validate_tenant(tenant),
         :ok <- validate_cleanup_limit(maximum),
         {:ok, manifest, _etag} <- load(tenant, config),
         :ok <- migration_gate(manifest, config) do
      case manifest.version do
        3 -> Retention.cleanup_retired(tenant, signal_string(config), config, opts)
        4 -> cleanup_paged(manifest, tenant, maximum, config, now(opts))
        _ -> manifest |> deletion_candidates(tenant, maximum, config, now(opts)) |> delete_candidates(tenant, config)
      end
    end
  end

  # Retired segments as for flat roots, plus manifest pages superseded by
  # compaction once their reader grace has passed. A gc page is deleted only
  # after every page it lists, so a missing gc page means its work is done.
  # `:now_ms` holds deletions back, for example until a manifest backup
  # records the retirements (`Pulse.Storage.S3.ManifestBackup.hold_ms/3`).
  defp now(opts), do: Keyword.get(opts, :now_ms, System.system_time(:millisecond))

  defp cleanup_paged(root, tenant, maximum, config, now) do
    signal = signal_string(config)

    with {:ok, plan} <- JournalManifest.cleanup_plan(root, now, maximum, tenant, signal, config) do
      retired = Enum.filter(plan.retired, fn {key, _} -> valid_segment_key?(tenant, key, config) end)
      {deleted, errors} = delete_retired(retired, config)
      pages = delete_pages(plan.pages, config)

      gc_refs =
        for {ref, keys} <- plan.gc_pages,
            length(delete_pages(keys, config)) == length(keys) and delete_pages([ref["k"]], config) != [],
            do: ref["k"]

      cursor = with {key, _} <- List.last(retired), do: key

      if retired == [] and pages == [] and gc_refs == [],
        do: {:ok, 0},
        else:
          finish_paged_cleanup(
            root,
            tenant,
            config,
            %{deleted: deleted, pages: pages, gc_refs: gc_refs, cursor: cursor},
            errors
          )
    end
  end

  # Rewrites of the pages holding deleted retirements are written here,
  # outside the manifest owner, which only swaps references.
  defp finish_paged_cleanup(root, tenant, config, work, errors) do
    with {:ok, changes} <- JournalManifest.plan_cleanup(root, work.deleted, tenant, signal_string(config), config),
         :ok <- publish_paged_cleanup(tenant, config, Map.put(work, :changes, changes)) do
      if errors == [], do: {:ok, length(work.deleted)}, else: {:error, {:cleanup_failed, Enum.reverse(errors)}}
    end
  end

  # The keys that were deleted (or were already absent).
  defp delete_pages(keys, config) do
    keys
    |> Pulse.Runtime.Task.async_stream(&{&1, ObjectStore.delete(config, &1)}, max_concurrency: 8, timeout: :infinity)
    |> Enum.flat_map(fn
      {:ok, {key, :ok}} -> [key]
      {:ok, {key, {:error, :not_found}}} -> [key]
      _ -> []
    end)
  end

  defp publish_paged_cleanup(tenant, config, work) do
    signal = signal_string(config)

    transaction = fn
      %{version: 4} = current ->
        current
        |> JournalManifest.apply_cleanup(work, tenant, signal, config)
        |> cleanup_write(current, tenant, signal, config)

      # Retention converted the root meanwhile; it owns cleanup now.
      _current ->
        {:done, :ok}
    end

    with {:ok, :ok} <- ManifestOwner.transact(tenant, signal, config, transaction), do: :ok
  end

  defp cleanup_write({:ok, current}, current, _tenant, _signal, _config), do: {:done, :ok}

  defp cleanup_write({:ok, updated}, _current, tenant, signal, config) do
    with {:ok, {sealed, payload, _}} <- JournalManifest.seal(updated, tenant, signal, config),
         do: {:write, sealed, payload, :ok}
  end

  defp cleanup_write(error, _current, _tenant, _signal, _config), do: error

  defp validate_cleanup_limit(maximum) when is_integer(maximum) and maximum > 0, do: :ok
  defp validate_cleanup_limit(_), do: {:error, :invalid_cleanup_options}

  defp deletion_candidates(manifest, tenant, maximum, config, now) do
    active = MapSet.new(manifest.segments, & &1.key)

    eligible =
      manifest.retired
      |> Enum.filter(fn {key, retirement} ->
        not retirement.deleted? and retirement.delete_after <= now and valid_segment_key?(tenant, key, config) and
          not MapSet.member?(active, key)
      end)
      |> Enum.sort_by(&elem(&1, 0))

    {before, after_cursor} =
      Enum.split_while(eligible, fn {key, _} -> manifest.cleanup_cursor != nil and key <= manifest.cleanup_cursor end)

    Enum.take(after_cursor ++ before, maximum)
  end

  defp delete_candidates([], _tenant, _config), do: {:ok, 0}

  defp delete_candidates(candidates, tenant, config) do
    {deleted, errors} = delete_retired(candidates, config)
    {cursor, _} = List.last(candidates)

    with :ok <- publish_deletions(tenant, config, deleted, cursor) do
      if errors == [], do: {:ok, length(deleted)}, else: {:error, {:cleanup_failed, Enum.reverse(errors)}}
    end
  end

  # Eight deletes at a time: one at a time, a full batch at object-store
  # latency took most of the operation timeout.
  defp delete_retired(candidates, config) do
    candidates
    |> Pulse.Runtime.Task.async_stream(fn {key, _} -> ObjectStore.delete(config, key) end,
      max_concurrency: 8,
      timeout: :infinity
    )
    |> Enum.zip(candidates)
    |> Enum.reduce({[], []}, fn
      {{:ok, result}, candidate}, {deleted, errors} when result in [:ok, {:error, :not_found}] ->
        {[candidate | deleted], errors}

      {{:ok, {:error, reason}}, {key, _}}, {deleted, errors} ->
        {deleted, [{key, reason} | errors]}
    end)
  end

  defp publish_deletions(tenant, config, deleted, cursor) do
    transaction = fn current ->
      updated = Manifest.mark_deleted(current, deleted, cursor)

      if updated == current,
        do: {:done, :ok},
        else: {:write, updated, updated |> Manifest.encode() |> IO.iodata_to_binary(), :ok}
    end

    with {:ok, :ok} <- ManifestOwner.transact(tenant, signal_string(config), config, transaction), do: :ok
  end

  defp load(tenant, config), do: Retention.load(tenant, signal_string(config), config)

  defp validate_options(opts) do
    valid? =
      Enum.all?([:max_segments, :max_input_bytes, :max_rows, :small_segment_bytes], fn key ->
        value = Keyword.get(opts, key, 32)
        is_integer(value) and value > 0
      end)

    grace = Keyword.get(opts, :grace_ms, 3_600_000)
    if valid? and is_integer(grace) and grace >= 0, do: :ok, else: {:error, :invalid_compaction_options}
  end
end
