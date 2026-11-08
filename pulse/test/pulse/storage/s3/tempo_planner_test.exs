defmodule Pulse.Storage.S3.TempoPlannerTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Record.Span
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.TraceSummary
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.OTLPTraceFixture, as: Fixture
  alias Pulse.Traces.TempoSearch

  @query ~s'{resource.service.name="api"} with (most_recent=true)'

  setup do
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
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "planner-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    start_supervised!(ManifestSupervision)
    {:ok, [base], 0} = Traces.decode(Fixture.payload([Fixture.span(10)]))

    base = %{
      base
      | events: [],
        links: [],
        attributes: %{},
        otlp: %{base.otlp | "events" => [], "links" => [], "attributes" => []}
    }

    %{agent: agent, config: config, tenant: "planner-#{System.unique_integer([:positive])}", base: base}
  end

  @tag timeout: 120_000
  test "cold catalog over 1024 sources recovers earlier other-service context without a second GET", ctx do
    root = record(ctx.base, "edge", 1, 1, 1)
    child = record(ctx.base, "api", 1, 2, 100, root.span_id)
    noise = for n <- 2..1026, do: [record(ctx.base, "noise", n, n + 10, n + 200)]
    entries = seed(ctx, [[root]] ++ noise ++ [[child]])
    assert Enum.all?(entries, & &1.trace_summary.pruning_safe?)
    opts = [trace_start: 50, trace_end: 60, max_scan_segments: 2, limit: 1, spss: 3]
    {:ok, predicates} = TempoSearch.parse(@query)
    {:ok, expected} = TempoSearch.json([root, child] ++ List.flatten(noise), predicates, opts)
    assert {:ok, json} = S3.tempo_search_json(ctx.tenant, predicates, opts)
    assert Pulse.JSON.decode!(json) == Pulse.JSON.decode!(expected)
    assert %{"traces" => [%{"rootServiceName" => "edge"}]} = Pulse.JSON.decode!(json)
    assert Enum.sort(data_gets(ctx)) == Enum.sort([hd(entries).key, List.last(entries).key])
    assert Agent.get(ctx.agent, & &1.lists) == 0
  end

  test "proven nonmatching sources require no data GET, not an integrity scrub", ctx do
    entries = seed(ctx, for(n <- 1..5, do: [record(ctx.base, "noise", n, n, 10)]))
    Agent.update(ctx.agent, fn state -> %{state | objects: Map.drop(state.objects, Enum.map(entries, & &1.key))} end)
    assert {:ok, json} = query(ctx, max_scan_segments: 1)
    assert Pulse.JSON.decode!(json) == %{"traces" => []}
    assert data_gets(ctx) == []
  end

  test "complete newest traces fit their source budget without admitting older candidates", ctx do
    groups =
      for n <- 1..8 do
        for i <- 1..20, do: record(ctx.base, "api", n * 20 + i, n * 20 + i, n * 400 + i * 10)
      end

    entries = seed(ctx, groups)
    {:ok, predicates} = TempoSearch.parse("{}")

    for limit <- [1, 20] do
      opts = [trace_start: 1, trace_end: 4000, limit: limit, spss: 3]
      assert {:ok, expected} = TempoSearch.json(List.flatten(groups), predicates, opts)

      assert {:ok, json} =
               S3.tempo_search_json(
                 ctx.tenant,
                 predicates,
                 Keyword.merge(opts,
                   max_scan_segments: 1,
                   max_scan_bytes: List.last(entries).byte_size,
                   max_scan_rows: 20
                 )
               )

      assert Pulse.JSON.decode!(json) == Pulse.JSON.decode!(expected)
    end
  end

  test "a small first window expands when recovered trace starts change the newest result", ctx do
    root = record(ctx.base, "edge", 1, 1, 1)
    child = record(ctx.base, "api", 1, 2, 160, root.span_id)
    newest = record(ctx.base, "api", 2, 3, 120)
    seed(ctx, [[root], [newest], [child]])
    {:ok, predicates} = TempoSearch.parse(@query)
    opts = [trace_start: 1, trace_end: 200, limit: 1, spss: 3]
    assert {:ok, expected} = TempoSearch.json([root, newest, child], predicates, opts)

    assert {:ok, json} = query(ctx, limit: 1, max_scan_segments: 3)
    assert Pulse.JSON.decode!(json) == Pulse.JSON.decode!(expected)
    assert [%{"traceID" => "2"}] = Pulse.JSON.decode!(json)["traces"]
  end

  test "unknown, missing or malformed proof bits cannot infer original service types", ctx do
    seed(ctx, for(n <- 1..3, do: [record(ctx.base, "noise", n, n, 10)]))
    rewrite(ctx, fn segment -> %{segment | trace_summary: %{segment.trace_summary | pruning_safe?: false}} end)
    assert {:error, :query_scan_limit} = query(ctx, max_scan_segments: 1)
    assert length(data_gets(ctx)) == 1
    assert TraceSummary.parse(%{"v" => 1, "s" => ["noise"], "k" => "true"}).pruning_safe? == false
    assert TraceSummary.matches?(nil, proven_only: true, resource: %{"service.name" => "api"})
  end

  test "legacy nonmatches remain candidates and fail overlapping searches", ctx do
    legacy = %{record(ctx.base, "noise", 1, 1, 10) | otlp: nil}
    match = record(ctx.base, "api", 2, 2, 100)
    [old, _new] = seed(ctx, [[legacy], [match]])
    refute old.trace_summary.pruning_safe?
    assert {:error, :trace_metadata_unknown} = query(ctx)
    assert length(data_gets(ctx)) == 2
  end

  test "original string service disagreement prevents service-source omission", ctx do
    row = %{record(ctx.base, "api", 1, 1, 10) | service: "noise"}
    [entry] = seed(ctx, [[row]])
    refute entry.trace_summary.pruning_safe?
    assert {:ok, json} = query(ctx)
    assert %{"traces" => [_]} = Pulse.JSON.decode!(json)
    assert data_gets(ctx) == [entry.key]
  end

  test "attribute and regex selectors prune proven sources; candidate windows keep scan admission", ctx do
    seed(ctx, for(n <- 1..3, do: [record(ctx.base, "noise", n, n, 10)]))

    search = fn query ->
      TempoSearch.parse(query)
      |> elem(1)
      |> then(&S3.tempo_search_json(ctx.tenant, &1, trace_start: 1, trace_end: 200, max_scan_segments: 1))
    end

    assert {:ok, ~s'{"traces":[]}'} = search.(~s'{resource.service.name=~"api"} with (most_recent=true)')
    assert {:ok, ~s'{"traces":[]}'} = search.(~s'{span.request_kind="absent"}')
    assert data_gets(ctx) == []

    # Every source may match: admit the first source, then reject expansion
    # before reading beyond the segment budget.
    assert {:error, :query_scan_limit} = search.(~s'{resource.service.name=~"no.*"}')
    assert length(data_gets(ctx)) == 1
  end

  test "context GETs retain cumulative segment, byte and row limits", ctx do
    root = record(ctx.base, "edge", 1, 1, 1)
    child = record(ctx.base, "api", 1, 2, 100, root.span_id)
    entries = seed(ctx, [[root], [child]])
    bytes = Enum.sum(Enum.map(entries, & &1.byte_size))

    for opts <- [[max_scan_segments: 1], [max_scan_bytes: bytes - 1], [max_scan_rows: 1]] do
      Agent.update(ctx.agent, &%{&1 | requests: []})
      assert {:error, :query_scan_limit} = query(ctx, opts)
      assert data_gets(ctx) == [List.last(entries).key]
    end

    Agent.update(ctx.agent, &%{&1 | requests: []})
    assert {:ok, _} = query(ctx, max_scan_segments: 2, max_scan_rows: 2, max_scan_bytes: bytes)
    assert length(data_gets(ctx)) == 2
  end

  test "context actual footer rows charge even when the manifest undercounts", ctx do
    root = record(ctx.base, "edge", 1, 1, 1)
    child = record(ctx.base, "api", 1, 2, 100, root.span_id)
    seed(ctx, [[root, record(ctx.base, "edge", 99, 99, 10)], [child]])
    rewrite(ctx, &%{&1 | row_count: 1})
    assert {:error, :query_scan_limit} = query(ctx, max_scan_rows: 2)
    assert length(data_gets(ctx)) == 2
  end

  test "context missing-object retry resets native state but not spent provider work", ctx do
    root = record(ctx.base, "edge", 1, 1, 1)
    child = record(ctx.base, "api", 1, 2, 100, root.span_id)
    [entry, _child] = seed(ctx, [[root], [child]])

    for {maximum, result} <- [{3, :error}, {4, :ok}] do
      Agent.update(ctx.agent, &%{&1 | requests: [], faults: %{{"GET", entry.key} => {404, :before, 1}}})
      assert elem(query(ctx, max_scan_segments: maximum), 0) == result
      assert length(data_gets(ctx)) == maximum
    end
  end

  test "read context validates corrupt noncandidate payloads rather than returning clipped context", ctx do
    root = record(ctx.base, "edge", 1, 1, 1)
    child = record(ctx.base, "api", 1, 2, 100, root.span_id)
    [entry, _child] = seed(ctx, [[root], [child]])
    blob = File.read!(Path.expand("../../../fixtures/traces/trace-invalid-version.parquet", __DIR__))
    Agent.update(ctx.agent, &%{&1 | objects: Map.put(&1.objects, entry.key, {"corrupt-owned-source", blob})})
    assert {:error, {:decode_failed, _}} = query(ctx)
    assert length(data_gets(ctx)) == 2
  end

  defp query(ctx, opts \\ []) do
    {:ok, predicates} = TempoSearch.parse(@query)

    S3.tempo_search_json(
      ctx.tenant,
      predicates,
      Keyword.merge([trace_start: 1, trace_end: 200, limit: 100, spss: 3], opts)
    )
  end

  defp record(base, service, id, span, time, parent \\ nil) do
    resource =
      Enum.map(base.otlp["resource"], fn pair ->
        if pair["key"] == "service.name", do: %{pair | "value" => %{"stringValue" => service}}, else: pair
      end)

    %{
      base
      | service: service,
        resource: Map.put(base.resource, "service.name", service),
        trace_id: hex(id, 128),
        span_id: hex(span, 64),
        parent_span_id: parent,
        timestamp_ns: time,
        end_timestamp_ns: time + 10,
        name: "span-#{span}",
        otlp: %{base.otlp | "resource" => resource}
    }
  end

  defp hex(value, bits), do: Base.encode16(<<value::size(bits)>>, case: :lower)

  defp seed(ctx, batches) do
    assert :ok = S3.append(:traces, ctx.tenant, hd(batches))
    key = Manifest.manifest_key(ctx.tenant, "traces")
    {_, body} = Agent.get(ctx.agent, &Map.fetch!(&1.objects, key))
    {:ok, root} = Manifest.decode(body)
    template = hd(root.segments)

    entries =
      batches
      |> Enum.with_index()
      |> Enum.map(fn {rows, index} ->
        assert {:ok, blob, min, max, count, safe} = NIF.encode_trace_segment_parquet_v2(Enum.map(rows, &Span.to_map/1))

        segment = %{
          template
          | key: Path.join(Path.dirname(template.key), "#{min}-#{max}-#{index}-planner.parquet"),
            min_ts: min,
            max_ts: max,
            row_count: count,
            byte_size: byte_size(blob),
            trace_summary: TraceSummary.build(rows, safe)
        }

        {segment, blob}
      end)

    body = %{root | segments: Enum.map(entries, &elem(&1, 0))} |> Manifest.encode() |> IO.iodata_to_binary()

    Agent.update(ctx.agent, fn state ->
      objects =
        Enum.reduce(entries, state.objects, fn {segment, blob}, objects ->
          Map.put(objects, segment.key, {"owned-source", blob})
        end)

      %{state | objects: Map.put(objects, key, {"owned-authority", body}), reads: [], requests: [], lists: 0}
    end)

    restart_manifest()
    Enum.map(entries, &elem(&1, 0))
  end

  defp rewrite(ctx, fun) do
    key = Manifest.manifest_key(ctx.tenant, "traces")

    Agent.update(ctx.agent, fn state ->
      {_, body} = Map.fetch!(state.objects, key)
      {:ok, root} = Manifest.decode(body)
      body = %{root | segments: Enum.map(root.segments, fun)} |> Manifest.encode() |> IO.iodata_to_binary()
      %{state | objects: Map.put(state.objects, key, {"rewritten-owned-authority", body}), reads: [], requests: []}
    end)

    restart_manifest()
  end

  defp restart_manifest do
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
  end

  defp data_gets(ctx),
    do:
      Agent.get(ctx.agent, fn state ->
        for {"GET", key} <- state.requests, String.ends_with?(key, ".parquet"), do: key
      end)
end
