defmodule Pulse.Traces.TempoFilteredNamesTest do
  use Pulse.Test.Case, async: true

  alias Pulse.{Codec.NIF, MCP.Tools, OTLP.Traces, Runtime, Storage}
  alias Pulse.Storage.S3
  alias Pulse.Test.ValueOnlyTraceDiscoveryStorage
  alias Pulse.Traces.{TempoDiscovery, TempoSearch}

  defp fixture do
    dir = Path.expand("../../fixtures/traces", __DIR__)
    raw = File.read!(Path.join(dir, "tempo-filtered-names-oracle.json"))

    assert Base.encode16(:crypto.hash(:sha256, raw), case: :lower) ==
             "ad642c6c44e6554f6e6da64cbea079f46b1ba66d595724b36e972510cb4fa88d"

    datasets =
      for {name, hash} <- [
            {"promoted", "b1df7099dbdd16290e37ac2421b683c65b8ba454bb5ac037a20d9b9872e35b13"},
            {"generic", "3ba941b1173b3074a1e3dc350ce4f60c51ea840bf4ba494dc4ef868c4a6146f0"},
            {"no-service", "0e7d4acc5240ffb2ab421078e936a989671fac7f77f89328cdf09318997fe9f7"}
          ],
          into: %{} do
        wire = File.read!(Path.join(dir, "tempo-filtered-names-#{name}.protobuf"))
        assert Base.encode16(:crypto.hash(:sha256, wire), case: :lower) == hash
        assert {:ok, rows, 0} = Traces.decode_protobuf(wire)
        {name, rows}
      end

    {datasets, Pulse.JSON.decode!(raw)}
  end

  defp state(scope, q, floor \\ 0) do
    {:ok, predicates} = TempoDiscovery.filter(scope, "", q)
    {:ok, state} = NIF.tempo_filtered_discovery_new(floor, scope, "", predicates)
    state
  end

  defp native(rows, scope, q) do
    resource = state(scope, q)
    {:ok, blob, _, _} = S3.encode_segment(:traces, rows)
    with {:ok, _} <- NIF.tempo_discovery_add(resource, blob), do: NIF.tempo_discovery_finish(resource)
  end

  test "actual engine and Parquet establish 75 filtered name cases across scopes and promotion types" do
    {datasets, cases} = fixture()
    assert length(cases) == 75
    assert Enum.count(cases, &(&1["response"] != &1["complete"])) == 11

    for c <- cases do
      raw = Enum.flat_map(c["response"]["scopes"], & &1["tags"]) |> MapSet.new()
      complete = Enum.flat_map(c["complete"]["scopes"], & &1["tags"]) |> MapSet.new()
      assert MapSet.subset?(raw, complete)
    end

    for c <- cases do
      rows = datasets[c["dataset"]]

      for spans <- [rows, Enum.reverse(rows), rows ++ rows] do
        assert {:ok, json} = native(spans, c["scope"], c["query"])
        assert Pulse.JSON.decode!(json) == c["complete"], inspect(c)
        assert {:ok, json} = TempoDiscovery.json(spans, c["scope"], "", discovery_query: c["query"])
        assert Pulse.JSON.decode!(json) == c["complete"], inspect(c)
      end

      resource = state(c["scope"], c["query"])

      for row <- rows do
        {:ok, blob, _, _} = S3.encode_segment(:traces, [row])
        assert {:ok, 1} = NIF.tempo_discovery_add(resource, blob)
      end

      assert {:ok, json} = NIF.tempo_discovery_finish(resource)
      assert Pulse.JSON.decode!(json) == c["complete"]
      assert :fallback = NIF.tempo_discovery_finish(resource)
    end
  end

  test "MCP and old adapters cannot silently discard name filters or reuse value-only callbacks" do
    {datasets, cases} = fixture()
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    for {name, rows} <- datasets, do: assert(:ok = Storage.append(:traces, name, rows))
    Runtime.put_env(:pulse, Storage, adapter: ValueOnlyTraceDiscoveryStorage)

    for c <- cases do
      assert {:ok, [%{"text" => json}]} =
               Tools.call("discover_trace_tags", %{
                 "tenant" => c["dataset"],
                 "scope" => c["scope"],
                 "query" => c["query"]
               })

      assert Pulse.JSON.decode!(json) == c["complete"], inspect(c)
    end

    for q <- [
          "{",
          "{} with (most_recent=true)",
          "{true}",
          ~s'{span.request.kind="api" || span.request.kind="rpc"}',
          ~s'{span.cached=false}'
        ] do
      assert {:error, :unsupported_trace_discovery} = TempoDiscovery.query("promoted", "span", "", 2, "json", q)
    end
  end

  test "name hints never become value proofs and unfiltered names still require original keys" do
    {datasets, _} = fixture()
    rows = datasets["no-service"]
    q = ~s'{resource.service.name="absent"}'
    assert {:ok, ~s'{"scopes":[{"name":"resource","tags":["service.name"]}]}'} = native(rows, "resource", q)
    assert {:ok, original} = TempoDiscovery.json(rows, "resource", "", [])
    refute "service.name" in hd(Pulse.JSON.decode!(original)["scopes"])["tags"]

    assert {:ok, ~s'{"tagValues":[]}'} =
             TempoDiscovery.json(rows, "resource", "service.name", discovery_query: ~s'{span.request.kind="absent"}')

    legacy = [%{hd(rows) | otlp: nil} | rows]
    assert {:error, :trace_metadata_unknown} = native(legacy, "resource", q)
    assert {:error, :trace_metadata_unknown} = TempoDiscovery.json(legacy, "resource", "", discovery_query: q)
    resource = state("span", q)
    bad = File.read!(Path.expand("../../fixtures/traces/trace-invalid-value.parquet", __DIR__))
    assert :fallback = NIF.tempo_discovery_add(resource, bad)
    assert :fallback = NIF.tempo_discovery_finish(resource)
  end

  test "promoted hints only use visible context at the authority floor, while all decoded rows are charged" do
    {datasets, _} = fixture()
    rows = datasets["promoted"]
    q = ~s'{resource.service.name="absent"}'
    {:ok, blob, _, _} = S3.encode_segment(:traces, rows)

    for {scope, expected} <- [
          {"span", %{"scopes" => []}},
          {"resource", %{"scopes" => [%{"name" => "resource", "tags" => ["service.name"]}]}}
        ] do
      resource = state(scope, q, 15_000_000_000)
      assert {:ok, 3} = NIF.tempo_discovery_add(resource, blob)
      assert {:ok, json} = NIF.tempo_discovery_finish(resource)
      assert Pulse.JSON.decode!(json) == expected
      visible = Enum.filter(rows, &(&1.timestamp_ns >= 15_000_000_000))
      assert {:ok, reference} = TempoDiscovery.json(visible, scope, "", discovery_query: q)
      assert Pulse.JSON.decode!(reference) == expected
    end

    resource = state("resource", q, 30_000_000_000)
    assert {:ok, 3} = NIF.tempo_discovery_add(resource, blob)
    assert {:ok, ~s'{"scopes":[]}'} = NIF.tempo_discovery_finish(resource)
  end

  test "whole-request row dictionary and independently escaped output bounds still apply to filtered names" do
    {datasets, _} = fixture()
    base = hd(datasets["promoted"])
    q = ~s'{resource.service.name="worker"}'

    make = fn key ->
      %{
        base
        | attributes: Map.put(base.attributes, key, "v"),
          otlp: Map.update!(base.otlp, "attributes", &(&1 ++ [%{"key" => key, "value" => %{"stringValue" => "v"}}]))
      }
    end

    rows = for i <- 1..5001, do: make.("key_#{i}")
    resource = state("span", q)
    # Small immutable segments avoid testing an unrelated segment payload cap.
    result =
      Enum.reduce_while(Enum.chunk_every(rows, 200), :ok, fn chunk, _ ->
        {:ok, blob, _, _} = S3.encode_segment(:traces, chunk)

        case NIF.tempo_discovery_add(resource, blob) do
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

    assert {:error, :query_resource_limit} = result
    assert :fallback = NIF.tempo_discovery_finish(resource)
    assert {:error, :query_resource_limit} = TempoDiscovery.json(rows, "span", "", discovery_query: q)
    escaped = for i <- 1..900, do: make.(String.duplicate(<<0>>, 200) <> Integer.to_string(i))
    assert {:error, :query_resource_limit} = native(escaped, "span", q)
    assert {:error, :query_resource_limit} = TempoDiscovery.json(escaped, "span", "", discovery_query: q)

    assert {:error, :query_scan_limit} =
             TempoDiscovery.json([base, base], "span", "", discovery_query: q, max_scan_rows: 1)
  end
end
