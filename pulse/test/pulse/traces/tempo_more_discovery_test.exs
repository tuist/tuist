defmodule Pulse.Traces.TempoMoreDiscoveryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.{Codec.NIF, MCP.Tools, OTLP.Traces, Runtime, Storage}
  alias Pulse.Storage.S3
  alias Pulse.Test.FailingStorage
  alias Pulse.Test.ScopedTraceDiscoveryStorage
  alias Pulse.Traces.{TempoDiscovery, TempoFloat, TempoSearch}

  defp fixture do
    dir = Path.expand("../../fixtures/traces", __DIR__)

    for {file, hash} <- [
          {"tempo-more-discovery-input.protobuf", "074a5bc48c218c1f39a4dfdb20d4daa10b258f6e03c574a963d0b7e23ca1615f"},
          {"tempo-more-discovery-oracle.json", "7f6a2e6992d78b124865f1fe5bf4690c83348998a308cd75977f617822c77b4d"},
          {"tempo-float-oracle.json", "17c48bbcc0aa1d6908c439e284e39ac8e4f4c1764f952100a895b44f8f5fc15b"},
          {"produce_tempo_more_discovery.go.txt", "48d62b3f5cf087227e737a464d70c4d58d019fd71523fe2d27ea949d9b8d8df0"},
          {"produce_tempo_dynamic_filters.go.txt", "eaba6f2388f6b5e9bfc71f02ddbc3a68451cba535fe4a54ef71547ccaf206d98"},
          {"produce_tempo_value_envelopes.go.txt", "11548a9a422a703b29b1f9c809a8d4ccbed0450548005c5b5b0d837e018245b7"}
        ] do
      assert Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(dir, file))), case: :lower) == hash
    end

    {:ok, rows, 0} = Traces.decode_protobuf(File.read!(Path.join(dir, "tempo-more-discovery-input.protobuf")))
    {rows, Pulse.JSON.decode!(File.read!(Path.join(dir, "tempo-more-discovery-oracle.json")))}
  end

  defp target("." <> key), do: {"none", key}

  defp target(name) do
    case String.split(name, ".", parts: 2) do
      [scope, key] -> {scope, key}
      [_] -> {"intrinsic", name}
    end
  end

  defp state(c) do
    {scope, key} = target(c["target"])
    {:ok, predicates} = TempoDiscovery.filter(scope, key, c["query"])

    if predicates == [],
      do: NIF.tempo_discovery_new(0, scope, key),
      else: NIF.tempo_filtered_discovery_new(0, scope, key, predicates)
  end

  test "273 independent IEEE spellings include integral float identity, signed zeros, subnormals and exponent thresholds" do
    {_, _} = fixture()
    floats = File.read!(Path.expand("../../fixtures/traces/tempo-float-oracle.json", __DIR__)) |> Pulse.JSON.decode!()
    assert length(floats) == 273

    for c <- floats do
      <<value::float-64>> = Base.decode16!(c["bits"], case: :lower)
      assert TempoFloat.format(value) == c["text"], inspect(c)
    end
  end

  test "actual Tempo dictionaries establish floats, three-owner unscoped values and seven stored intrinsic strings" do
    {rows, cases} = fixture()
    assert length(cases) == 20
    {:ok, forward, _, _} = S3.encode_segment(:traces, rows)
    {:ok, reverse, _, _} = S3.encode_segment(:traces, Enum.reverse(rows))

    parts =
      for chunk <- Enum.chunk_every(rows, 57) do
        {:ok, blob, _, _} = S3.encode_segment(:traces, chunk)
        blob
      end

    for c <- cases do
      {scope, key} = target(c["target"])

      for blobs <- [[forward], [reverse], [forward, reverse], parts] do
        {:ok, s} = state(c)
        for blob <- blobs, do: assert({:ok, _} = NIF.tempo_discovery_add(s, blob))
        assert {:ok, json} = NIF.tempo_discovery_finish(s)
        assert Pulse.JSON.decode!(json) == c["response"], inspect(c)
        assert :fallback = NIF.tempo_discovery_finish(s)
      end

      assert {:ok, json} = TempoDiscovery.json(rows, scope, key, discovery_query: c["query"])
      assert Pulse.JSON.decode!(json) == c["response"], inspect(c)
    end
  end

  test "MCP and reference fallback never route new values through old scoped callbacks; intrinsic fields are not attributes" do
    {rows, cases} = fixture()
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    assert :ok = Storage.append(:traces, "new-values", rows)
    Runtime.put_env(:pulse, Storage, adapter: ScopedTraceDiscoveryStorage)

    for c <- Enum.filter(cases, &(String.starts_with?(&1["target"], ".") or not String.contains?(&1["target"], "."))) do
      {scope, key} = target(c["target"])

      assert {:ok, [%{"text" => json}]} =
               Tools.call("discover_trace_tag_values", %{"tenant" => "new-values", "scope" => scope, "key" => key})

      assert Pulse.JSON.decode!(json) == c["response"]
      assert {:ok, _} = TempoDiscovery.query("new-values", scope, key, 1)
    end

    for scope <- ["span", "instrumentation", "none"] do
      assert {:ok, ~s'{"tagValues":[]}'} = TempoDiscovery.json(rows, scope, "name", [])
    end

    assert {:error, :unsupported_trace_discovery} =
             TempoDiscovery.query("new-values", "none", "value", 2, "json", ~s'{resource.value="never"}')

    assert :fallback =
             NIF.tempo_filtered_discovery_new(0, "none", "value", [{"resource", "value", "=", "never"}])

    for {scope, key} <- [{"none", "value"}, {"intrinsic", "name"}] do
      assert {:error, :trace_metadata_unknown} = TempoDiscovery.json([%{hd(rows) | otlp: nil}], scope, key, [])
      assert {:error, :query_scan_limit} = TempoDiscovery.json(rows, scope, key, max_scan_rows: 1)
    end

    for key <- ["root.name", "root.service.name"] do
      assert {:error, :unsupported_trace_discovery} = TempoDiscovery.query("new-values", "none", key)
    end
  end

  test "filtered intrinsic strings are complete matching-parent values, without upstream pre-join omissions" do
    {rows, _} = fixture()
    dir = Path.expand("../../fixtures/traces", __DIR__)
    raw = File.read!(Path.join(dir, "tempo-dynamic-filters-oracle.json"))

    assert Base.encode16(:crypto.hash(:sha256, raw), case: :lower) ==
             "f65ce3b464b100b6fd9f2cf330ae560e1993d1b62961cdca922d54d5307f844d"

    cases = Pulse.JSON.decode!(raw)
    assert length(cases) == 42
    assert Enum.count(cases, &(&1["raw"] != &1["complete"])) == 12
    {:ok, blob, _, _} = S3.encode_segment(:traces, Enum.reverse(rows))
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    assert :ok = Storage.append(:traces, "filtered", rows)
    Runtime.put_env(:pulse, Storage, adapter: ScopedTraceDiscoveryStorage)

    for c <- cases do
      {:ok, s} = state(c)
      assert {:ok, _} = NIF.tempo_discovery_add(s, blob)
      assert {:ok, json} = NIF.tempo_discovery_finish(s)
      assert Pulse.JSON.decode!(json) == c["complete"], inspect(c)
      assert {:ok, json} = TempoDiscovery.json(rows, "intrinsic", c["target"], discovery_query: c["query"])
      assert Pulse.JSON.decode!(json) == c["complete"], inspect(c)

      assert {:ok, [%{"text" => json}]} =
               Tools.call("discover_trace_tag_values", %{
                 "tenant" => "filtered",
                 "scope" => "intrinsic",
                 "key" => c["target"],
                 "query" => c["query"]
               })

      assert Pulse.JSON.decode!(json) == c["complete"]
    end
  end

  test "stored intrinsic failures are not static vocabulary; empty strings are effective protobuf defaults" do
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    Runtime.put_env(:pulse, Storage, adapter: FailingStorage)

    for key <-
          ~w(name span:name statusMessage span:statusMessage instrumentation:name instrumentation:version event:name) do
      assert {:error, :storage_unavailable} = TempoDiscovery.query("empty", "intrinsic", key)
    end

    assert {:ok, _} = TempoDiscovery.query("empty", "intrinsic", "kind")
    {rows, _} = fixture()
    no_events = Enum.filter(rows, &(&1.events == []))
    assert {:ok, ~s'{"tagValues":[]}'} = TempoDiscovery.json(no_events, "intrinsic", "event:name", [])
    assert {:ok, json} = TempoDiscovery.json(rows, "intrinsic", "statusMessage", [])
    assert %{"type" => "string"} in Pulse.JSON.decode!(json)["tagValues"]
  end

  test "stored intrinsic dictionaries reject cardinality and escaped output independently, and poison on unknown nonmatches" do
    {rows, _} = fixture()
    base = hd(rows)
    many = for i <- 1..5001, do: %{base | name: "distinct_#{i}"}
    {:ok, blob, _, _} = S3.encode_segment(:traces, many)
    {:ok, s} = NIF.tempo_discovery_new(0, "intrinsic", "name")
    assert {:error, :query_resource_limit} = NIF.tempo_discovery_add(s, blob)
    assert :fallback = NIF.tempo_discovery_finish(s)
    assert {:error, :query_resource_limit} = TempoDiscovery.json(many, "intrinsic", "name", [])
    escaped = for i <- 1..1000, do: %{base | name: String.duplicate(<<0>>, 256) <> "#{i}"}
    {:ok, blob, _, _} = S3.encode_segment(:traces, escaped)
    {:ok, s} = NIF.tempo_discovery_new(0, "intrinsic", "name")
    assert {:ok, 1000} = NIF.tempo_discovery_add(s, blob)
    assert {:error, :query_resource_limit} = NIF.tempo_discovery_finish(s)
    assert :fallback = NIF.tempo_discovery_finish(s)
    assert {:error, :query_resource_limit} = TempoDiscovery.json(escaped, "intrinsic", "name", [])
    {:ok, blob, _, _} = S3.encode_segment(:traces, [%{base | otlp: nil}])

    {:ok, s} =
      NIF.tempo_filtered_discovery_new(0, "intrinsic", "event:name", [{"resource", "service.name", "=", "absent"}])

    assert {:error, :trace_metadata_unknown} = NIF.tempo_discovery_add(s, blob)
    assert :fallback = NIF.tempo_discovery_finish(s)
  end

  test "dynamic event names charge parent plus every owner and attribute before returning any values" do
    {rows, _} = fixture()
    base = Enum.find(rows, &(&1.events != []))
    event = hd(base.events) |> Map.put("attributes", %{}) |> Map.put("name", "constant")
    dense = %{base | events: List.duplicate(event, 2000), otlp: Map.put(base.otlp, "events", List.duplicate([], 2000))}
    {:ok, blob, _, _} = S3.encode_segment(:traces, [dense])
    {:ok, s} = NIF.tempo_discovery_new(0, "intrinsic", "event:name")
    for _ <- 1..999, do: assert({:ok, 1} = NIF.tempo_discovery_add(s, blob))
    assert {:error, :trace_discovery_work_limit} = NIF.tempo_discovery_add(s, blob)
    assert :fallback = NIF.tempo_discovery_finish(s)

    assert {:error, :trace_discovery_work_limit} =
             TempoDiscovery.json(List.duplicate(dense, 1000), "intrinsic", "event:name", [])
  end
end
