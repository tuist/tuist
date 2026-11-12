defmodule Pulse.OTLP.ElixirSDKTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Storage.S3
  alias Pulse.Storage.SortOrder
  alias Pulse.Test.ElixirSDKAssertions
  alias Pulse.Traces.{Assembly, Tempo}

  @fixtures Path.expand("../../fixtures/traces/elixir_sdk", __DIR__)
  @manifest_sha "4cc29459e456387b3151e3fbde3840b0198b3506ccadcfb1230f69fa3c8a572e"

  test "frozen producer sources, dependency locks and captures have immutable provenance" do
    bytes = File.read!(Path.join(@fixtures, "checksums.json"))
    assert sha(bytes) == @manifest_sha

    for {name, expected} <- Pulse.JSON.decode!(bytes) do
      assert sha(File.read!(Path.join(@fixtures, name))) == expected, name
    end
  end

  for profile <- ~w(modern legacy), protocol <- ~w(http grpc) do
    @profile profile
    @protocol protocol
    test "#{profile} #{protocol} SDK record losses are explicit and received metadata survives compaction and export" do
      prefix = @profile <> "-" <> @protocol
      assert {:ok, sdk, 0} = Traces.decode_protobuf(fixture(prefix <> "-sdk.protobuf"))
      assert {:ok, delivered, 0} = Traces.decode_protobuf(fixture(prefix <> "-delivered.protobuf"))
      assert Enum.sort_by(sdk, & &1.span_id) === Enum.sort_by(delivered, & &1.span_id)
      oracle = Pulse.JSON.decode!(fixture(prefix <> "-oracle.json"))
      ElixirSDKAssertions.assert_versions(oracle, @profile)
      assert oracle["flush"] == ":ok"
      assert oracle["export"] == %{"count" => 5, "result" => ":ok"}
      ElixirSDKAssertions.assert_spans(delivered, oracle)

      blobs =
        Enum.map(delivered, fn row ->
          assert {:ok, blob, _, _} = S3.encode_segment(:traces, [row])
          blob
        end)

      assert {:ok, merged, _, _, 5, _, _} = NIF.compact_trace_segments(blobs, 100)
      assert {:ok, decoded} = S3.decode_segment(:traces, merged, nil, nil, [])
      ElixirSDKAssertions.assert_spans(decoded, oracle)
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
  end

  defp fixture(name) do
    manifest = File.read!(Path.join(@fixtures, "checksums.json"))
    assert sha(manifest) == @manifest_sha
    bytes = File.read!(Path.join(@fixtures, name))
    assert sha(bytes) == Map.fetch!(Pulse.JSON.decode!(manifest), name)
    bytes
  end

  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
