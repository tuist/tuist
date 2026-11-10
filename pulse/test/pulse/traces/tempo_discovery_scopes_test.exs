defmodule Pulse.Traces.TempoDiscoveryScopesTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Traces.{TempoDiscovery, TempoSearch}

  defp fixture do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-scopes-input.protobuf", __DIR__))
    json = File.read!(Path.expand("../../fixtures/traces/tempo-scopes-oracle.json", __DIR__))

    assert Base.encode16(:crypto.hash(:sha256, wire), case: :lower) ==
             "2ebb762307e7b3059e05e04c75e034e6bfb304552e0ce96a141490da73ee9d1c"

    assert Base.encode16(:crypto.hash(:sha256, json), case: :lower) ==
             "f2047b3107af23be81c3252a9da0898a28482b8ad522fdf3a5cc9b76453e213f"

    assert {:ok, rows, 0} = Traces.decode_protobuf(wire)
    {rows, Pulse.JSON.decode!(json)}
  end

  defp native(rows, c, floor \\ 0) do
    {:ok, predicates} = TempoDiscovery.filter(c["scope"], c["key"], c["query"])

    {:ok, state} =
      if predicates == [],
        do: NIF.tempo_discovery_new(floor, c["scope"], c["key"]),
        else: NIF.tempo_filtered_discovery_new(floor, c["scope"], c["key"], predicates)

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

  test "actual Tempo Parquet and engine establish original owner separation in all five scopes" do
    {rows, cases} = fixture()
    assert length(cases) == 68

    for spans <- [rows, Enum.reverse(rows), rows ++ rows], c <- cases do
      assert {:ok, json} = native(spans, c)
      assert Pulse.JSON.decode!(json) == c["response"], inspect(c)
      assert {:ok, reference} = TempoDiscovery.json(spans, c["scope"], c["key"], discovery_query: c["query"])
      assert Pulse.JSON.decode!(reference) == c["response"], inspect(c)
    end
  end

  test "MCP serves scoped names and filtered nested values without flattening intrinsic fields" do
    {rows, cases} = fixture()
    assert :ok = Pulse.Storage.append(:traces, "scopes", rows)
    Runtime.put_env(:pulse, TempoSearch, enabled: true)

    for c <- cases do
      name = if c["key"] == "", do: "discover_trace_tags", else: "discover_trace_tag_values"
      args = %{"tenant" => "scopes", "scope" => c["scope"]}
      args = if c["key"] == "", do: args, else: Map.merge(args, %{"key" => c["key"], "query" => c["query"]})
      assert {:ok, [%{"text" => json}]} = Tools.call(name, args)
      assert Pulse.JSON.decode!(json) == c["response"], inspect(c)
    end

    assert {:ok, intrinsic} = TempoDiscovery.query("scopes", "intrinsic", "name")

    assert Pulse.JSON.decode!(intrinsic) == %{
             "tagValues" => [%{"type" => "string", "value" => "api"}, %{"type" => "string", "value" => "rpc"}]
           }

    assert {:ok, nested} = TempoDiscovery.query("scopes", "event", "phase", 2, "json", ~s'{event.phase="first"}')

    assert Pulse.JSON.decode!(nested) == %{
             "tagValues" => [%{"type" => "string", "value" => "first"}, %{"type" => "string", "value" => "second"}]
           }
  end

  test "unknown metadata and matching unsupported nested values fail whole, while floors exclude only expired parents" do
    {rows, _} = fixture()

    for scope <- ["instrumentation", "event", "link"] do
      c = %{"scope" => scope, "key" => "opaque", "query" => ""}
      assert {:error, :unsupported_trace_tag_type} = native(rows, c)
      assert {:error, :unsupported_trace_tag_type} = TempoDiscovery.json(rows, scope, "opaque", [])
      assert {:ok, ~s'{"tagValues":[]}'} = native(rows, c, 15_000_000_000)
      legacy = [%{hd(rows) | otlp: nil} | rows]
      c = %{c | "query" => ~s'{resource.service.name="absent"}'}
      assert {:error, :trace_metadata_unknown} = native(legacy, c)

      assert {:error, :trace_metadata_unknown} =
               TempoDiscovery.json(legacy, scope, "opaque", discovery_query: c["query"])
    end
  end

  test "flat scopes explicitly trade previous row capacity for bounded attribute work" do
    {rows, _} = fixture()
    base = hd(rows)
    extra = for i <- 1..1020, do: %{"key" => "charge_#{i}", "value" => %{"stringValue" => "v"}}
    attrs = base.otlp["resource"] ++ extra
    assert length(attrs) == 1024
    projection = Enum.reduce(extra, base.resource, &Map.put(&2, &1["key"], "v"))
    dense = %{base | resource: projection, otlp: Map.put(base.otlp, "resource", attrs)}
    q = ~s'{resource.service.name="absent"}'
    {:ok, predicates} = TempoDiscovery.filter("resource", "shared", q)
    {:ok, state} = NIF.tempo_filtered_discovery_new(0, "resource", "shared", predicates)
    {:ok, blob, _, _} = S3.encode_segment(:traces, [dense])
    rounds = div(2_000_000, 1025)
    for _ <- 1..rounds, do: assert({:ok, 1} = NIF.tempo_discovery_add(state, blob))
    assert {:error, :trace_discovery_work_limit} = NIF.tempo_discovery_add(state, blob)
    assert :fallback = NIF.tempo_discovery_finish(state)

    assert {:error, :trace_discovery_work_limit} =
             TempoDiscovery.json(List.duplicate(dense, rounds + 1), "resource", "shared", discovery_query: q)
  end

  test "nested owner work is capped before matching even when parent row and dictionary counts are small" do
    {rows, _} = fixture()
    base = hd(rows)
    # Empty owners cost work, and one attribute doubles their cost. No match,
    # parent row cap or tiny dictionary hides traversal of nested metadata.
    pair = %{"key" => "phase", "value" => %{"stringValue" => "constant"}}
    q = ~s'{resource.service.name="absent"}'
    {:ok, predicates} = TempoDiscovery.filter("event", "phase", q)

    for {attrs, projection, parents} <- [{[], %{}, 1000}, {[pair], %{"phase" => "constant"}, 500}],
        key <- ["phase", ""] do
      event = Map.put(hd(base.events), "attributes", projection)

      dense = %{
        base
        | events: List.duplicate(event, 2000),
          otlp: Map.put(base.otlp, "events", List.duplicate(attrs, 2000))
      }

      {:ok, state} = NIF.tempo_filtered_discovery_new(0, "event", key, predicates)
      # Keep every parent and all two million work units, but amortize Parquet
      # setup across ten rows. The extra parent still crosses the exact limit
      # in a separate source, so resetting work per segment cannot pass.
      {:ok, blob, _, _} = S3.encode_segment(:traces, List.duplicate(dense, 10))
      {:ok, extra, _, _} = S3.encode_segment(:traces, [dense])
      for _ <- 1..div(parents, 10), do: assert({:ok, 10} = NIF.tempo_discovery_add(state, blob))
      assert {:error, :trace_discovery_work_limit} = NIF.tempo_discovery_add(state, extra)
      assert :fallback = NIF.tempo_discovery_finish(state)

      assert {:error, :trace_discovery_work_limit} =
               TempoDiscovery.json(List.duplicate(dense, parents + 1), "event", key, discovery_query: q)
    end
  end
end
