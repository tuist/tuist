defmodule Pulse.OTLP.RustSDKTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Storage.S3
  alias Pulse.Storage.SortOrder
  alias Pulse.Test.RustSDKAssertions
  alias Pulse.Traces.{Assembly, Tempo}

  @root Path.expand("../../fixtures/traces", __DIR__)
  @manifest_sha "f7256df86d7d6209b0df4be7acdd1f6a893a726d02cb9d356728627fede617c9"

  test "frozen sources, full dependency lock, resolved features and actual captures have immutable provenance" do
    manifest = File.read!(Path.join(@root, "rust_sdk/checksums.json"))
    assert sha(manifest) == @manifest_sha
    index = Pulse.JSON.decode!(manifest)
    assert map_size(index) == 15

    for {name, expected} <- index do
      assert sha(File.read!(Path.join(@root, name))) == expected, name
    end

    lock = fixture("rust-sdk.Cargo.lock.txt")
    versions = Regex.scan(~r/^name = "([^"]+)"\nversion = "([^"]+)"$/m, lock, capture: :all_but_first)

    assert length(versions) == 144

    for pair <- [
          ["opentelemetry", "0.31.0"],
          ["opentelemetry_sdk", "0.31.0"],
          ["opentelemetry-otlp", "0.31.1"],
          ["opentelemetry-proto", "0.31.0"],
          ["tracing-opentelemetry", "0.32.1"],
          ["tracing-subscriber", "0.3.23"],
          ["reqwest", "0.12.28"],
          ["tonic", "0.14.5"],
          ["prost", "0.14.3"],
          ["tokio", "1.52.1"],
          ["hyper", "1.9.0"],
          ["h2", "0.4.13"],
          ["http", "1.4.0"],
          ["futures-executor", "0.3.32"]
        ] do
      assert pair in versions
    end
  end

  for protocol <- ~w(http http-env grpc) do
    @protocol protocol
    test "#{protocol} actual Rust SDK metadata survives receipt, native compaction, assembly and Tempo export" do
      prefix = "rust_sdk/" <> @protocol
      assert {:ok, sdk, 0} = Traces.decode_protobuf(fixture(prefix <> "-sdk.protobuf"))
      assert {:ok, delivered, 0} = Traces.decode_protobuf(fixture(prefix <> "-delivered.protobuf"))
      assert Enum.sort_by(sdk, & &1.span_id) === Enum.sort_by(delivered, & &1.span_id)
      oracle = Pulse.JSON.decode!(fixture(prefix <> "-oracle.json"))
      assert oracle["export_errors"] == []
      assert oracle["flush"] == nil
      assert oracle["shutdown"] == nil
      RustSDKAssertions.assert_spans(delivered, oracle)

      blobs =
        Enum.map(delivered, fn row ->
          assert {:ok, blob, _, _} = S3.encode_segment(:traces, [row])
          blob
        end)

      assert {:ok, merged, _, _, 3, _, _} = NIF.compact_trace_segments(blobs, 100)
      assert {:ok, decoded} = S3.decode_segment(:traces, merged, nil, nil, [])
      RustSDKAssertions.assert_spans(decoded, oracle)
      trace_id = hd(decoded).trace_id
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

  test "frozen actual HTTP attempts disclose all whole rejections and transport-specific exporter results" do
    evidence = Pulse.JSON.decode!(fixture("rust_sdk/observations.json"))

    assert evidence["stored_counts"] == %{
             "http" => 3,
             "http-env" => 3,
             "grpc" => 3,
             "denied" => 0,
             "oversize" => 0,
             "unavailable" => 0,
             "rate" => 0,
             "malformed" => 0,
             "override" => 0,
             "untrusted-incoming-tenant" => 0
           }

    assert length(evidence["attempts"]) == 13
    assert map_size(evidence["producers"]) == 13

    assert Map.new(Enum.group_by(evidence["attempts"], & &1["tenant"]), fn {tenant, attempts} ->
             {tenant, Enum.map(attempts, & &1["status"])}
           end) == %{
             "http" => [200],
             "http-env" => [200],
             "grpc" => [200],
             "denied" => [401, 401],
             "oversize" => [413, 413],
             "unavailable" => [503, 503],
             "rate" => [429, 429],
             "malformed" => [401],
             "override" => [401]
           }

    for tenant <- ~w(denied oversize unavailable rate) do
      encodings = evidence["attempts"] |> Enum.filter(&(&1["tenant"] == tenant)) |> Enum.map(& &1["encoding"])
      assert Enum.sort(encodings) == [nil, "gzip"]
    end

    for attempt <- evidence["attempts"] do
      bytes = Base.decode64!(attempt["body"])
      bytes = if attempt["encoding"] == "gzip", do: :zlib.gunzip(bytes), else: bytes
      assert {:ok, spans, 0} = Traces.decode_protobuf(bytes)
      assert length(spans) == 3
    end

    for {name, producer} <- evidence["producers"] do
      if name in ~w(http http-env grpc),
        do: assert(producer["export_errors"] == []),
        else: RustSDKAssertions.assert_export_error(producer, String.replace_prefix(name, "grpc-", ""))

      assert producer["shutdown"] == nil
    end
  end

  defp fixture(name) do
    manifest = File.read!(Path.join(@root, "rust_sdk/checksums.json"))
    assert sha(manifest) == @manifest_sha
    bytes = File.read!(Path.join(@root, name))
    assert sha(bytes) == Map.fetch!(Pulse.JSON.decode!(manifest), name)
    bytes
  end

  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
