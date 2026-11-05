defmodule Pulse.OTLP.SDKBridgeTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Storage.S3
  alias Pulse.Storage.SortOrder
  alias Pulse.Test.CollectorBridgeTap
  alias Pulse.Test.SDKBridgeAssertions
  alias Pulse.Traces.{Assembly, Tempo}

  @fixtures Path.expand("../../fixtures/traces/collector_bridge", __DIR__)
  @hashes %{
    "../produce_sdk_bridge.go.txt" => "4bd4ed2b4bc4699e798093aa8e15d3eb58b5eecd407458c01f621059185d086e",
    "../sdk-bridge.go.mod.txt" => "1b8d0366e4a8585265b03b342e26ec796d6fa7a0559b50ee3821ee27ab544fe3",
    "../sdk-bridge.go.sum.txt" => "3c0e4cc1e2fe9edf04b373eaa2fc0928559602c05f5c29ab0134be7a54b86001",
    "sdk-request.protobuf" => "0c41960561d3d93e066a99178266090e1cd0d06926e9c06cb1d479eaf92cfab1",
    "collector-request.protobuf" => "6d54d47fa6e9676145696adcda14afea6b6bbf8017a98960b1d82f9aa64c4ed8",
    "sdk-oracle.json" => "d9bfb3897bcfba2b4eece63712a38a31842f696319f2abc493d0c3bdbd4226b5",
    "sdk-buildinfo.txt" => "19004d69934f5e5f53507e7b263eeec10b227c58c93f739c16c43d1ae95e315f",
    "split-collector-request.protobuf" => "da01f7c8b92f26f5eff721172fb168e3a4d4c6055855b8bb09e1d6d38397e40f",
    "partial-producer.protobuf" => "977747b0c64211e2b07187a7d5c333ead8cb542ec35e12707247e185c54ce967",
    "partial-collector.protobuf" => "19cdc88fac71f448c59140a510ac07c8e67eeae7f002abaf213f93baab971bfe",
    "partial-result.json" => "a85bb10c2fe3983a53c315cdb3ac52f4f45e347a3167a31b5ff9bddc3126a1fe"
  }

  defp fixture(name) do
    bytes = File.read!(Path.join(@fixtures, name))
    assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == Map.fetch!(@hashes, name)
    bytes
  end

  defp rows(name) do
    assert {:ok, rows, 0} = Traces.decode_protobuf(fixture(name))
    Enum.sort_by(rows, & &1.span_id)
  end

  test "real SDK export request and non-rebatching Collector preserve the same complete typed spans" do
    for name <- ~w(../produce_sdk_bridge.go.txt ../sdk-bridge.go.mod.txt ../sdk-bridge.go.sum.txt sdk-buildinfo.txt),
        do: fixture(name)

    sdk = rows("sdk-request.protobuf")
    delivered = rows("collector-request.protobuf")
    assert sdk === delivered
    oracle = Pulse.JSON.decode!(fixture("sdk-oracle.json"))
    SDKBridgeAssertions.assert_spans(delivered, oracle)

    blobs =
      Enum.map(delivered, fn row ->
        assert {:ok, blob, _, _} = S3.encode_segment(:traces, [row])
        blob
      end)

    assert {:ok, merged, _, _, 3, _, _} = NIF.compact_trace_segments(blobs, 100)
    assert {:ok, decoded} = S3.decode_segment(:traces, merged, nil, nil, [])
    SDKBridgeAssertions.assert_spans(decoded, oracle)
    trace_id = hd(delivered).trace_id
    assert {:ok, state} = NIF.trace_query_new_trace(trace_id, nil, 100)
    assert {:ok, _} = NIF.trace_query_add(state, merged)
    assert {:ok, native} = NIF.trace_query_finish_trace(state, 100, trace_id)
    assert {:ok, reference} = Assembly.json(SortOrder.sort(decoded, :traces), trace_id)
    assert Pulse.JSON.decode!(native) === Pulse.JSON.decode!(reference)

    for format <- ["json", "json_v2", "protobuf", "protobuf_v2"] do
      assert {:ok, actual} = NIF.tempo_trace_export(native, format)
      assert {:ok, expected} = Tempo.reference(reference, format)

      if String.starts_with?(format, "json"),
        do: assert(Pulse.JSON.decode!(actual) === Pulse.JSON.decode!(expected)),
        else: assert(actual == expected)
    end
  end

  test "captured Collector split loses schema URLs before Pulse; readers do not invent them" do
    sdk = rows("sdk-request.protobuf")
    split = rows("split-collector-request.protobuf")
    assert Enum.map(sdk, & &1.span_id) == Enum.map(split, & &1.span_id)
    different = Enum.filter(Enum.zip(sdk, split), fn {a, b} -> a !== b end)
    assert [{source, lost}] = different
    assert source.name == "database request"
    assert source.resource_schema_url != "" and source.scope_schema_url != ""
    assert lost.resource_schema_url == "" and lost.scope_schema_url == ""
    assert %{source | resource_schema_url: "", scope_schema_url: ""} === lost
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, split)
    assert {:ok, decoded} = S3.decode_segment(:traces, blob, nil, nil, [])
    assert Enum.sort_by(decoded, & &1.span_id) === split
  end

  test "capture exhaustion preserves evidence and retry state instead of restarting its Agent" do
    state = %{
      count: 64,
      requests: List.duplicate(:owned_evidence, 64),
      failures: %{"alpha" => [429, 503]},
      owner: self()
    }

    agent = start_supervised!({Agent, fn -> state end})
    conn = Plug.Conn.put_req_header(Plug.Test.conn("POST", "/v1/traces", ""), "x-scope-orgid", "alpha")

    assert_raise RuntimeError, "bridge request evidence limit exceeded", fn ->
      CollectorBridgeTap.call(conn, agent: agent)
    end

    assert Agent.get(agent, & &1) == state
  end

  test "public malformed-span probe remains partial without Collector repair or whole-batch replay" do
    assert {:ok, [producer], 1} = Traces.decode_protobuf(fixture("partial-producer.protobuf"))
    assert {:ok, [delivered], 1} = Traces.decode_protobuf(fixture("partial-collector.protobuf"))
    assert producer === delivered
    assert delivered.name == "partial valid"
    result = Pulse.JSON.decode!(fixture("partial-result.json"))
    assert result["grpc_code"] == "OK"
    assert result["response"] == "partial_success:{}"
    # Actual no-retry/backend rejectedSpans=1 observations live in the optional
    # process harness, not established by this fixture-only replay.
  end
end
