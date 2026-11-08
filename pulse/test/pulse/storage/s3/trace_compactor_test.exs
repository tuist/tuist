defmodule Pulse.Storage.S3.TraceCompactorTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.CompactionOwnership
  alias Pulse.Storage.S3.CompactionTasks
  alias Pulse.Storage.S3.CompactionWorker
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.Retention
  alias Pulse.Storage.S3.TraceCompactor
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.OTLPTraceFixture, as: Fixture
  alias Pulse.Test.TuistTraceFixture
  alias Pulse.Traces.Metrics
  alias Pulse.Traces.TempoSearch

  setup tags do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: agent}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "trace-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    # Tests of the flat format's own behaviour opt out of paged manifests.
    config = if tags[:manifest_format], do: Map.put(config, :manifest_format, tags[:manifest_format]), else: config

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    {:ok, [span], 0} = Traces.decode(Fixture.payload())
    %{agent: agent, config: config, tenant: "trace-compact-#{System.unique_integer([:positive])}", span: span}
  end

  defp load(ctx) do
    assert {:ok, manifest, _} = Retention.load(ctx.tenant, "traces", ctx.config)
    manifest
  end

  test "native assembly scans the full stored trace and never returns a budget-limited prefix", ctx do
    root = %{ctx.span | span_id: String.duplicate("a", 16), parent_span_id: nil, timestamp_ns: 1}
    assert :ok = S3.append(:traces, ctx.tenant, [root])
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span, ctx.span])
    assert {:ok, json} = S3.get_trace_json(ctx.tenant, root.trace_id, [])
    result = Pulse.JSON.decode!(json)
    assert result["span_count"] == 3
    assert result["root_span_ids"] == [root.span_id]
    assert result["duplicate_span_ids"] == [ctx.span.span_id]
    assert {:error, :query_scan_limit} = S3.get_trace_json(ctx.tenant, root.trace_id, max_scan_segments: 1)
    assert {:ok, json} = S3.get_trace_json("empty-tenant", root.trace_id, [])
    assert Pulse.JSON.decode!(json)["span_count"] == 0
  end

  @tag manifest_format: "flat"
  test "flat roots discard unused ID hashes while retaining exact-ID pruning", ctx do
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])
    [segment] = load(ctx).segments
    assert segment.trace_summary.lookup_hashes == nil
    assert segment.trace_summary.bits != nil
    assert {:ok, [_]} = S3.query(:traces, ctx.tenant, trace_id: ctx.span.trace_id)
  end

  test "LIST-rebuilt trace objects charge recovered footer rows", ctx do
    assert {:ok, blob, min, max} = S3.encode_segment(:traces, List.duplicate(ctx.span, 20))
    key = S3.object_key(ctx.tenant, "traces", min, max, "legacy", nil)
    assert {:ok, _} = ObjectStore.put(ctx.config, key, blob)
    assert {:error, :query_scan_limit} = S3.query(:traces, ctx.tenant, limit: 1, max_scan_rows: 10)
    assert [segment] = load(ctx).segments
    assert segment.row_count == nil
  end

  test "native merge preserves duplicates, nested metadata, summaries and durable recovery", ctx do
    a = %{ctx.span | attributes: Map.put(ctx.span.attributes, "zero", -0.0)}
    b = %{ctx.span | timestamp_ns: ctx.span.timestamp_ns + 1, attributes: Map.put(ctx.span.attributes, "zero", 0.0)}
    assert :ok = S3.append(:traces, ctx.tenant, [a, b], idempotency_key: "batch")
    assert :ok = S3.append(:traces, ctx.tenant, [a])
    assert {:ok, before} = S3.query(:traces, ctx.tenant, [])

    assert {:ok, %{merged: 2, replacements: [replacement]}} =
             TraceCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)

    manifest = load(ctx)
    assert [segment] = manifest.segments
    assert segment.key == replacement
    assert segment.row_count == 3
    assert segment.trace_summary.services == [ctx.span.service]
    assert map_size(manifest.retired) == 2
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert {:ok, ^before} = S3.query(:traces, ctx.tenant, [])
    assert {:ok, 2} = TraceCompactor.cleanup(ctx.tenant, ctx.config)
    assert {:ok, 0} = TraceCompactor.cleanup(ctx.tenant, ctx.config)
    assert :ok = S3.append(:traces, ctx.tenant, [a, b], idempotency_key: "batch")
    assert {:ok, ^before} = S3.query(:traces, ctx.tenant, [])
    assert {:ok, 1} = TraceCompactor.cleanup(ctx.tenant, ctx.config)
  end

  test "lost conditional publication response is recognized without losing the replacement", ctx do
    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [ctx.span]))
    key = Manifest.manifest_key(ctx.tenant, "traces")
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {500, :after, 1}}})
    assert {:ok, %{merged: 2}} = TraceCompactor.compact(ctx.tenant, ctx.config)
    assert [_] = load(ctx).segments
    assert {:ok, rows} = S3.query(:traces, ctx.tenant, [])
    assert length(rows) == 2
  end

  test "native payload ceiling refuses publication instead of dropping spans", ctx do
    row = %{ctx.span | name: :binary.copy(<<0>>, 2 * 1024 * 1024)}
    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [row]))

    assert {:error, :payload_too_large} =
             TraceCompactor.compact(ctx.tenant, ctx.config,
               small_segment_bytes: 32 * 1024 * 1024,
               max_input_bytes: 64 * 1024 * 1024
             )

    assert length(load(ctx).segments) == 2
    assert load(ctx).retired == %{}
  end

  test "over-budget native merges shrink original source sets before publication", ctx do
    row = %{ctx.span | name: :binary.copy(<<0>>, 1024 * 1024)}
    for _ <- 1..4, do: assert(:ok = S3.append(:traces, ctx.tenant, [row]))

    assert {:ok, %{merged: 2}} =
             TraceCompactor.compact(ctx.tenant, ctx.config,
               small_segment_bytes: 32 * 1024 * 1024,
               max_input_bytes: 64 * 1024 * 1024
             )

    manifest = load(ctx)
    assert length(manifest.segments) == 3
    assert Enum.sum(Enum.map(manifest.segments, & &1.row_count)) == 4
    assert map_size(manifest.retired) == 2
  end

  test "partial selection obeys every input bound without starving fresh sources", ctx do
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])
    [source] = active(ctx)

    fresh =
      for n <- 1..2 do
        %{source | key: String.replace(source.key, "-rand-", "-rand-#{n}-")}
      end

    partial =
      for n <- 1..64 do
        %{
          source
          | key: String.replace(source.key, "-rand-", "-compact-#{n}-"),
            trace_summary: %{source.trace_summary | lookup_hashes: <<0::64>>}
        }
      end

    for opts <- [[max_sources: 2], [max_rows: 2], [max_input_bytes: source.byte_size * 2]] do
      assert TraceCompactor.select(partial ++ fresh, opts) == Enum.sort_by(fresh, & &1.key)
    end

    assert length(TraceCompactor.select(partial, [])) == 64
    assert length(TraceCompactor.select([hd(fresh) | partial], max_sources: 2)) == 2
  end

  test "metadata admission finds viable pairs beyond oversized and singleton prefixes", ctx do
    for {counts, maximum} <- [{[3, 1, 1], 2}, {[2, 2, 1, 1], 3}, {[3, 1, 1], 3}] do
      tenant = "#{ctx.tenant}-#{Enum.join(counts)}-#{maximum}"

      expected =
        counts
        |> Enum.with_index()
        |> Enum.flat_map(fn {count, index} ->
          row = %{
            ctx.span
            | timestamp_ns: ctx.span.timestamp_ns + index,
              end_timestamp_ns: ctx.span.end_timestamp_ns + index
          }

          rows = List.duplicate(row, count)
          assert :ok = S3.append(:traces, tenant, rows)
          rows
        end)

      assert {:ok, %{merged: merged}} = TraceCompactor.compact(tenant, ctx.config, max_rows: maximum)
      assert merged >= 2
      assert {:ok, rows} = S3.query(:traces, tenant, max_scan_segments: length(counts) - 1)
      assert Enum.frequencies(rows) == Enum.frequencies(expected)
    end

    large = %{
      ctx.span
      | name: :binary.copy("large", 10_000),
        timestamp_ns: ctx.span.timestamp_ns - 1,
        end_timestamp_ns: ctx.span.end_timestamp_ns - 1
    }

    assert :ok = S3.append(:traces, ctx.tenant, [large])
    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [ctx.span]))
    bytes = active(ctx) |> Enum.filter(&(&1.min_ts == ctx.span.timestamp_ns)) |> Enum.sum_by(& &1.byte_size)
    assert {:ok, %{merged: 2}} = TraceCompactor.compact(ctx.tenant, ctx.config, max_input_bytes: bytes)
    assert {:ok, rows} = S3.query(:traces, ctx.tenant, max_scan_segments: 2)
    assert Enum.frequencies(rows) == %{large => 1, ctx.span => 2}
  end

  test "decoded overflow finds healthy same-hour batches without quarantining either source", ctx do
    big = %{
      ctx.span
      | name: :binary.copy(<<0>>, 1024 * 1024),
        timestamp_ns: ctx.span.timestamp_ns - 20,
        end_timestamp_ns: ctx.span.end_timestamp_ns - 20
    }

    next = %{big | timestamp_ns: big.timestamp_ns + 10, end_timestamp_ns: big.end_timestamp_ns + 10}
    assert :ok = S3.append(:traces, ctx.tenant, [big, big])
    assert :ok = S3.append(:traces, ctx.tenant, [next])
    originals = active(ctx)
    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [ctx.span]))

    assert {:ok, %{merged: merged}} = TraceCompactor.compact(ctx.tenant, ctx.config)
    assert merged >= 2
    assert Enum.any?(originals, &Map.has_key?(load(ctx).retired, &1.key))

    # The failing pair does not prove either source is individually invalid.
    # New arrivals must still be able to merge with those original sources.
    for _ <- 1..4 do
      for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [ctx.span]))
      assert {:ok, %{merged: merged}} = TraceCompactor.compact(ctx.tenant, ctx.config)
      assert merged >= 2
    end

    assert Enum.all?(originals, &Map.has_key?(load(ctx).retired, &1.key))

    rows =
      Enum.flat_map(active(ctx), fn segment ->
        assert {:ok, blob} = ObjectStore.get(ctx.config, segment.key)
        assert {:ok, decoded} = S3.decode_segment(:traces, blob, nil, nil, [])
        decoded
      end)

    assert Enum.frequencies(rows) == %{big => 2, next => 1, ctx.span => 10}
  end

  test "bounded compaction converges after fresh sources are exhausted", ctx do
    for _ <- 1..24, do: assert(:ok = S3.append(:traces, ctx.tenant, [ctx.span]))

    Enum.reduce_while(1..30, nil, fn _, _ ->
      assert {:ok, result} = TraceCompactor.compact(ctx.tenant, ctx.config, max_sources: 2)
      if result.merged == 0, do: {:halt, nil}, else: {:cont, nil}
    end)

    assert {:ok, rows} = S3.query(:traces, ctx.tenant, max_scan_segments: 1)
    assert rows == List.duplicate(ctx.span, 24)
    assert {:ok, %{merged: 0}} = TraceCompactor.compact(ctx.tenant, ctx.config, max_sources: 2)
  end

  test "partial finishing does not republish outputs without reducing fragmentation", ctx do
    payload =
      update_in(Fixture.payload(), ["resourceSpans", Access.all(), "resource", "attributes", Access.all()], fn
        %{"key" => "service.name"} = attribute -> put_in(attribute, ["value", "stringValue"], "another-service")
        attribute -> attribute
      end)

    assert {:ok, [other], 0} = Traces.decode(payload)
    assert :ok = S3.append(:traces, ctx.tenant, [ctx.span])
    assert :ok = S3.append(:traces, ctx.tenant, [other])
    assert {:ok, %{merged: 2, outputs: 2}} = TraceCompactor.compact(ctx.tenant, ctx.config)
    before = active(ctx)

    for _ <- 1..3 do
      assert {:ok, %{merged: 0}} = TraceCompactor.compact(ctx.tenant, ctx.config)
      assert active(ctx) == before
    end

    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [ctx.span]))
    assert {:ok, %{merged: 4, outputs: 2}} = TraceCompactor.compact(ctx.tenant, ctx.config)
    assert {:ok, rows} = S3.query(:traces, ctx.tenant, max_scan_segments: 2)
    assert Enum.frequencies(rows) == %{ctx.span => 3, other => 1}
  end

  test "oversized partial payloads do not prevent fresh sources from compacting", ctx do
    row = %{ctx.span | name: :binary.copy(<<0>>, 1024 * 1024)}
    opts = [small_segment_bytes: 32 * 1024 * 1024]
    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [row]))
    assert {:ok, %{merged: 2}} = TraceCompactor.compact(ctx.tenant, ctx.config, opts)
    [partial] = active(ctx)
    assert {:ok, partial_blob} = ObjectStore.get(ctx.config, partial.key)

    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [row]))
    fresh = Enum.reject(active(ctx), &(&1.key == partial.key))

    blobs =
      Enum.map(fresh, fn source ->
        {:ok, blob} = ObjectStore.get(ctx.config, source.key)
        blob
      end)

    # The native bound is decoded JSON, not compressed Parquet. Even one
    # fresh source plus the partial exceeds it, but the fresh pair fits.
    assert {:error, :payload_too_large} =
             NIF.compact_trace_segments_split([partial_blob, hd(blobs)], 60_000, 256, 1024, 20_000)

    assert {:ok, [_]} = NIF.compact_trace_segments_split(blobs, 60_000, 256, 1024, 20_000)
    assert {:ok, %{merged: 2}} = TraceCompactor.compact(ctx.tenant, ctx.config, opts)

    segments = active(ctx)
    assert length(segments) == 2
    assert partial in segments
    assert Enum.sum_by(segments, & &1.row_count) == 4

    # Publication retires only the selected pair, retaining every original
    # object until normal backup-held cleanup. Decode each active output to
    # prove complete rows, including duplicates, not just manifest counts.
    assert Enum.all?(fresh, &Map.has_key?(load(ctx).retired, &1.key))
    for source <- fresh, do: assert({:ok, _} = ObjectStore.get(ctx.config, source.key))

    # Now the partial set alone exceeds the native budget. A later batch
    # still progresses, instead of setting this entire hour aside locally.
    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [row]))
    assert {:ok, %{merged: 2}} = TraceCompactor.compact(ctx.tenant, ctx.config, opts)
    later = active(ctx)
    assert length(later) == 3
    assert Enum.all?(segments, &(&1 in later))
    assert Enum.sum_by(later, & &1.row_count) == 6

    for segment <- later do
      assert {:ok, blob} = ObjectStore.get(ctx.config, segment.key)
      assert {:ok, rows} = S3.decode_segment(:traces, blob, nil, nil, [])
      assert rows == [row, row]
    end

    # An irreducible partial-only batch must not defer newly arriving fresh
    # sources from the same hour, nor repeatedly publish unchanged outputs.
    for _ <- 1..2, do: assert({:ok, %{merged: 0}} = TraceCompactor.compact(ctx.tenant, ctx.config, opts))
    assert active(ctx) == later
    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [ctx.span]))
    assert {:ok, %{merged: 2}} = TraceCompactor.compact(ctx.tenant, ctx.config, opts)
  end

  test "trace-only workers join their own eligibility group and maintain idle durable tenants", ctx do
    for _ <- 1..2, do: assert(:ok = S3.append(:traces, ctx.tenant, [ctx.span]))

    config =
      Map.merge(ctx.config, %{compaction_enabled: false, trace_compaction_enabled: true, compaction_interval_ms: 60_000})

    start_supervised!(%{id: CompactionOwnership, start: {:pg, :start_link, [CompactionOwnership.scope()]}})
    start_supervised!({Task.Supervisor, name: CompactionTasks})
    worker = start_supervised!({CompactionWorker, config})
    assert CompactionOwnership.members(config, "metrics") == []
    assert CompactionOwnership.members(config, "traces") == [node()]
    send(worker, :compact)
    _ = :sys.get_state(worker, 60_000)
    assert [_] = load(ctx).segments
  end

  # Canary flushed traces every 2 s: an hour held more segments than one query
  # may read, so every trace panel failed until hours were merged.
  test "an hour of per-flush segments merges into service, class and ID objects that queries prune", ctx do
    Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    hour = div(System.os_time(:second), 3600) * 3600 - 7200
    flushes = 1100

    1..flushes
    |> Pulse.Runtime.Task.async_stream(
      fn n -> :ok = S3.append(:traces, ctx.tenant, flush((hour + div(n * 3, 1)) * 1_000_000_000, n)) end,
      max_concurrency: 16,
      timeout: :infinity
    )
    |> Stream.run()

    window = {hour * 1_000_000_000, (hour + 3600) * 1_000_000_000, 60_000_000_000}
    errors = ~s[{ status = error } | rate()]

    search =
      &TempoSearch.query(ctx.tenant, &1,
        trace_start: hour * 1_000_000_000,
        trace_end: (hour + 3600) * 1_000_000_000,
        limit: 20,
        spss: 10
      )

    assert {:error, :query_scan_limit} = Metrics.query(ctx.tenant, errors, window, false)
    {:ok, uncompacted} = search.(~s[{ status = error }])

    # As maintenance passes do: an empty pass rotates the candidate cursor.
    for _ <- 1..40, do: assert({:ok, _} = TraceCompactor.compact(ctx.tenant, ctx.config, settle_ms: 0))
    segments = active(ctx)
    assert length(segments) < 100
    assert Enum.sum_by(segments, & &1.row_count) == flushes * 20

    for segment <- segments do
      summary = segment.trace_summary
      assert [_service] = summary.services
      flagged? = 2 in summary.statuses or summary.events?
      assert byte_size(summary.lookup_hashes) <= if(flagged?, do: 1024, else: 256) * 8
      assert summary.pruning_safe?
      assert is_list(summary.statuses)
    end

    error_objects = Enum.filter(segments, &(2 in &1.trace_summary.statuses))
    assert length(error_objects) * 3 < length(segments)

    assert {:ok, json} = Metrics.query(ctx.tenant, errors, window, false)
    # Five failing spans per flush; the 1h window holds every flush.
    total =
      json
      |> Pulse.JSON.decode!()
      |> get_in(["series", Access.all(), "samples", Access.all(), "value"])
      |> List.flatten()
      |> Enum.sum()

    assert_in_delta total * 60, flushes * 5, 0.001
    assert {:ok, ^uncompacted} = search.(~s[{ status = error }])
  end

  defp active(ctx) do
    root = load(ctx)
    {:ok, segments} = JournalManifest.query(root, ctx.tenant, "traces", [], ctx.config)
    segments
  end

  defp flush(start, n) do
    for request <- TuistTraceFixture.requests(start) do
      request =
        update_in(
          request,
          ["resourceSpans", Access.all(), "scopeSpans", Access.all(), "spans", Access.all(), "traceId"],
          fn id ->
            (n * 1000 + String.to_integer(id, 16))
            |> Integer.to_string(16)
            |> String.downcase()
            |> String.pad_leading(32, "0")
          end
        )

      {:ok, spans, 0} = Traces.decode(request)
      spans
    end
    |> List.flatten()
  end
end
