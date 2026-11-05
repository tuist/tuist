defmodule Pulse.OTLP.WireProtocolTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.IngestLimits
  alias Pulse.OTLP.JSON
  alias Pulse.OTLP.{Logs, Metrics, Traces, Value}
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Test.OTLPTraceFixture, as: Wire

  @directory "test/fixtures/otlp/wire"

  test "frozen public reference inputs and captures match their checksum index" do
    manifest = @directory |> Path.join("checksums.json") |> File.read!() |> Pulse.JSON.decode!()
    assert manifest["otlp"] == "v1.9.0"
    assert manifest["google_protobuf"] == "v1.36.11"
    assert map_size(manifest["files"]) == 16

    for {path, expected} <- manifest["files"] do
      bytes = File.read!(Path.join(@directory, path))
      assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == expected, path
    end
  end

  test "public Google protobuf merges resource, scope, status and AnyValue across all signals" do
    for {name, decoder, signal, count} <- [
          {"logs", Logs, :logs, 1},
          {"metrics", Metrics, :metrics, 2},
          {"traces", Traces, :traces, 1}
        ] do
      expected = @directory |> Path.join(name <> ".json") |> File.read!() |> JSON.decode!()
      assert {:ok, records, 0} = decoder.decode(expected)
      assert length(records) == count

      for suffix <- [".protobuf", "-canonical.protobuf"] do
        assert {:ok, wire, 0} = decoder.decode_protobuf(File.read!(Path.join(@directory, name <> suffix)))
        assert :erlang.term_to_binary(wire, [:deterministic]) == :erlang.term_to_binary(records, [:deterministic])
      end

      assert_owner_metadata(signal, hd(records))
      assert {:ok, blob, _, _} = S3.encode_segment(signal, records)
      assert {:ok, decoded} = S3.decode_segment(signal, blob, nil, nil, [])

      assert :erlang.term_to_binary(Enum.map(decoded, & &1.otlp), [:deterministic]) ==
               :erlang.term_to_binary(Enum.map(records, & &1.otlp), [:deterministic])
    end

    assert {:ok, [log], 0} = Logs.decode_protobuf(File.read!(Path.join(@directory, "logs.protobuf")))
    assert log.body == ["first", "second"]
    assert log.attributes["nested"] == %{"a" => "one", "b" => "two"}
    assert {:ok, metrics, 0} = Metrics.decode_protobuf(File.read!(Path.join(@directory, "metrics.protobuf")))
    assert Enum.map(metrics, & &1.value) == [7.0, 8.0]
    assert Enum.map(metrics, & &1.otlp["point"]["asInt"]) == ["7", "8"]
    assert Enum.all?(metrics, &(not Map.has_key?(&1.otlp["point"], "asDouble")))

    for sample <- metrics do
      assert [%{"asInt" => "9"} = exemplar] = sample.otlp["point"]["exemplars"]
      refute Map.has_key?(exemplar, "asDouble")
    end

    assert {:ok, [span], 0} = Traces.decode_protobuf(File.read!(Path.join(@directory, "traces.protobuf")))
    assert span.status == %{"code" => 1, "message" => "retained status"}
  end

  test "split singular owners cannot bypass cumulative attribute counts, bytes or nodes" do
    for decoder <- [Logs, Metrics, Traces] do
      Runtime.put_env(:pulse, IngestLimits, max_attributes: 2)

      attrs =
        for key <- ["a", "b", "c"],
            do: Wire.bytes(1, Wire.message(%{"key" => key, "value" => %{"stringValue" => "v"}}, :pair))

      resource =
        Wire.bytes(1, Wire.bytes(1, Enum.at(attrs, 0) <> Enum.at(attrs, 1)) <> Wire.bytes(1, Enum.at(attrs, 2)))

      assert {:error, :attributes_too_large} = decoder.decode_protobuf(resource)
      Runtime.put_env(:pulse, IngestLimits, max_attribute_bytes: 7)
      # Each fragment is six bytes, but together they exceed seven.
      assert {:error, :attributes_too_large} = decoder.decode_protobuf(split_resource("12345"))
      Runtime.put_env(:pulse, IngestLimits, max_nodes: 3)
      # Each Pair/Any fragment has two attribute nodes. Four cannot fit.
      assert {:error, :attributes_too_large} = decoder.decode_protobuf(split_resource("v"))
    end
  end

  test "overwritten oneof contents remain charged to their merged owner's attribute budget" do
    # Each resource fragment supplies 2 * 20,000 bytes through oneof scalar
    # replacement. The final values total only 40,002 bytes, but the source
    # supplied 80,002: final-tree-only validation would incorrectly accept it.
    value =
      Wire.bytes(2, Wire.bytes(1, String.duplicate("a", 20_000))) <>
        Wire.bytes(2, Wire.bytes(1, String.duplicate("b", 20_000)))

    fragment = fn key -> Wire.bytes(1, Wire.bytes(1, Wire.bytes(1, key) <> value)) end
    payload = Wire.bytes(1, fragment.("a") <> fragment.("b"))
    Runtime.put_env(:pulse, IngestLimits, max_value_bytes: 30_000)

    for decoder <- [Logs, Metrics, Traces] do
      assert {:error, :attributes_too_large} = decoder.decode_protobuf(payload)
    end
  end

  test "losing metric data members still consume source record admission" do
    Runtime.put_env(:pulse, IngestLimits, max_records: 3)
    assert {:error, :too_many_records} = Metrics.decode_protobuf(File.read!(Path.join(@directory, "metrics.protobuf")))
    assert {:ok, [_, _], 0} = Metrics.decode_protobuf(File.read!(Path.join(@directory, "metrics-canonical.protobuf")))
  end

  test "quoted decimal and exponent integers match the public ProtoJSON implementation exactly" do
    cases = @directory |> Path.join("numeric-strings.json") |> File.read!() |> Pulse.JSON.decode!()
    assert length(cases) == 60

    for row <- cases do
      {low, high} =
        if row["kind"] == "int64",
          do: {-9_223_372_036_854_775_808, 9_223_372_036_854_775_807},
          else: {0, 18_446_744_073_709_551_615}

      if row["accepted"] do
        assert Value.integer(row["literal"], low, high) == {:ok, String.to_integer(row["expected"])}, inspect(row)
      else
        assert Value.integer(row["literal"], low, high) == :error, inspect(row)
      end
    end

    assert {:ok, 1} = Value.integer("0." <> String.duplicate("0", 1000) <> "1e1001", 0, 10)
    assert :error = Value.integer("1e" <> String.duplicate("9", 1000), 0, 10)
    assert :error = Value.integer("1e-" <> String.duplicate("9", 1000), 0, 10)
    assert :error = Value.integer("1" <> String.duplicate("0", 100_000) <> "e-99999", 0, 9)
  end

  test "quoted exponent integers preserve typed owners and nanosecond source time across signals" do
    assert {:ok, 9_007_199_254_740_993, %{"intValue" => "9007199254740993"}} =
             Value.decode(%{"intValue" => "9007199254740993.0"})

    for {name, decoder} <- [{"logs", Logs}, {"metrics", Metrics}, {"traces", Traces}] do
      json = @directory |> Path.join(name <> ".json") |> File.read!()
      assert {:ok, original, 0} = json |> JSON.decode!() |> decoder.decode()
      changed = String.replace(json, "1700000000123456789", "1.700000000123456789e18")
      assert {:ok, ^original, 0} = changed |> JSON.decode!() |> decoder.decode()
    end
  end

  test "unknown wire occurrences consume request-node admission before semantic filtering" do
    Runtime.put_env(:pulse, IngestLimits, max_otlp_nodes: 2, max_trace_nodes: 2)
    payload = Wire.bytes(99, "") <> Wire.bytes(99, "")
    assert {:error, :too_many_otlp_nodes} = Logs.decode_protobuf(payload)
    assert {:error, :too_many_otlp_nodes} = Metrics.decode_protobuf(payload)
    assert {:error, :too_many_trace_nodes} = Traces.decode_protobuf(payload)
  end

  test "wire capability is independently fenced without changing stored signal formats" do
    assert NIF.otlp_wire_api_version() == 3
    assert :ok = NIF.ensure_otlp_wire_api!()
    assert NIF.log_metadata_api_version() == 1
    assert NIF.trace_metadata_api_version() == 2
    assert NIF.metric_metadata_api_version() == 2
    assert NIF.otlp_metrics_api_version() == 2
  end

  defp assert_owner_metadata(:traces, record) do
    assert record.scope["name"] == "wire.scope"
    assert record.scope["version"] == "1.0"
    assert length(record.otlp["scope"]) == 2
    assert_scope_zero(record.otlp["scope"])
    assert length(record.otlp["resource"]) == 2
    assert record.resource_dropped_attributes_count == 0
  end

  defp assert_owner_metadata(_signal, record) do
    assert record.otlp["scope"]["name"] == "wire.scope"
    assert record.otlp["scope"]["version"] == "1.0"
    assert length(record.otlp["scope"]["attributes"]) == 2
    assert_scope_zero(record.otlp["scope"]["attributes"])
    assert length(record.otlp["resource"]["attributes"]) == 2
    assert record.otlp["resource"]["droppedAttributesCount"] == 0
  end

  defp assert_scope_zero(attributes) do
    assert %{"value" => %{"doubleValue" => zero}} = Enum.find(attributes, &(&1["key"] == "scope.first"))
    assert <<zero::float-64>> == <<0x8000000000000000::64>>
  end

  defp split_resource(value) do
    pair = fn key -> Wire.message(%{"key" => key, "value" => %{"stringValue" => value}}, :pair) end
    Wire.bytes(1, Wire.bytes(1, Wire.bytes(1, pair.("a"))) <> Wire.bytes(1, Wire.bytes(1, pair.("b"))))
  end
end
