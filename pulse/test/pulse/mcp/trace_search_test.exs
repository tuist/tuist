defmodule Pulse.MCP.TraceSearchTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Test.OTLPTraceFixture, as: Fixture
  alias Pulse.Traces.Search
  alias Pulse.Traces.Selector

  defp span(ts, id) do
    raw = Fixture.span(ts) |> Map.put("traceId", Base.encode16(<<id::128>>, case: :lower))
    assert {:ok, [span], 0} = Traces.decode(Fixture.payload([raw]))
    span
  end

  defp args(query, extra \\ %{}) do
    Map.merge(%{"tenant" => "search", "query" => query, "start_ts_ns" => 0, "end_ts_ns" => 10_000}, extra)
  end

  defp search(query, extra \\ %{}) do
    assert {:ok, [%{"text" => text}]} = Tools.call("search_traces", args(query, extra))
    Pulse.JSON.decode!(text)
  end

  test "captured expanded resource selector and bounded hints parse; unsupported syntax never guesses" do
    query =
      ~s|{ resource.service.namespace = "tuist" && resource.service.name = "tuist-registry" && resource.deployment.environment =~ "tuist-(production\u007ccanary)" } with (most_recent=true)|

    assert {:ok,
            [
              {"resource", "service.namespace", "=", "tuist"},
              {"resource", "service.name", "=", "tuist-registry"},
              {"resource", "deployment.environment", "=~", "tuist-(production|canary)"}
            ]} = Selector.parse(query)

    assert {:error, :unexpanded_trace_variable} = Selector.parse(~s|{ resource.env =~ "${environment:regex}" }|)

    for query <- [
          "{}",
          ~s|{ resource.a = "x" } with (most_recent=false)|,
          ~s|{ resource.a = "x" } with (foo=true)|,
          ~s|{ resource.a != "x" }|,
          ~s'{ resource.a = "x" || span.b = "y" }',
          ~s|{ duration > 1s }|,
          ~s|{ resource.a = "x" } >> { span.b = "y" }|,
          ~s'{ resource.a = "x" } | count()',
          ~s|{ resource.a = 1 }|,
          ~s|{ resource.a =~ "(?=x)" }|,
          ~s'{resource.a=~"x)|(?:y"}',
          ~s|{ resource.a = "x" } trailing|
        ] do
      assert {:error, _} = Selector.parse(query)
    end

    assert {:error, :query_expression_limit} = Selector.parse(String.duplicate("x", 16_385))

    assert {:error, :query_expression_limit} =
             Selector.parse("{" <> Enum.join(List.duplicate(~s|span.a="x"|, 17), "&&") <> "}")

    assert {:error, :unsupported_trace_selector} = Selector.parse("{span.a=\"" <> String.duplicate("🌍", 1025) <> "\"}")
  end

  test "reference groups before trace limit, counts duplicates and orders earliest window span not newest matching span" do
    a = span(900, 1)
    b = span(500, 2)
    context = span(100, 1)

    typed =
      Map.update!(context.otlp, "resource", fn pairs ->
        Enum.map(pairs, fn pair ->
          if pair["key"] == "service.namespace", do: %{pair | "value" => %{"stringValue" => "other"}}, else: pair
        end)
      end)

    context = %{context | resource: Map.put(context.resource, "service.namespace", "other"), otlp: typed}
    assert :ok = Storage.append(:traces, "search", [a, a, b, context])
    result = search(~s|{ resource.service.namespace = "tuist" } with (most_recent=true)|, %{"limit" => 1})
    assert result["matched_trace_count"] == 2
    assert [row] = result["traces"]
    assert row["trace_id"] == b.trace_id
    assert row["stored_span_count"] == 1
    [_, row_a] = search(~s|{ resource.service.namespace = "tuist" }|)["traces"]
    assert row_a["matching_span_count"] == 2
    assert row_a["stored_span_count"] == 3
    assert row_a["start_timestamp_ns"] == 100
    assert row_a["end_timestamp_ns"] == 1900
    assert row_a["duration_ns"] == 1800

    assert search(~s|{ span.request_kind = "api" }|, %{"start_ts_ns" => 900, "end_ts_ns" => 900})["matched_trace_count"] ==
             1

    assert search(~s|{ span.request_kind = "api" }|, %{"tenant" => "other"})["traces"] == []
  end

  test "original types, fully anchored regex and same-span conjunction agree in reference/native" do
    a = span(10, 1)
    b = %{span(20, 2) | attributes: Map.put(a.attributes, "request_kind", "worker")}

    typed =
      Map.update!(b.otlp, "attributes", fn pairs ->
        Enum.map(pairs, fn pair ->
          if pair["key"] == "request_kind", do: %{pair | "value" => %{"stringValue" => "worker"}}, else: pair
        end)
      end)

    b = %{b | otlp: typed}
    assert :ok = Storage.append(:traces, "search", [a, b])
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, [a, b])

    for query <- [
          ~s|{ span.bytes = "aGVsbG8=" }|,
          ~s|{ span.metrics.skip = "false" }|,
          ~s|{ span.request_kind =~ "pi" }|,
          ~s|{ span.request_kind =~ "(api\u007cworker)" }|,
          ~s|{ span.request_kind = "api" && span.request_kind = "worker" }|,
          ~s|{ resource.deployment.environment = "production" && span.request_kind = "api" }|
        ] do
      assert {:ok, predicates} = Selector.parse(query)
      assert {:ok, native} = NIF.trace_search_new(0, 10_000, predicates, 100, 65_536)
      assert {:ok, 2} = NIF.trace_search_add(native, blob)
      assert {:ok, json} = NIF.trace_search_finish(native)
      assert Pulse.JSON.decode!(json) == search(query)
      assert :fallback = NIF.trace_search_finish(native)
    end
  end

  test "unknown legacy and malformed typed metadata fail whole results; native failure poisons state" do
    span = span(10, 1)
    assert :ok = Storage.append(:traces, "search", [span, %{span | otlp: nil}])
    assert {:error, :trace_metadata_unknown} = Tools.call("search_traces", args(~s|{span.request_kind="api"}|))
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, [%{span | otlp: nil}])
    assert {:ok, predicates} = Selector.parse(~s|{span.request_kind="api"}|)
    assert {:ok, native} = NIF.trace_search_new(0, 10_000, predicates, 1, 10)
    assert {:error, :trace_metadata_unknown} = NIF.trace_search_add(native, blob)
    assert :fallback = NIF.trace_search_finish(native)
    newer = %{span | timestamp_ns: 20, end_timestamp_ns: 1020}
    assert :ok = Storage.append(:traces, "search", [newer])
    assert search(~s'{span.request_kind="api"}', %{"start_ts_ns" => 20, "end_ts_ns" => 20})["matched_trace_count"] == 1
    malformed = %{span | otlp: Map.put(span.otlp, "version", 2)}
    assert {:error, {:decode_failed, _}} = Search.json([malformed], predicates, start_ts: 0, end_ts: 10_000)
  end

  test "all distinct groups count toward cap including nonmatching traces" do
    spans = [span(10, 1), span(20, 2)]
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, spans)
    assert {:ok, predicates} = Selector.parse(~s|{span.request_kind="absent"}|)
    assert {:ok, native} = NIF.trace_search_new(0, 10_000, predicates, 1, 1)
    assert {:error, :trace_group_limit} = NIF.trace_search_add(native, blob)
    assert :fallback = NIF.trace_search_finish(native)

    assert {:error, :trace_group_limit} =
             Search.json(spans, predicates, start_ts: 0, end_ts: 10_000, max_trace_groups: 1)
  end

  test "native grouping is partition/order independent against reference on randomized stored spans" do
    :rand.seed(:exsss, {40, 51, 62})
    spans = for _ <- 1..80, do: span(:rand.uniform(100), :rand.uniform(12))
    assert {:ok, predicates} = Selector.parse(~s'{resource.service.namespace="tuist" && span.request_kind=~"api"}')
    opts = [start_ts: 0, end_ts: 1000, limit: 5]
    assert {:ok, reference} = Search.json(spans, predicates, opts)

    for records <- [spans, Enum.reverse(spans), Enum.shuffle(spans)] do
      assert {:ok, native} = NIF.trace_search_new(0, 1000, predicates, 5, 65_536)

      for batch <- Enum.chunk_every(records, 7) do
        assert {:ok, blob, _, _} = S3.encode_segment(:traces, batch)
        assert {:ok, _} = NIF.trace_search_add(native, blob)
      end

      assert {:ok, json} = NIF.trace_search_finish(native)
      assert Pulse.JSON.decode!(json) == Pulse.JSON.decode!(reference)
    end

    assert :fallback = NIF.trace_search_new(0, 1000, [{"resource", "env", "=~", "x)|(?:y"}], 5, 65_536)
  end

  test "closed tool requires explicit valid windows and trace limit" do
    for extra <- [
          %{"limit" => 0},
          %{"limit" => 1001},
          %{"start_ts_ns" => -1},
          %{"end_ts_ns" => -1},
          %{"start_ts_ns" => 11_000},
          %{"fields" => []},
          %{"max_trace_groups" => 1}
        ] do
      assert {:error, {:invalid_arguments, _}} = Tools.call("search_traces", args(~s|{span.request_kind="api"}|, extra))
    end

    assert {:error, {:invalid_arguments, _}} =
             Tools.call("search_traces", %{"tenant" => "search", "query" => ~s|{span.request_kind="api"}|})
  end
end
