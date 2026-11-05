defmodule Pulse.Storage.S3.TracesTest do
  use Pulse.Test.Case, async: true

  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Record.SpanKey
  alias Pulse.Runtime
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.TraceSummary
  alias Pulse.Storage.SortOrder
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.OTLPTraceFixture, as: Fixture
  alias Pulse.Traces.Tempo
  alias Pulse.Traces.TempoSearch

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
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)

    start_supervised!(ManifestSupervision)
    tasks = start_supervised!(Task.Supervisor)
    tenant = "traces-#{System.unique_integer([:positive])}"
    {:ok, spans, 0} = Traces.decode(Fixture.payload([Fixture.span(10), Fixture.span(20)]))
    %{agent: agent, tenant: tenant, spans: spans, tasks: tasks}
  end

  @tag timeout: 120_000
  test "MCP limited searches retain only global top-k across 150k overlapping spans", ctx do
    [base | _] = ctx.spans
    # Rich tags duplicate projected attributes. Keep explicit headroom under
    # the unchanged 16 MiB full-key/result budgets for 5,000 surviving rows.
    attrs = Map.new(1..12, &{"attr.#{&1}", "v#{&1}"})
    typed = attrs |> Map.new(fn {key, value} -> {key, %{"stringValue" => value}} end) |> Fixture.pairs()
    otlp = %{base.otlp | "attributes" => typed, "events" => [], "links" => []}
    assert SpanKey.size(%{base | attributes: attrs, events: [], links: [], otlp: otlp}) * 5000 < 16_777_216

    for segment <- 1..30 do
      records =
        for row <- 1..5000 do
          %{
            base
            | timestamp_ns: 1_700_000_000_000_000_000 + row * 1000 + segment,
              end_timestamp_ns: 1_700_000_000_000_001_000 + row * 1000 + segment,
              trace_id: Base.encode16(<<segment::64, row::64>>, case: :lower),
              attributes: attrs,
              events: [],
              links: [],
              otlp: otlp
          }
        end

      assert :ok = S3.append(:traces, ctx.tenant, records)
    end

    assert {:ok, [%{"text" => text}]} =
             Tools.call("query_traces", %{
               "tenant" => ctx.tenant,
               "service" => "tuist-server",
               "limit" => 10,
               "fields" => ["timestamp_ns", "trace_id", "duration_ns"]
             })

    rows = Pulse.JSON.decode!(text)
    assert Enum.map(rows, & &1["timestamp_ns"]) == Enum.map(30..21//-1, &(1_700_000_000_005_000_000 + &1))
    assert Enum.all?(rows, &(&1["duration_ns"] == 1000))

    assert {:ok, [%{"text" => large}]} =
             Tools.call("query_traces", %{"tenant" => ctx.tenant, "limit" => 5000, "fields" => ["timestamp_ns"]})

    expected = for segment <- 1..30, row <- 1..5000, do: 1_700_000_000_000_000_000 + row * 1000 + segment
    assert Enum.map(Pulse.JSON.decode!(large), & &1["timestamp_ns"]) == expected |> Enum.sort(:desc) |> Enum.take(5000)
    # The full-metadata response stays native too, even with a deliberately
    # small BEAM heap. The off-heap result has its own native byte ceiling.
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_heap_words: 200_000)
    assert {:ok, [%{"text" => full}]} = Tools.call("query_traces", %{"tenant" => ctx.tenant, "limit" => 5000})
    assert length(Pulse.JSON.decode!(full)) == 5000
    assert {:error, :query_sample_limit} = Tools.call("query_traces", %{"tenant" => ctx.tenant})
  end

  test "MCP projections budget returned fields and keep canonical order for conflicting copies", ctx do
    attrs = 1..25 |> Map.new(&{"attr.#{&1}", %{"stringValue" => "v#{&1}"}}) |> Fixture.pairs()
    raw = Fixture.span() |> Map.merge(%{"attributes" => attrs, "events" => [], "links" => []})
    id = &Base.encode16(<<&1::128>>, case: :lower)
    at = &Map.merge(raw, %{"traceId" => id.(&1), "startTimeUnixNano" => "#{&1}", "endTimeUnixNano" => "#{&1 + 1000}"})

    records =
      for chunk <- Enum.chunk_every(1..5000, 500) do
        assert {:ok, spans, 0} = Traces.decode(Fixture.payload(Enum.map(chunk, at)))
        spans
      end
      |> List.flatten()

    assert SpanKey.size(hd(records)) * 5000 > 16_777_216
    assert :ok = S3.append(:traces, ctx.tenant, records)
    call = &Tools.call("query_traces", Map.merge(%{"tenant" => ctx.tenant, "limit" => 5000}, &1))
    assert {:error, :query_resource_limit} = call.(%{})
    assert {:ok, [%{"text" => text}]} = call.(%{"fields" => ["trace_id", "duration_ns"]})
    rows = Pulse.JSON.decode!(text)
    assert length(rows) == 5000
    assert hd(rows) == %{"trace_id" => id.(5000), "duration_ns" => 1000}

    # A different stored copy of the newest span (same start, trace and span
    # ID) forces the complete-key rerun; both orders match the canonical one.
    assert {:ok, [copy], 0} = Traces.decode(Fixture.payload([Map.put(at.(5000), "name", "retried")]))
    assert :ok = S3.append(:traces, ctx.tenant, [copy])
    ordered = SortOrder.sort([List.last(records), copy], :traces)
    assert {:ok, [%{"text" => text}]} = call.(%{"limit" => 2, "fields" => ["name"]})
    assert Pulse.JSON.decode!(text) == Enum.map(ordered, &%{"name" => &1.name})
    assert {:ok, [%{"text" => text}]} = call.(%{"limit" => 1, "fields" => ["name"]})
    assert Pulse.JSON.decode!(text) == [%{"name" => hd(ordered).name}]
  end

  @tag timeout: 120_000
  test "cold-manifest trace lookup prunes over 1024 segments without partial scans", ctx do
    [base | _] = ctx.spans

    # This tests cold pruning, not 1030 serial CAS publications. Seed actual
    # encoded objects and a coherent owned authority after one public append.
    assert :ok = S3.append(:traces, ctx.tenant, [%{base | trace_id: Base.encode16(<<1::128>>, case: :lower)}])
    key = Manifest.manifest_key(ctx.tenant, "traces")
    {_, body} = Agent.get(ctx.agent, &Map.fetch!(&1.objects, key))
    {:ok, root} = Manifest.decode(body)
    template = hd(root.segments)

    entries =
      for n <- 1..1030 do
        record = %{base | trace_id: Base.encode16(<<n::128>>, case: :lower)}
        {:ok, blob, _, _} = S3.encode_segment(:traces, [record])

        segment = %{
          template
          | key: String.replace_suffix(template.key, ".parquet", "-#{n}.parquet"),
            byte_size: byte_size(blob),
            trace_summary: TraceSummary.build([record])
        }

        {segment, blob}
      end

    Agent.update(ctx.agent, fn state ->
      objects =
        Enum.reduce(entries, state.objects, fn {segment, blob}, objects ->
          Map.put(objects, segment.key, {"fixture", blob})
        end)

      body = %{root | segments: Enum.map(entries, &elem(&1, 0))} |> Manifest.encode() |> IO.iodata_to_binary()
      %{state | objects: Map.put(objects, key, {"seeded-authority", body})}
    end)

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    id = Base.encode16(<<1::128>>, case: :lower)
    assert {:ok, [%{trace_id: ^id}]} = S3.query(:traces, ctx.tenant, trace_id: id, max_scan_segments: 1)
    assert {:ok, [%{"text" => text}]} = Tools.call("query_traces", %{"tenant" => ctx.tenant, "trace_id" => id})
    assert [%{"trace_id" => ^id}] = Pulse.JSON.decode!(text)
    assert {:error, :query_scan_limit} = S3.query(:traces, ctx.tenant, max_scan_segments: 1024)
    # Same-time old spans cannot be skipped: metadata ties may outrank a hit.
    assert {:error, :query_scan_limit} =
             S3.query(:traces, ctx.tenant, service: "tuist-server", limit: 1, max_scan_segments: 1)

    latest = %{base | timestamp_ns: 100, end_timestamp_ns: 1100}
    assert :ok = S3.append(:traces, ctx.tenant, [latest])
    assert {:ok, [^latest]} = S3.query(:traces, ctx.tenant, service: "tuist-server", limit: 1, max_scan_segments: 1)

    assert {:error, :query_scan_limit} =
             S3.query(:traces, ctx.tenant, service: "tuist-server", limit: 1, max_scan_rows: 0)
  end

  test "resource service.name filters skip proven sources of other services", ctx do
    [base | _] = ctx.spans
    services = ["kura-cache-0", "tuist-server", "kura-meta-1", "noise"]

    rows =
      for n <- 1..24 do
        service = Enum.at(services, rem(n, 4))

        resource =
          Enum.map(base.otlp["resource"], fn pair ->
            if pair["key"] == "service.name", do: %{pair | "value" => %{"stringValue" => service}}, else: pair
          end)

        %{
          base
          | service: service,
            resource: Map.put(base.resource, "service.name", service),
            trace_id: Base.encode16(<<n::128>>, case: :lower),
            timestamp_ns: n * 1000,
            end_timestamp_ns: n * 1000 + 10,
            otlp: %{base.otlp | "resource" => resource}
        }
      end

    Enum.each(rows, &assert(:ok == S3.append(:traces, ctx.tenant, [&1])))
    {:ok, entry} = ManifestOwner.ensure_loaded(ctx.tenant, "traces", Runtime.get_env(:pulse, S3))
    assert Enum.all?(entry.manifest.segments, & &1.trace_summary.pruning_safe?)

    query = fn opts ->
      Agent.update(ctx.agent, &%{&1 | reads: []})
      {:ok, spans} = S3.query(:traces, ctx.tenant, Keyword.merge([start_ts: 0, end_ts: 100_000, limit: 50], opts))
      reads = Agent.get(ctx.agent, fn state -> Enum.count(state.reads, &String.ends_with?(&1, ".parquet")) end)
      {spans |> Enum.map(& &1.service) |> Enum.frequencies(), reads}
    end

    # Only the 12 kura sources can hold a match; the rest are never read.
    assert query.(resource_regex: %{"service.name" => "kura-(.*)-.*"}) ==
             {%{"kura-cache-0" => 6, "kura-meta-1" => 6}, 12}

    assert query.(resource: %{"service.name" => "noise"}) == {%{"noise" => 6}, 6}
    assert query.(resource_regex: %{"service.name" => "missing.*"}) == {%{}, 0}

    # Other resource keys prune through their own complete value sets.
    assert {%{}, 0} = query.(resource_regex: %{"service.namespace" => "kura"})
    assert {_, 24} = query.(resource: %{"service.namespace" => "tuist"})

    tempo = fn selector ->
      {:ok, predicates} = TempoSearch.parse(selector)
      Agent.update(ctx.agent, &%{&1 | reads: []})
      {:ok, json} = S3.tempo_search_json(ctx.tenant, predicates, trace_start: 0, trace_end: 0, limit: 20, spss: 1)
      reads = Agent.get(ctx.agent, fn state -> Enum.count(state.reads, &String.ends_with?(&1, ".parquet")) end)
      {length(Pulse.JSON.decode!(json)["traces"]), reads}
    end

    # Tempo original-string selectors prune the same proven sources.
    assert tempo.(~s|{resource.service.namespace=~"kura.*"}|) == {0, 0}
    assert tempo.(~s|{resource.service.name=~"kura-(.*)-.*" && span.request_kind="api"}|) == {12, 12}

    # Without the proof that the promoted service is the original string
    # service.name, or a resource value set, sources are read.
    Agent.update(ctx.agent, fn state ->
      key = Manifest.manifest_key(ctx.tenant, "traces")
      {etag, body} = Map.fetch!(state.objects, key)
      {:ok, root} = Manifest.decode(body)

      segments =
        Enum.map(root.segments, &%{&1 | trace_summary: %{&1.trace_summary | pruning_safe?: false, attributes: nil}})

      body = %{root | segments: segments} |> Manifest.encode() |> IO.iodata_to_binary()
      %{state | objects: Map.put(state.objects, key, {etag <> "-unproven", body})}
    end)

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert query.(resource: %{"service.name" => "noise"}) == {%{"noise" => 6}, 24}
    # Unproven sources may hold legacy rows: every one is a Tempo candidate.
    assert tempo.(~s|{resource.service.namespace=~"kura.*"}|) == {0, 24}
  end

  @tag timeout: 120_000
  test "limited span queries skip sources and manifest leaves without a matching attribute value", ctx do
    [base | _] = ctx.spans

    # 600 one-span pushes, as exporters produce them: more than the inline
    # tail holds, so older segments live in leaf pages. Kura pushes carry
    # health-check routes; one in 50 is a cache request. The oldest push has
    # a distinctly named span.
    span = fn n ->
      kura? = rem(n, 2) == 0
      route = if rem(n, 50) == 0, do: "/api/cache/cas/{id}", else: if(kura?, do: "/up", else: "/api/runs")
      {service, namespace} = if kura?, do: {"kura-eu-#{rem(n, 3)}", "kura"}, else: {"tuist-server", "tuist"}

      resource =
        Enum.map(base.otlp["resource"], fn
          %{"key" => "service.name"} = pair -> %{pair | "value" => %{"stringValue" => service}}
          %{"key" => "service.namespace"} = pair -> %{pair | "value" => %{"stringValue" => namespace}}
          pair -> pair
        end)

      typed = [%{"key" => "http.route", "value" => %{"stringValue" => route}} | base.otlp["attributes"]]

      %{
        base
        | service: service,
          name: if(n == 1, do: "oldest", else: base.name),
          resource: %{base.resource | "service.name" => service, "service.namespace" => namespace},
          attributes: Map.put(base.attributes, "http.route", route),
          trace_id: Base.encode16(<<n::128>>, case: :lower),
          timestamp_ns: n * 1000,
          end_timestamp_ns: n * 1000 + 10,
          otlp: %{base.otlp | "resource" => resource, "attributes" => typed}
      }
    end

    1..600
    |> Task.async_stream(&S3.append(:traces, ctx.tenant, [span.(&1)]), max_concurrency: 8, timeout: :infinity)
    |> Enum.each(&assert(&1 == {:ok, :ok}))

    leaves =
      Agent.get(ctx.agent, fn state ->
        state.objects |> Map.keys() |> Enum.count(&String.ends_with?(&1, "-leaf.json"))
      end)

    assert leaves > 0

    query = fn opts ->
      :ok = S3.MetadataCache.clear()
      Agent.update(ctx.agent, &%{&1 | reads: []})
      result = S3.query(:traces, ctx.tenant, Keyword.merge([start_ts: 0, end_ts: 1_000_000, limit: 50], opts))
      reads = Agent.get(ctx.agent, & &1.reads)

      {result, Enum.count(reads, &String.ends_with?(&1, ".parquet")),
       Enum.count(reads, &String.ends_with?(&1, "-leaf.json"))}
    end

    starts = fn {:ok, spans} -> Enum.map(spans, & &1.timestamp_ns) end

    # Unfiltered: the newest candidates are planned from the inline tail and
    # the scan stops after 50 one-span segments; no leaf is read.
    {result, reads, pages} = query.([])
    assert starts.(result) == Enum.map(600..551//-1, &(&1 * 1000))
    assert {reads, pages} == {50, 0}

    # The Grafana Kura cache panel: only the 12 cache segments are read.
    kura = [
      resource: %{"service.namespace" => "kura"},
      resource_regex: %{"service.name" => "kura-(.*)-.*"},
      attributes_regex: %{"http.route" => "/api/cache.*|/api/metro/cache.*|/v1/cache.*"}
    ]

    {result, reads, _pages} = query.(kura)
    assert starts.(result) == Enum.map(600..50//-50, &(&1 * 1000))
    assert reads == 12

    # Values no source holds read neither segments nor leaves.
    assert {{:ok, []}, 0, 0} = query.(attributes: %{"http.route" => "/v1/cache/{hash}"})
    assert {{:ok, []}, 0, 0} = query.(resource: %{"service.namespace" => "missing"})
    assert {{:ok, []}, 0, 0} = query.(attributes_regex: %{"missing.key" => ".*"})

    # A filter no summary decides visits every candidate, window after
    # window, and still finds the oldest span.
    {result, reads, pages} = query.(name: "oldest")
    assert starts.(result) == [1000]
    assert {reads, pages} == {600, leaves}

    # Visited segments count across windows.
    assert {{:error, :query_scan_limit}, _, _} = query.(name: "oldest", max_scan_segments: 100)
    assert %{limit: :max_scan_segments, observed: 101, stage: :visited} = Pulse.QueryLimit.take()
  end

  @tag timeout: 120_000
  test "Tempo searches plan matching sources newest first and read only candidate trace context", ctx do
    [base | _] = ctx.spans

    # 601 pushes of one root span each; every 50th is a Kura cache request
    # whose child span arrives with the next push, so complete context lives
    # in a source the predicates prune.
    span = fn n, child? ->
      kura? = rem(n, 2) == 0

      route =
        cond do
          child? -> "/internal"
          rem(n, 50) == 0 -> "/api/cache/cas/{id}"
          kura? -> "/up"
          true -> "/api/runs"
        end

      {service, namespace} = if kura?, do: {"kura-eu-#{rem(n, 3)}", "kura"}, else: {"tuist-server", "tuist"}

      resource =
        Enum.map(base.otlp["resource"], fn
          %{"key" => "service.name"} = pair -> %{pair | "value" => %{"stringValue" => service}}
          %{"key" => "service.namespace"} = pair -> %{pair | "value" => %{"stringValue" => namespace}}
          pair -> pair
        end)

      typed = [%{"key" => "http.route", "value" => %{"stringValue" => route}} | base.otlp["attributes"]]
      ts = n * 1000 + if(child?, do: 1, else: 0)

      %{
        base
        | service: service,
          resource: %{base.resource | "service.name" => service, "service.namespace" => namespace},
          attributes: Map.put(base.attributes, "http.route", route),
          trace_id: Base.encode16(<<n::128>>, case: :lower),
          span_id: Base.encode16(<<n::32, if(child?, do: 2, else: 1)::32>>, case: :lower),
          parent_span_id: if(child?, do: Base.encode16(<<n::32, 1::32>>, case: :lower)),
          timestamp_ns: ts,
          end_timestamp_ns: ts + 10,
          otlp: %{base.otlp | "resource" => resource, "attributes" => typed}
      }
    end

    push = fn n ->
      if rem(n - 1, 50) == 0 and n > 1, do: [span.(n, false), span.(n - 1, true)], else: [span.(n, false)]
    end

    1..601
    |> Task.async_stream(&S3.append(:traces, ctx.tenant, push.(&1)), max_concurrency: 8, timeout: :infinity)
    |> Enum.each(&assert(&1 == {:ok, :ok}))

    leaves =
      Agent.get(ctx.agent, fn state ->
        state.objects |> Map.keys() |> Enum.count(&String.ends_with?(&1, "-leaf.json"))
      end)

    assert leaves > 0

    search = fn query, limit ->
      {:ok, predicates} = TempoSearch.parse(query)
      :ok = S3.MetadataCache.clear()
      Agent.update(ctx.agent, &%{&1 | reads: []})
      result = S3.tempo_search_json(ctx.tenant, predicates, trace_start: 0, trace_end: 0, limit: limit, spss: 3)
      reads = Agent.get(ctx.agent, & &1.reads)

      traces =
        with {:ok, json} <- result do
          for trace <- Pulse.JSON.decode!(json)["traces"] do
            {String.to_integer(trace["traceID"], 16),
             trace["serviceStats"] |> Map.values() |> Enum.map(& &1["spanCount"])}
          end
        end

      # The same answer as the reference search over every stored span.
      opts = [trace_start: 0, trace_end: 0, limit: limit, spss: 3]
      {:ok, expected} = TempoSearch.json(Enum.flat_map(1..601, push), predicates, opts)
      if match?({:ok, _}, result), do: assert(Pulse.JSON.decode!(elem(result, 1)) == Pulse.JSON.decode!(expected))

      {traces, Enum.count(reads, &String.ends_with?(&1, ".parquet")),
       Enum.count(reads, &String.ends_with?(&1, "-leaf.json"))}
    end

    kura = ~s|{resource.service.namespace="kura" && span.http.route=~"/api/cache.*"}|

    # The newest four cache sources answer: the fifth ends before the fourth
    # trace starts. Each trace's child comes from the pruned source after it.
    assert {[{600, [2]}, {550, [2]}, {500, [2]}, {450, [2]}], 8, pages} = search.(kura, 4)
    assert pages < leaves

    # Fewer matches than the limit visit every candidate, once: the second
    # round reuses what the first read.
    {traces, reads, _pages} = search.(kura, 20)
    assert traces == Enum.map(600..50//-50, &{&1, [2]})
    assert reads == 24

    # Values no source holds read neither segments nor leaves.
    assert {[], 0, 0} = search.(~s|{span.http.route="/v1/cache/{hash}"}|, 20)
    assert {[], 0, 0} = search.(~s|{resource.service.namespace="missing"}|, 20)

    # Expressions prune nothing but still stop after the newest window.
    assert {[{601, [1]}, {600, [2]}], 4, _} = search.(~s|{span.http.route!="none"}|, 2)
  end

  test "trace search scans every object before limiting traces; one hot trace cannot hide another", ctx do
    [base | _] = ctx.spans
    a = %{base | trace_id: Base.encode16(<<1::128>>, case: :lower), timestamp_ns: 1000, end_timestamp_ns: 2000}
    b = %{base | trace_id: Base.encode16(<<2::128>>, case: :lower), timestamp_ns: 100, end_timestamp_ns: 1100}
    for count <- [2000, 2000, 1001], do: assert(:ok = S3.append(:traces, ctx.tenant, List.duplicate(a, count)))
    assert :ok = S3.append(:traces, ctx.tenant, [b])

    resource =
      Enum.map(a.otlp["resource"], fn pair ->
        if pair["key"] == "service.namespace", do: %{pair | "value" => %{"stringValue" => "other"}}, else: pair
      end)

    context = %{
      a
      | timestamp_ns: 1,
        end_timestamp_ns: 1001,
        resource: Map.put(a.resource, "service.namespace", "other"),
        otlp: Map.put(a.otlp, "resource", resource)
    }

    assert :ok = S3.append(:traces, ctx.tenant, [context])

    args = %{
      "tenant" => ctx.tenant,
      "query" => ~s'{resource.service.namespace="tuist"} with (most_recent=true)',
      "start_ts_ns" => 0,
      "end_ts_ns" => 3000,
      "limit" => 2
    }

    Runtime.put_env(:pulse, Pulse.QueryRunner, max_heap_words: 200_000)
    assert {:ok, [%{"text" => text}]} = Tools.call("search_traces", args)
    result = Pulse.JSON.decode!(text)
    assert result["matched_trace_count"] == 2
    assert [row_b, row_a] = result["traces"]
    assert row_b["trace_id"] == b.trace_id
    assert row_a["trace_id"] == a.trace_id
    assert row_a["start_timestamp_ns"] == 1
    assert row_a["stored_span_count"] == 5002
    assert row_a["matching_span_count"] == 5001
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_segments: 1)
    assert {:error, :query_scan_limit} = Tools.call("search_traces", Map.put(args, "limit", 1))
  end

  test "search missing-object retry restarts native grouping and charges earlier work", ctx do
    [base | _] = ctx.spans
    a = %{base | trace_id: Base.encode16(<<1::128>>, case: :lower), timestamp_ns: 20, end_timestamp_ns: 1020}
    b = %{base | trace_id: Base.encode16(<<2::128>>, case: :lower), timestamp_ns: 10, end_timestamp_ns: 1010}
    assert :ok = S3.append(:traces, ctx.tenant, [a])
    assert :ok = S3.append(:traces, ctx.tenant, [b])

    key =
      Agent.get(ctx.agent, fn state ->
        Enum.find(
          Map.keys(state.objects),
          &(String.ends_with?(&1, ".parquet") and String.contains?(&1, "00000000000000000010-"))
        )
      end)

    assert is_binary(key)
    Agent.update(ctx.agent, &%{&1 | faults: %{{"GET", key} => {404, :before, 1}}})
    args = %{"tenant" => ctx.tenant, "query" => ~s'{span.request_kind="api"}', "start_ts_ns" => 0, "end_ts_ns" => 30}
    assert {:ok, [%{"text" => text}]} = Tools.call("search_traces", args)
    result = Pulse.JSON.decode!(text)
    assert result["matched_trace_count"] == 2
    assert Enum.map(result["traces"], & &1["stored_span_count"]) == [1, 1]
    Agent.update(ctx.agent, &%{&1 | faults: %{{"GET", key} => {404, :before, 1}}})
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_segments: 3)
    assert {:error, :query_scan_limit} = Tools.call("search_traces", args)
  end

  test "search charges actual footer rows even when a manifest undercounts them", ctx do
    assert :ok = S3.append(:traces, ctx.tenant, ctx.spans)
    key = Manifest.manifest_key(ctx.tenant, "traces")

    Agent.update(ctx.agent, fn state ->
      {etag, body} = Map.fetch!(state.objects, key)
      {:ok, root} = Manifest.decode(body)
      root = %{root | segments: Enum.map(root.segments, &%{&1 | row_count: 1})}
      body = root |> Manifest.encode() |> IO.iodata_to_binary()
      %{state | objects: Map.put(state.objects, key, {etag <> "-undercount", body})}
    end)

    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 1)
    args = %{"tenant" => ctx.tenant, "query" => ~s'{span.request_kind="api"}', "start_ts_ns" => 0, "end_ts_ns" => 30}
    assert {:error, :query_scan_limit} = Tools.call("search_traces", args)

    assert {:error, :query_scan_limit} =
             Tools.call("get_trace", %{"tenant" => ctx.tenant, "trace_id" => hd(ctx.spans).trace_id})

    assert {:error, :query_scan_limit} = Tempo.lookup(ctx.tenant, hd(ctx.spans).trace_id, "protobuf_v2")
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    args = %{args | "query" => args["query"] <> " with (most_recent=true)", "start_ts_ns" => 1}
    assert {:error, :query_scan_limit} = Tools.call("search_trace_metadata", args)
    assert {:error, :query_scan_limit} = Tools.call("discover_trace_tags", %{"tenant" => ctx.tenant, "scope" => "span"})
    assert {:error, :query_scan_limit} = Tools.call("discover_trace_tags", %{"tenant" => ctx.tenant})

    assert {:error, :query_scan_limit} =
             Tools.call("discover_trace_tag_values", %{"tenant" => ctx.tenant, "scope" => "none", "key" => "shared"})

    assert {:error, :query_scan_limit} =
             Tools.call("discover_trace_tag_values", %{"tenant" => ctx.tenant, "scope" => "intrinsic", "key" => "name"})

    assert {:error, :query_scan_limit} =
             Tools.call("discover_trace_tags", %{
               "tenant" => ctx.tenant,
               "query" => ~s'{resource.service.name="absent"}'
             })

    assert {:error, :query_scan_limit} =
             Tools.call("discover_trace_tags", %{
               "tenant" => ctx.tenant,
               "scope" => "resource",
               "query" => ~s'{resource.service.name="absent"}'
             })

    assert {:error, :query_scan_limit} =
             Tools.call("discover_trace_tags", %{"tenant" => ctx.tenant, "scope" => "instrumentation"})

    assert {:error, :query_scan_limit} =
             Tools.call("discover_trace_tag_values", %{
               "tenant" => ctx.tenant,
               "scope" => "span",
               "key" => "request_kind",
               "query" => ~s'{resource.service.name="absent"}'
             })

    for {start, finish} <- [{1, 30}, {100, 200}],
        {tool, target} <- [
          {"discover_trace_tags", %{}},
          {"discover_trace_tags", %{"scope" => "span", "query" => ~s'{resource.service.name="absent"}'}},
          {"discover_trace_tag_values", %{"scope" => "none", "key" => "shared"}},
          {"discover_trace_tag_values",
           %{"scope" => "none", "key" => "shared", "query" => ~s'{resource.service.name="absent"}'}},
          {"discover_trace_tag_values", %{"scope" => "intrinsic", "key" => "name"}},
          {"discover_trace_tag_values", %{"scope" => "intrinsic", "key" => "rootName"}},
          {"discover_trace_tag_values", %{"scope" => "intrinsic", "key" => "trace:duration"}},
          {"discover_trace_tag_values",
           %{"scope" => "intrinsic", "key" => "trace:duration", "query" => ~s'{resource.service.name="absent"}'}},
          {"discover_trace_tag_values",
           %{"scope" => "intrinsic", "key" => "trace:rootService", "query" => ~s'{resource.service.name="absent"}'}},
          {"discover_trace_tag_values", %{"scope" => "intrinsic", "key" => "event:timeSinceStart"}},
          {"discover_trace_tag_values",
           %{"scope" => "intrinsic", "key" => "event:timeSinceStart", "query" => ~s'{resource.service.name="absent"}'}}
        ] do
      args = Map.merge(target, %{"tenant" => ctx.tenant, "start_ts_ns" => start, "end_ts_ns" => finish})
      assert {:error, :query_scan_limit} = Tools.call(tool, args)
    end

    assert Agent.get(ctx.agent, fn state -> Enum.any?(state.reads, &String.ends_with?(&1, ".parquet")) end)
  end

  test "filtered discovery refuses corrupt nonmatching stored data instead of publishing an empty set", ctx do
    assert :ok = S3.append(:traces, ctx.tenant, ctx.spans)
    blob = File.read!(Path.expand("../../../fixtures/traces/trace-invalid-version.parquet", __DIR__))

    Agent.update(ctx.agent, fn state ->
      objects =
        Map.new(state.objects, fn {key, value} ->
          if String.ends_with?(key, ".parquet"), do: {key, {"corrupt-fixture", blob}}, else: {key, value}
        end)

      %{state | objects: objects}
    end)

    Runtime.put_env(:pulse, TempoSearch, enabled: true)

    args = %{
      "tenant" => ctx.tenant,
      "scope" => "span",
      "key" => "retries",
      "query" => ~s'{resource.service.name="absent"}'
    }

    assert {:error, {:decode_failed, _}} = Tools.call("discover_trace_tag_values", args)
  end

  test "Tempo captured-input budget is clamped before reads and lower budgets survive lying sizes", ctx do
    assert :ok = S3.append(:traces, ctx.tenant, ctx.spans)
    key = Manifest.manifest_key(ctx.tenant, "traces")
    {:ok, predicates} = TempoSearch.parse(~s'{span.request_kind="api"} with (most_recent=true)')

    for {declared, allowed} <- [{33_554_433, 134_217_728}, {1, 1}] do
      Agent.update(ctx.agent, fn state ->
        {etag, body} = Map.fetch!(state.objects, key)
        {:ok, root} = Manifest.decode(body)
        root = %{root | segments: Enum.map(root.segments, &%{&1 | byte_size: declared})}
        body = root |> Manifest.encode() |> IO.iodata_to_binary()
        %{state | objects: Map.put(state.objects, key, {etag <> "-sized", body}), reads: []}
      end)

      assert :ok = stop_supervised(ManifestSupervision)
      start_supervised!(ManifestSupervision)

      assert {:error, :query_scan_limit} =
               S3.tempo_search_json(ctx.tenant, predicates,
                 trace_start: 1,
                 trace_end: 30,
                 limit: 100,
                 spss: 3,
                 max_scan_bytes: allowed
               )

      parquet_read? = Agent.get(ctx.agent, &Enum.any?(&1.reads, fn key -> String.ends_with?(key, ".parquet") end))
      assert parquet_read? == (declared == 1)
    end
  end

  test "legacy entries recover row counts from the footer before charging scan budgets", ctx do
    assert :ok = S3.append(:traces, ctx.tenant, ctx.spans)
    key = Manifest.manifest_key(ctx.tenant, "traces")

    Agent.update(ctx.agent, fn state ->
      {etag, body} = Map.fetch!(state.objects, key)
      {:ok, manifest} = Manifest.decode(body)
      segments = Enum.map(manifest.segments, &%{&1 | row_count: nil, trace_summary: nil})
      body = %{manifest | segments: segments} |> Manifest.encode() |> IO.iodata_to_binary()
      %{state | objects: Map.put(state.objects, key, {etag, body})}
    end)

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert {:error, :query_scan_limit} = S3.query(:traces, ctx.tenant, limit: 1, max_scan_rows: 1)
    assert {:ok, [%{timestamp_ns: 20}]} = S3.query(:traces, ctx.tenant, limit: 1, max_scan_rows: 2)
  end

  test "get_trace stops reading segments once a trace exceeds 5,000 spans", ctx do
    [base | _] = ctx.spans

    for segment <- 1..60 do
      spans =
        for row <- 1..100 do
          ts = 1_700_000_000_000_000_000 + segment * 1_000_000 + row

          %{
            base
            | timestamp_ns: ts,
              end_timestamp_ns: ts + 1,
              span_id: Base.encode16(<<segment::32, row::32>>, case: :lower)
          }
        end

      assert :ok = S3.append(:traces, ctx.tenant, spans, [])
    end

    Agent.update(ctx.agent, &%{&1 | reads: []})

    assert {:error, :query_sample_limit} =
             Tools.call("get_trace", %{"tenant" => ctx.tenant, "trace_id" => base.trace_id})

    reads = Agent.get(ctx.agent, fn state -> Enum.count(state.reads, &String.ends_with?(&1, ".parquet")) end)
    assert reads in 51..59
  end

  # Converting the 20,000-entry flat history into pages takes about 25 s on an
  # idle two-core machine and longer under CI contention. The heap cap, not
  # the time, is what this test checks.
  @tag timeout: 300_000
  test "appends never copy a large cached flat manifest into the request process", ctx do
    # Retain-forever flat manifests gain one entry per append. Ingest must not
    # deep-copy them out of the cache per request: Alloy keeps many keep-alive
    # connection processes, and each copy outlived the request as garbage.
    config = Map.new(Runtime.get_env(:pulse, S3))
    prefix = "tenants/#{ctx.tenant}/v4/signal=traces/date=2023-11-14/hour=22/"
    ids = for n <- 1..40, do: Base.encode16(<<n::128>>, case: :lower)

    segments =
      for n <- 1..20_000 do
        min = 1_700_000_000_000_000_000 + n * 1_000_000_000

        "#{prefix}#{min}-#{min + 999}-#{n}.parquet"
        |> Segment.build(min, min + 999, 150, 40_000)
        |> Map.put(:trace_summary, TraceSummary.from_values(["tuist-server"], ids))
      end

    body = IO.iodata_to_binary(Manifest.encode(%{Manifest.new() | segments: Enum.reverse(segments)}))
    assert {:ok, _etag} = Pulse.ObjectStore.put(config, Manifest.manifest_key(ctx.tenant, "traces"), body)
    assert {:ok, %{manifest: cached}} = ManifestOwner.ensure_loaded(ctx.tenant, "traces", config)
    assert length(cached.segments) == 20_000
    cap = div(:erts_debug.size(cached), 4)

    task =
      Task.Supervisor.async_nolink(ctx.tasks, fn ->
        Process.flag(:max_heap_size, %{size: cap, kill: true, error_logger: false})
        S3.append(:traces, ctx.tenant, ctx.spans, [])
      end)

    assert Task.await(task, 240_000) == :ok
    assert {:ok, %{manifest: manifest}} = ManifestOwner.ensure_loaded(ctx.tenant, "traces", config)
    # That append converted the flat history into pages; the root lists only its tail.
    assert manifest.version == 4
    assert JournalManifest.referenced(manifest) == 20_001
  end

  test "ack follows segment PUT and manifest CAS, retries deduplicate, and filters isolate signals", ctx do
    manifest_key = Manifest.manifest_key(ctx.tenant, "traces")
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", manifest_key} => owner}})

    task =
      Task.Supervisor.async_nolink(ctx.tasks, fn ->
        S3.append(:traces, ctx.tenant, ctx.spans, idempotency_key: "retry")
      end)

    assert_receive {:storage_barrier, writer, "PUT", ^manifest_key}, 30_000
    assert Task.yield(task, 0) == nil
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    send(writer, {:release_storage, manifest_key})
    assert Task.await(task, 10_000) == :ok
    assert :ok = S3.append(:traces, ctx.tenant, ctx.spans, idempotency_key: "retry")
    assert {:ok, rows} = S3.query(:traces, ctx.tenant, trace_id: Fixture.trace_id())
    assert Enum.map(rows, & &1.timestamp_ns) == [20, 10]

    assert {:ok, [%{timestamp_ns: 10}]} =
             S3.query(:traces, ctx.tenant,
               start_ts: 10,
               end_ts: 10,
               service: "tuist-server",
               attributes: %{"metrics.skip" => false}
             )

    assert {:ok, []} = S3.query(:traces, ctx.tenant, service: "other")
    assert {:ok, []} = S3.query(:traces, "other", [])
    assert {:ok, []} = S3.query(:logs, ctx.tenant, [])
    assert {:ok, []} = S3.query(:metrics, ctx.tenant, [])
    assert {:error, :query_scan_limit} = S3.query(:traces, ctx.tenant, max_scan_rows: 1)
    assert {:error, :query_sample_limit} = S3.query(:traces, ctx.tenant, max_records: 1)
  end
end
