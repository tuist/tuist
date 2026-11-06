defmodule Pulse.Traces.TempoFilteredDiscoveryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Test.LegacyTraceDiscoveryStorage
  alias Pulse.Traces.TempoDiscovery, as: Discovery
  alias Pulse.Traces.TempoSearch

  defp fixture do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-filtered-discovery-input.protobuf", __DIR__))
    json = File.read!(Path.expand("../../fixtures/traces/tempo-filtered-discovery-oracle.json", __DIR__))

    assert Base.encode16(:crypto.hash(:sha256, wire), case: :lower) ==
             "c3b6d9a720ddb1352fcabbb9eeb71fbd5563955b677011f00f37a3ac7bbb4430"

    assert Base.encode16(:crypto.hash(:sha256, json), case: :lower) ==
             "38f9515469e322fb9dc1d366954fac21110371f01372f283068ede61823673be"

    assert {:ok, rows, 0} = Traces.decode_protobuf(wire)
    {rows, Pulse.JSON.decode!(json)}
  end

  defp native(rows, scope, key, query, floor \\ 0) do
    {:ok, predicates} = Discovery.filter(scope, key, query)
    {:ok, state} = NIF.tempo_filtered_discovery_new(floor, scope, key, predicates)

    result =
      Enum.reduce_while(rows, :ok, fn row, _ ->
        {:ok, blob, _, _} = S3.encode_segment(:traces, [row])

        case NIF.tempo_discovery_add(state, blob) do
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

    if result == :ok, do: NIF.tempo_discovery_finish(state), else: result
  end

  test "actual Tempo engine and Parquet fetch establish same-span typed filtered values, independent of partitions and order" do
    {spans, cases} = fixture()

    for rows <- [spans, Enum.reverse(spans), spans ++ spans], c <- Enum.filter(cases, & &1["supported"]) do
      [scope, key] = String.split(c["target"], ".", parts: 2)
      assert {:ok, json} = native(rows, scope, key, c["query"])
      assert Pulse.JSON.decode!(json) == c["response"], c["name"]
      assert {:ok, reference} = Discovery.json(rows, scope, key, discovery_query: c["query"])
      assert Pulse.JSON.decode!(reference) == c["response"], c["name"]
    end
  end

  test "stored-value discovery rejects upstream literal invention, malformed fallback, hints, filtered names and unsupported grammar" do
    {_, cases} = fixture()
    shortcut = Enum.find(cases, &(not &1["supported"]))
    assert shortcut["response"] == %{"tagValues" => [%{"type" => "string", "value" => "invented"}]}

    for q <- [
          shortcut["query"],
          "{",
          ~s'{span.request.kind="api"} | count()',
          ~s'{span.request.kind="api"} with (most_recent=true)',
          ~s'{span.request.kind="${variable}"}',
          ~s'{span.request.kind=~"x)|(?:y"}'
        ] do
      assert {:error, :unsupported_trace_discovery} = Discovery.filter("span", "request.kind", q)
    end

    assert {:ok, [{"span", "request.kind", "=", "api"}]} = Discovery.filter("span", "", ~s'{span.request.kind="api"}')

    assert :fallback =
             NIF.tempo_filtered_discovery_new(0, "span", "request.kind", [{"span", "request.kind", "=", "invented"}])

    assert :fallback =
             NIF.tempo_filtered_discovery_new(0, "span", "retries", [{"span", "request.kind", "=~", "x)|(?:y"}])
  end

  defp expression_native(segments, scope, key, query, window \\ {0, 0}) do
    {:ok, {:expression, program}} = Discovery.filter(scope, key, query)
    {start, finish} = window
    {:ok, state} = NIF.tempo_expression_discovery_new(0, scope, key, program, start, finish)

    result =
      Enum.reduce_while(segments, :ok, fn rows, _ ->
        {:ok, blob, _, _} = S3.encode_segment(:traces, rows)

        case NIF.tempo_discovery_add(state, blob) do
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

    if result == :ok, do: NIF.tempo_discovery_finish(state), else: result
  end

  test "expression discovery evaluates stored same-target values without query-literal invention" do
    {rows, _} = fixture()

    for query <- [
          ~s'{span.request.kind="api" || span.request.kind="rpc"}',
          ~s'{span.request.kind="invented" || span.request.kind="also-invented"}',
          ~s'{span.cached=false}',
          ~s'{span.retries>=0}'
        ] do
      assert {:ok, native} = expression_native([rows], "span", "request.kind", query)
      assert {:ok, reference} = Discovery.json(rows, "span", "request.kind", discovery_query: query)
      assert Pulse.JSON.decode!(native) == Pulse.JSON.decode!(reference)
      refute String.contains?(native, "invented")
    end
  end

  test "span-local and duration-only expressions do not require unique roots" do
    {[base | _], _} = fixture()
    a = %{base | parent_span_id: nil}
    b = %{a | span_id: "ffffffffffffffff", name: "another-root"}
    rows = [a, b]

    for query <- [~s'{span.retries<=0}', ~s'{trace:duration>=0ns}'] do
      assert {:ok, native} = expression_native([rows], "span", "retries", query)
      assert {:ok, reference} = Discovery.json(rows, "span", "retries", discovery_query: query)
      assert Pulse.JSON.decode!(native) == Pulse.JSON.decode!(reference)
    end
  end

  test "legacy unknown still fails nonmatching filters; unsupported types fail only on matching rows; floors do not create partial dictionaries" do
    {rows, _} = fixture()
    [first | _] = rows
    absent = ~s'{resource.service.name="absent"}'
    legacy = [%{first | otlp: nil} | rows]
    assert {:error, :trace_metadata_unknown} = native(legacy, "span", "retries", absent)
    assert {:error, :trace_metadata_unknown} = Discovery.json(legacy, "span", "retries", discovery_query: absent)
    assert {:ok, ~s'{"tagValues":[]}'} = native(rows, "span", "opaque", ~s'{span.request.kind="rpc"}')
    assert {:error, :unsupported_trace_tag_type} = native(rows, "span", "opaque", ~s'{span.request.kind="api"}')
    assert {:ok, json} = native(legacy, "span", "retries", ~s'{resource.service.name="frontend"}', 15_000_000_000)
    assert Pulse.JSON.decode!(json) == %{"tagValues" => [%{"type" => "int", "value" => "9223372036854775807"}]}
  end

  defp with_candidate(span, value) do
    pair = %{"key" => "candidate.value", "value" => %{"stringValue" => value}}

    %{
      span
      | attributes: Map.put(span.attributes, "candidate.value", value),
        otlp: Map.update!(span.otlp, "attributes", &(&1 ++ [pair]))
    }
  end

  test "expression replay fails whole on dictionary exhaustion and consumes the handle" do
    {[base | _], _} = fixture()
    rows = for n <- 1..5001, do: with_candidate(base, "value#{n}")
    query = ~s'{span.retries<=0}'
    {:ok, {:expression, program}} = Discovery.filter("span", "candidate.value", query)
    {:ok, state} = NIF.tempo_expression_discovery_new(0, "span", "candidate.value", program, 0, 0)
    {:ok, blob, _, _} = S3.encode_segment(:traces, rows)
    assert {:ok, 5001} = NIF.tempo_discovery_add(state, blob)
    assert {:error, :query_resource_limit} = NIF.tempo_discovery_finish(state)
    assert :fallback = NIF.tempo_discovery_finish(state)
    assert {:error, :query_resource_limit} = Discovery.json(rows, "span", "candidate.value", discovery_query: query)
  end

  test "filtered dictionaries and escaped output still fail whole and poison state at their independent caps" do
    {[base | _], _} = fixture()
    query = ~s'{resource.service.name="worker"}'
    {:ok, predicates} = Discovery.filter("span", "candidate.value", query)
    rows = for n <- 1..5001, do: with_candidate(base, "value#{n}")
    assert {:error, :query_resource_limit} = Discovery.json(rows, "span", "candidate.value", discovery_query: query)
    {:ok, state} = NIF.tempo_filtered_discovery_new(0, "span", "candidate.value", predicates)

    for chunk <- rows |> Enum.take(5000) |> Enum.chunk_every(1000) do
      {:ok, blob, _, _} = S3.encode_segment(:traces, chunk)
      assert {:ok, _} = NIF.tempo_discovery_add(state, blob)
    end

    {:ok, blob, _, _} = S3.encode_segment(:traces, [List.last(rows)])
    assert {:error, :query_resource_limit} = NIF.tempo_discovery_add(state, blob)
    assert :fallback = NIF.tempo_discovery_finish(state)
    large = with_candidate(base, String.duplicate(<<1>>, 200_000))
    assert {:error, :query_resource_limit} = native([large], "span", "candidate.value", query)
    assert {:error, :query_resource_limit} = Discovery.json([large], "span", "candidate.value", discovery_query: query)
  end

  test "malformed nonmatching input cannot disappear behind a false filter" do
    {rows, _} = fixture()
    query = ~s'{resource.service.name="absent"}'
    {:ok, predicates} = Discovery.filter("span", "retries", query)
    {:ok, state} = NIF.tempo_filtered_discovery_new(0, "span", "retries", predicates)
    blob = File.read!(Path.expand("../../fixtures/traces/trace-invalid-version.parquet", __DIR__))
    assert :fallback = NIF.tempo_discovery_add(state, blob)
    assert :fallback = NIF.tempo_discovery_finish(state)

    assert {:error, {:decode_failed, :invalid_trace_metadata}} =
             Discovery.json([%{hd(rows) | kind: 99}], "span", "retries", discovery_query: query)
  end

  test "legacy optional adapter callbacks cannot silently discard filters" do
    {rows, cases} = fixture()
    assert :ok = Pulse.Storage.append(:traces, "legacy-adapter", rows)
    Runtime.put_env(:pulse, Pulse.Storage, adapter: LegacyTraceDiscoveryStorage)
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    assert {:ok, json} = Discovery.query("legacy-adapter", "span", "retries")
    assert Pulse.JSON.decode!(json) == %{"tagValues" => [%{"type" => "string", "value" => "unfiltered-adapter"}]}
    c = Enum.find(cases, &(&1["name"] == "same-span-conjunction"))
    assert {:ok, json} = Discovery.query("legacy-adapter", "span", "retries", 2, "json", c["query"])
    assert Pulse.JSON.decode!(json) == c["response"]
  end

  test "MCP filtered values are tenant local and filters cannot erase row accounting" do
    {rows, cases} = fixture()
    assert :ok = Pulse.Storage.append(:traces, "owned-filtered", rows)
    Runtime.put_env(:pulse, TempoSearch, enabled: true)

    for c <- Enum.filter(cases, & &1["supported"]) do
      [scope, key] = String.split(c["target"], ".", parts: 2)
      args = %{"tenant" => "owned-filtered", "scope" => scope, "key" => key, "query" => c["query"]}
      assert {:ok, [%{"text" => json}]} = Tools.call("discover_trace_tag_values", args)
      assert Pulse.JSON.decode!(json) == c["response"], c["name"]
    end

    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 1)

    args = %{
      "tenant" => "owned-filtered",
      "scope" => "span",
      "key" => "retries",
      "query" => ~s'{resource.service.name="absent"}'
    }

    assert {:error, :query_sample_limit} = Tools.call("discover_trace_tag_values", args)
  end
end
