defmodule Pulse.Storage.S3.TraceCompactorTest do
  use Pulse.Test.Case, async: true

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
