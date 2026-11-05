defmodule Pulse.Errors.Projection do
  @moduledoc """
  Optional, bounded S3-derived error history. The log manifest alone accepts
  events; this independent CAS root publishes coverage, deduplication, summaries
  and replay pages together. No ingest request waits for this index.
  """
  alias Pulse.Alerting.Canonical
  alias Pulse.Errors
  alias Pulse.Errors.ProjectionCursor
  alias Pulse.ObjectStore
  alias Pulse.QueryRunner
  alias Pulse.Runtime
  alias Pulse.Storage.S3

  @root_bytes 8_388_608
  @page_bytes 262_144
  @decoded_bytes 33_554_432
  @sources 4096
  @occurrences 20_000
  @step_sources 32
  @day_ns 86_400_000_000_000
  @rate_window_ns 300_000_000_000
  @rate_detector "error-count-ratio-v1"

  def key(tenant, project), do: "tenants/#{tenant}/errors/v1/project=#{project}/head.json"

  def step(tenant, project, opts \\ []) do
    with :ok <- scope(tenant, project) do
      QueryRunner.run(tenant, :alerting, &advance(tenant, project, &1, opts))
    end
  end

  def read(kind, tenant, project, args \\ %{}) when kind in [:issues, :changes] do
    with :ok <- scope(tenant, project) do
      QueryRunner.run(tenant, :raw, fn _deadline -> read_page(kind, tenant, project, args) end)
    end
  end

  defp read_page(kind, tenant, project, args) do
    with {:ok, cursor} <- ProjectionCursor.open(args["cursor"], tenant, project, kind),
         limit when is_integer(limit) and limit in 1..100 <- args["limit"] || 50,
         {:ok, root, _etag} <- load(tenant, project, config()) do
      if kind == :changes,
        do: changes_page(root, tenant, project, cursor, limit),
        else: issues_page(root, tenant, project, cursor, limit)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_arguments}
    end
  end

  defp scope(tenant, project) do
    with :ok <- S3.validate_tenant(tenant) do
      if is_binary(project) and Regex.match?(~r/\A[0-9]{1,32}\z/, project),
        do: :ok,
        else: {:error, :invalid_project}
    end
  end

  defp config, do: Map.new(Runtime.get_env(:pulse, S3, []))

  defp load(tenant, project, config) do
    with {:ok, etag, bytes} <- ObjectStore.get_bounded(config, key(tenant, project), nil, @root_bytes),
         {:ok, %{"version" => 1, "sources" => sources, "pages" => pages, "issues" => issues} = root} <-
           Pulse.JSON.decode(bytes),
         true <- is_map(sources) and is_list(pages) and is_map(issues) do
      {:ok, root, etag}
    else
      {:error, :not_found} -> {:error, :projection_not_ready}
      {:error, _} = error -> error
      _ -> {:error, :invalid_projection}
    end
  end

  defp advance(tenant, project, deadline, opts) do
    config = config()
    now = Keyword.get(opts, :now_ns, System.system_time(:nanosecond))
    settings = Runtime.get_env(:pulse, __MODULE__, [])
    horizon = Keyword.get(settings, :history_days, 1) * @day_ns
    scan = [start_ts: max(0, now - horizon), matchers: matchers(project), max_scan_segments: @sources]
    scan = Keyword.merge(QueryRunner.storage_opts(deadline), scan)

    with {:ok, old, etag} <- existing(tenant, project, config, now, horizon),
         {:ok, snapshot} <- S3.log_snapshot(tenant, scan),
         true <- now >= old["indexed_at_ns"],
         floor = max(snapshot.floor_ns, max(0, now - horizon)),
         {base, reset} = reconcile(old, snapshot, floor, horizon),
         {:ok, sources} <- fetch_sources(base, snapshot, floor, project, deadline, config),
         {:ok, next, changes} <- derive(old, base, sources, snapshot, floor, now, reset),
         :ok <- publish(tenant, project, next, changes, etag, config, deadline) do
      {:ok, status(next)}
    else
      false -> {:error, :projection_clock_regressed}
      error -> error
    end
  end

  defp existing(tenant, project, config, now, horizon) do
    case load(tenant, project, config) do
      {:error, :projection_not_ready} ->
        {:ok,
         %{
           "version" => 1,
           "generation" => nonce(),
           "baseline" => true,
           "history_floor_ns" => max(0, now - horizon),
           "horizon_ns" => horizon,
           "indexed_at_ns" => 0,
           "sequence" => 0,
           "replay_floor" => 0,
           "sources" => %{},
           "candidates" => %{},
           "issues" => %{},
           "pages" => []
         }, nil}

      result ->
        result
    end
  end

  defp reconcile(old, snapshot, floor, horizon) do
    current = Map.new(snapshot.segments, &{&1.key, &1.max_ts})

    # A source could have arrived AND expired between observations. A new raw
    # floor above the previously covered history cannot prove continuity, even
    # when every previously known source was processed. Never invent coverage.
    reset =
      cond do
        old["horizon_ns"] != horizon -> "history_horizon_changed"
        old["indexed_at_ns"] > 0 and snapshot.floor_ns > old["history_floor_ns"] -> "source_history_unverifiable"
        missing_input?(old, current, floor) -> "source_disappeared"
        true -> nil
      end

    base =
      if reset do
        old
        |> Map.merge(%{"sources" => %{}, "issues" => %{}, "baseline" => true})
        |> Map.put("last_reset_reason", reset)
      else
        old
      end

    sources =
      base["sources"]
      |> Map.take(Map.keys(current))
      |> Map.new(fn {key, rows} -> {key, Enum.filter(rows, &(&1["timestamp_ns"] >= floor))} end)

    {Map.merge(base, %{"sources" => sources, "candidates" => current, "horizon_ns" => horizon}), reset}
  end

  defp missing_input?(old, current, floor) do
    Enum.any?(old["candidates"], fn {key, maximum} ->
      not Map.has_key?(current, key) and
        (not Map.has_key?(old["sources"], key) or maximum >= floor)
    end)
  end

  defp fetch_sources(base, snapshot, floor, project, deadline, config) do
    pending =
      snapshot.segments
      |> Enum.reject(&Map.has_key?(base["sources"], &1.key))
      |> Enum.sort_by(& &1.key)
      |> Enum.take(@step_sources)

    count = Enum.reduce(base["sources"], 0, fn {_, rows}, n -> n + length(rows) end)
    budget = %{sources: base["sources"], records: count, bytes: 0, rows: 0, decoded_bytes: 0}

    Enum.reduce_while(pending, {:ok, budget}, fn segment, {:ok, budget} ->
      opts = [
        matchers: matchers(project),
        max_records: max(1, @occurrences - budget.records),
        max_decoded_bytes: @decoded_bytes - budget.decoded_bytes
      ]

      result =
        with :ok <- before_deadline(deadline),
             true <- budget.records < @occurrences,
             true <- budget.rows + (segment.row_count || 100_000) <= 100_000,
             {:ok, _, blob} <- ObjectStore.get_bounded(config, segment.key, nil, 67_108_864 - budget.bytes),
             {:ok, rows, charged_bytes} <- S3.decode_log_segment_bounded(blob, floor, nil, opts),
             rows = rows |> Enum.filter(&Errors.error_record?/1) |> Enum.map(&compact/1),
             next = %{
               sources: Map.put(budget.sources, segment.key, rows),
               records: budget.records + length(rows),
               bytes: budget.bytes + byte_size(blob),
               decoded_bytes: budget.decoded_bytes + charged_bytes,
               rows: budget.rows + (segment.row_count || 100_000)
             },
             true <- next.rows <= 100_000 and next.records <= @occurrences and next.bytes < 67_108_864 do
          {:ok, next}
        else
          false -> {:error, :projection_capacity}
          error -> error
        end

      case result do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, budget} -> {:ok, budget.sources}
      error -> error
    end
  end

  defp compact(record) do
    # Small retained fields must not pin the Parquet column arena or a large
    # payload message through a sub-binary after this segment is processed.
    %{
      "event_id" => :binary.copy(record.resource["error_event_id"]),
      "issue_id" => :binary.copy(record.resource["error_issue_id"]),
      "timestamp_ns" => record.timestamp_ns,
      "title" => record.body |> Errors.title() |> String.byte_slice(0, 2000) |> :binary.copy(),
      "service" => :binary.copy(record.service),
      "digest" => Errors.event_digest(record)
    }
  end

  defp derive(old, base, sources, snapshot, floor, now, reset) do
    events =
      sources
      |> Map.values()
      |> List.flatten()
      # Project/tenant scope is fixed by the root. Conflicting SDK retries use
      # greatest (occurrence timestamp, canonical payload digest), never arrival
      # order or observed_timestamp_ns; nodes therefore pick the same copy.
      |> Enum.sort_by(&{&1["timestamp_ns"], &1["event_id"], &1["digest"]}, :desc)
      |> Enum.uniq_by(& &1["event_id"])

    issues =
      events
      |> Enum.group_by(& &1["issue_id"])
      |> Map.new(fn {id, [latest | _] = rows} ->
        summary = %{
          "issue_id" => id,
          "title" => latest["title"],
          "service" => latest["service"],
          "retained_count" => length(rows),
          "first_seen_ns" => Enum.min(Enum.map(rows, & &1["timestamp_ns"])),
          "last_seen_ns" => latest["timestamp_ns"],
          "latest_example" => Map.take(latest, ~w(event_id timestamp_ns))
        }

        {id, summary}
      end)

    backlog = length(snapshot.segments) - map_size(sources)
    # Only a complete reconciliation can publish exact counts or novelty. Work
    # checkpoints advance independently; incomplete batches expose pending state,
    # not partial counts disguised as retained-history totals.
    changes = if backlog == 0, do: observation_changes(base, issues, floor), else: []
    {rate_state, findings} = rate_changes(base, events, floor, now, backlog)
    findings = Enum.map(findings, &Map.merge(&1, %{"source_etag" => snapshot.etag, "history_floor_ns" => floor}))
    changes = changes ++ findings
    changes = if reset, do: [%{"kind" => "reset", "reason" => reset} | changes], else: changes

    changes =
      if base["baseline"] and backlog == 0,
        do: changes ++ [%{"kind" => "baseline_ready"}],
        else: changes

    next =
      Map.merge(base, %{
        "sources" => sources,
        "issues" => if(backlog == 0, do: issues, else: base["issues"]),
        "baseline" => base["baseline"] and backlog > 0,
        "backlog_segments" => backlog,
        "history_floor_ns" => floor,
        "source_etag" => snapshot.etag,
        "indexed_at_ns" => now,
        "rate_detector" => rate_state,
        "sequence" => old["sequence"] + length(changes)
      })

    changes =
      changes
      |> Enum.with_index(old["sequence"] + 1)
      |> Enum.map(fn {change, seq} ->
        Map.merge(change, %{"sequence" => seq, "change_id" => "#{old["generation"]}:#{seq}", "indexed_at_ns" => now})
      end)

    {:ok, next, changes}
  end

  defp observation_changes(%{"baseline" => true}, _issues, _floor), do: []

  defp observation_changes(base, issues, floor) do
    issues
    |> Enum.sort()
    |> Enum.reject(fn {id, summary} -> base["issues"][id] == summary end)
    |> Enum.map(fn {id, summary} ->
      previous = base["issues"][id]
      known = previous != nil and previous["last_seen_ns"] >= floor
      kind = if known, do: "issue_observation", else: "new_in_retained_history"
      %{"kind" => kind, "issue" => summary}
    end)
  end

  defp rate_changes(base, _events, _floor, _now, backlog) when backlog > 0, do: {base["rate_detector"], []}

  defp rate_changes(base, events, floor, now, 0) do
    finish = div(now, @rate_window_ns) * @rate_window_ns
    middle = finish - @rate_window_ns
    start = middle - @rate_window_ns
    previous = base["rate_detector"]

    if start < floor do
      {%{"detector" => @rate_detector, "status" => "insufficient_history", "window_end_ns" => finish}, []}
    else
      emitted =
        if previous && previous["window_end_ns"] == finish,
          do: MapSet.new(previous["emitted"] || []),
          else: MapSet.new()

      findings =
        events
        |> rate_findings(start, middle, finish)
        |> Enum.reject(&MapSet.member?(emitted, [&1["issue_id"], &1["service"]]))

      emitted = Enum.reduce(findings, emitted, &MapSet.put(&2, [&1["issue_id"], &1["service"]]))

      state = %{
        "detector" => @rate_detector,
        "status" => "ready",
        "window_end_ns" => finish,
        "emitted" => Enum.sort(emitted)
      }

      # Bootstrap, reset and old-worker upgrades establish a baseline, not an
      # incident. Remember qualifying groups so the next pass cannot announce it.
      suppress = base["baseline"] or previous == nil or previous["status"] != "ready"
      {state, if(suppress, do: [], else: findings)}
    end
  end

  defp rate_findings(events, start, middle, finish) do
    events
    |> Enum.filter(&(&1["timestamp_ns"] >= start and &1["timestamp_ns"] < finish))
    |> Enum.group_by(&[&1["issue_id"], &1["service"]])
    |> Enum.sort()
    |> Enum.flat_map(fn {[issue, service], rows} ->
      {current, baseline} = Enum.split_with(rows, &(&1["timestamp_ns"] >= middle))
      before = length(baseline)
      after_count = length(current)

      if before >= 5 and after_count >= 3 * before do
        [
          %{
            "kind" => "error_rate_increase",
            "detector" => @rate_detector,
            "issue_id" => issue,
            "service" => service,
            "baseline" => %{"start_ns" => start, "end_ns" => middle, "count" => before},
            "current" => %{"start_ns" => middle, "end_ns" => finish, "count" => after_count},
            "ratio" => after_count / before,
            "coverage" => "retained_snapshot",
            "evidence" => Enum.take(current, 3) |> Enum.map(&Map.take(&1, ~w(event_id timestamp_ns title service)))
          }
        ]
      else
        []
      end
    end)
  end

  defp publish(tenant, project, next, changes, etag, config, deadline) do
    with {:ok, refs} <- write_pages(tenant, project, changes, config, deadline) do
      {expired, pages} = Enum.split(next["pages"] ++ refs, -64)
      replay_floor = if expired == [], do: next["replay_floor"], else: List.last(expired)["last"]
      next = Map.merge(next, %{"pages" => pages, "replay_floor" => replay_floor, "publication" => nonce()})
      bytes = Canonical.encode(next)

      with true <- byte_size(bytes) <= @root_bytes,
           :ok <- before_deadline(deadline),
           :ok <- cas(key(tenant, project), bytes, etag, config) do
        # The new root first fences readers below replay_floor. Deletion cannot
        # hide a committed change inside the advertised replay range.
        Enum.each(expired, &ObjectStore.delete_bounded(config, &1["key"]))
        :ok
      else
        false -> {:error, :projection_capacity}
        error -> error
      end
    end
  end

  defp write_pages(tenant, project, changes, config, deadline) do
    changes
    |> Enum.chunk_while(
      {[], 2},
      fn change, {page, bytes} ->
        size = byte_size(Canonical.encode(change))

        if page != [] and (length(page) == 64 or bytes + 1 + size > @page_bytes) do
          {:cont, Enum.reverse(page), {[change], 2 + size}}
        else
          {:cont, {[change | page], bytes + size + if(page == [], do: 0, else: 1)}}
        end
      end,
      fn
        {[], _} = acc -> {:cont, acc}
        {page, _} -> {:cont, Enum.reverse(page), {[], 2}}
      end
    )
    |> Enum.reduce_while({:ok, []}, fn page, {:ok, refs} ->
      bytes = Canonical.encode(page)
      digest = Canonical.digest(bytes)
      page_key = String.replace_suffix(key(tenant, project), "head.json", "pages/#{digest}.json")

      ref = %{
        "key" => page_key,
        "digest" => digest,
        "bytes" => byte_size(bytes),
        "first" => hd(page)["sequence"],
        "last" => List.last(page)["sequence"]
      }

      result =
        with true <- byte_size(bytes) <= @page_bytes,
             :ok <- before_deadline(deadline),
             {:ok, _} <- ObjectStore.put(config, page_key, bytes),
             do: :ok

      case result do
        :ok -> {:cont, {:ok, refs ++ [ref]}}
        false -> {:halt, {:error, :projection_capacity}}
        error -> {:halt, error}
      end
    end)
  end

  defp cas(key, bytes, etag, config) do
    result =
      if etag,
        do: ObjectStore.put_if_match(config, key, bytes, etag),
        else: ObjectStore.put_if_none_match(config, key, bytes)

    case result do
      {:ok, _} ->
        :ok

      _ ->
        case ObjectStore.get_bounded(config, key, nil, @root_bytes) do
          {:ok, _, ^bytes} -> :ok
          _ -> {:error, :projection_conflict_or_unconfirmed}
        end
    end
  end

  defp issues_page(root, tenant, project, cursor, limit) do
    digest = Canonical.hash([root["generation"], root["history_floor_ns"], root["issues"]])

    if root["backlog_segments"] == 0 do
      complete_issues_page(root, tenant, project, cursor, limit, digest)
    else
      {:error, :projection_catching_up}
    end
  end

  defp complete_issues_page(root, tenant, project, cursor, limit, digest) do
    if cursor == nil or (cursor["snapshot"] == digest and is_integer(cursor["offset"]) and cursor["offset"] >= 0) do
      offset = if cursor, do: cursor["offset"], else: 0
      rows = root["issues"] |> Map.values() |> Enum.sort_by(&{-&1["last_seen_ns"], &1["issue_id"]})
      result = Enum.slice(rows, offset, limit)
      more = offset + length(result) < length(rows)

      next =
        if more,
          do:
            ProjectionCursor.seal(
              %{"snapshot" => digest, "offset" => offset + length(result)},
              tenant,
              project,
              :issues
            )

      {:ok, Map.merge(status(root), %{"results" => result, "next_cursor" => next})}
    else
      {:error, :reset_required}
    end
  end

  defp changes_page(root, tenant, project, cursor, limit) do
    after_seq = if cursor, do: cursor["sequence"], else: root["replay_floor"]

    with true <-
           (cursor == nil or cursor["generation"] == root["generation"]) and
             is_integer(after_seq) and after_seq >= root["replay_floor"] and after_seq <= root["sequence"],
         refs = Enum.filter(root["pages"], &(&1["last"] > after_seq)),
         {:ok, changes} <- replay(refs, after_seq, limit, []) do
      sequence = if changes == [], do: after_seq, else: List.last(changes)["sequence"]

      next =
        ProjectionCursor.seal(%{"generation" => root["generation"], "sequence" => sequence}, tenant, project, :changes)

      {:ok, Map.merge(status(root), %{"changes" => changes, "next_cursor" => next})}
    else
      false -> {:error, :reset_required}
      error -> error
    end
  end

  defp replay([], _seq, _limit, acc), do: {:ok, acc}
  defp replay(_refs, _seq, limit, acc) when length(acc) >= limit, do: {:ok, acc}

  defp replay([ref | rest], seq, limit, acc) do
    with {:ok, _, bytes} <- ObjectStore.get_bounded(config(), ref["key"], nil, @page_bytes),
         true <- byte_size(bytes) == ref["bytes"] and Canonical.digest(bytes) == ref["digest"],
         {:ok, rows} when is_list(rows) <- Pulse.JSON.decode(bytes) do
      rows = Enum.filter(rows, &(&1["sequence"] > seq)) |> Enum.take(limit - length(acc))
      replay(rest, seq, limit, acc ++ rows)
    else
      {:error, :not_found} -> {:error, :reset_required}
      {:error, _} = error -> error
      _ -> {:error, :invalid_projection}
    end
  end

  defp status(root) do
    Map.take(root, ~w(indexed_at_ns source_etag history_floor_ns horizon_ns sequence replay_floor last_reset_reason))
    |> Map.merge(%{
      "baseline_pending" => root["baseline"],
      "backlog_segments_at_index" => root["backlog_segments"],
      "complete_at_index" => root["backlog_segments"] == 0,
      "lag_ns" => nil,
      "lag_status" => "unknown",
      "novelty" => "new_in_retained_history",
      "grouping" => "sentry-group-v1",
      "rate_detector" => rate_status(root)
    })
  end

  defp rate_status(root) do
    state = root["rate_detector"] || %{"detector" => @rate_detector, "status" => "baseline_pending"}
    state = Map.delete(state, "emitted")
    if root["backlog_segments"] > 0, do: Map.put(state, "status", "catching_up"), else: state
  end

  defp matchers(project), do: [{"error_source", :eq, "sentry"}, {"error_project", :eq, project}]
  defp nonce, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  defp before_deadline(deadline) do
    if System.monotonic_time(:millisecond) < deadline, do: :ok, else: {:error, :query_timeout}
  end
end
