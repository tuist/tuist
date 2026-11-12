defmodule Pulse.Traces.TempoDiscoveryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Storage.S3
  alias Pulse.Traces.TempoDiscovery, as: Discovery
  alias Pulse.Traces.TempoSearch

  defp fixture do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-discovery-input.protobuf", __DIR__))
    json = File.read!(Path.expand("../../fixtures/traces/tempo-discovery-oracle.json", __DIR__))

    assert Base.encode16(:crypto.hash(:sha256, wire), case: :lower) ==
             "c16d4e61dfb1c84f9efe270a2a08b903fd3f10933fff8f71be4981d5e1d7941b"

    assert Base.encode16(:crypto.hash(:sha256, json), case: :lower) ==
             "fe1b77a7598c7928abcb3b569f8fa5cd8c0d057a2ee1580a7923df3d9dbd9aed"

    assert {:ok, spans, 0} = Traces.decode_protobuf(wire)
    {spans, Pulse.JSON.decode!(json)}
  end

  defp native(rows, scope, key, floor \\ 0) do
    {:ok, state} = NIF.tempo_discovery_new(floor, scope, key)
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, rows)

    case NIF.tempo_discovery_add(state, blob) do
      {:ok, _} -> NIF.tempo_discovery_finish(state)
      error -> error
    end
  end

  test "actual Tempo Parquet discovery fixtures establish scoped names and original scalar types independently" do
    {spans, cases} = fixture()

    for rows <- [spans, Enum.reverse(spans), spans ++ spans], c <- cases do
      assert {:ok, json} = native(rows, c["scope"], c["key"])
      assert Pulse.JSON.decode!(json) == c["response"]
      assert {:ok, ref} = Discovery.json(rows, c["scope"], c["key"], [])
      assert Pulse.JSON.decode!(ref) == c["response"]
    end
  end

  test "legacy unknown and targeted unsupported values fail whole requests; retention hides only expired rows" do
    {rows, _} = fixture()
    [first | _] = rows
    assert {:error, :unsupported_trace_tag_type} = native(rows, "span", "opaque")
    assert {:error, :unsupported_trace_tag_type} = Discovery.json(rows, "span", "opaque", [])
    legacy = [%{first | otlp: nil} | rows]
    assert {:error, :trace_metadata_unknown} = native(legacy, "span", "absent")
    assert {:error, :trace_metadata_unknown} = Discovery.json(legacy, "span", "absent", [])
    assert {:ok, json} = native(legacy, "span", "cached", 15_000_000_000)
    assert Pulse.JSON.decode!(json) == %{"tagValues" => [%{"type" => "bool", "value" => "true"}]}
    assert {:ok, "{\"scopes\":[]}"} = native([], "span", "")
  end

  defp with_value(span, key, value) do
    %{
      span
      | attributes: %{key => value},
        otlp: Map.put(span.otlp, "attributes", [%{"key" => key, "value" => %{"stringValue" => value}}])
    }
  end

  test "distinct dictionary cap and escaped output budget fail rather than truncate and poison native resources" do
    {[span | _], _} = fixture()
    rows = for n <- 1..5001, do: with_value(span, "key#{n}", "value")
    assert {:error, :query_resource_limit} = Discovery.json(rows, "span", "", [])
    {:ok, state} = NIF.tempo_discovery_new(0, "span", "")
    chunks = Enum.chunk_every(rows, 1000)

    for chunk <- Enum.take(chunks, 5) do
      {:ok, blob, _, _} = S3.encode_segment(:traces, chunk)
      assert {:ok, _} = NIF.tempo_discovery_add(state, blob)
    end

    {:ok, blob, _, _} = S3.encode_segment(:traces, List.last(chunks))
    assert {:error, :query_resource_limit} = NIF.tempo_discovery_add(state, blob)
    assert :fallback = NIF.tempo_discovery_finish(state)
    rows = [with_value(span, "large", String.duplicate(<<1>>, 200_000))]
    assert {:error, :query_resource_limit} = Discovery.json(rows, "span", "large", [])
    assert {:error, :query_resource_limit} = native(rows, "span", "large")
  end

  test "default-off and MCP typed discovery use owned runtime dependencies" do
    {spans, cases} = fixture()
    assert :ok = Pulse.Storage.append(:traces, "owned", spans)
    assert {:error, :tempo_search_disabled} = Discovery.query("owned", "span", "cached")
    Pulse.Runtime.put_env(:pulse, TempoSearch, enabled: true)

    for c <- cases do
      name = if c["key"] == "", do: "discover_trace_tags", else: "discover_trace_tag_values"
      args = %{"tenant" => "owned", "scope" => c["scope"]}
      args = if c["key"] == "", do: args, else: Map.put(args, "key", c["key"])
      assert {:ok, [%{"text" => text}]} = Tools.call(name, args)
      assert Pulse.JSON.decode!(text) == c["response"]
    end
  end
end
