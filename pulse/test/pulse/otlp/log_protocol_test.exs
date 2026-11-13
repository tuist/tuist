defmodule Pulse.OTLP.LogProtocolTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.IngestLimits
  alias Pulse.OTLP.Logs
  alias Pulse.OTLP.Value
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Test.OTLPLogFixture, as: Fixture
  alias Pulse.Test.OTLPTraceFixture

  test "official protoc wire and independently decoded OTLP JSON retain the same typed content" do
    assert {:ok, logs, 0} = Logs.decode(Fixture.json())
    assert {:ok, wire_logs, 0} = Logs.decode_protobuf(Fixture.protobuf())
    assert :erlang.term_to_binary(logs, [:deterministic]) == :erlang.term_to_binary(wire_logs, [:deterministic])
    [log, bytes_log] = logs
    assert log.service == "example-api"
    assert log.trace_id == "30313233343536373839616263646566"
    assert log.span_id == "6465616462656566"
    assert log.observed_timestamp_ns == 1_700_000_000_123_456_790
    assert log.resource["deployment.environment"] == "production"
    assert log.resource["deployment.environment.name"] == "production"
    assert log.otlp["flags"] == 4_294_967_295
    assert log.otlp["eventName"] == "example.login"
    assert log.otlp["droppedAttributesCount"] == 3
    assert log.otlp["resource"]["droppedAttributesCount"] == 1
    assert log.otlp["scope"]["droppedAttributesCount"] == 2
    assert log.otlp["scope"]["attributes"] == [%{"key" => "enabled", "value" => %{"boolValue" => false}}]
    assert log.otlp["resourceSchemaUrl"] == "https://opentelemetry.io/schemas/1.27.0"
    assert log.otlp["scopeSchemaUrl"] == "https://example.com/log-schema/1"
    assert log.attributes["bytes"] == log.attributes["string"]
    assert Enum.at(log.otlp["attributes"], 0)["value"] == %{"bytesValue" => "AP8="}
    assert Enum.at(log.otlp["attributes"], 1)["value"] == %{"stringValue" => "AP8="}

    assert log.body["numbers"] == [
             9_223_372_036_854_775_807,
             -9_223_372_036_854_775_808,
             -0.0,
             "NaN",
             "Infinity",
             "-Infinity",
             nil
           ]

    assert float_bits(Enum.at(log.body["numbers"], 2)) == <<0x8000000000000000::64>>
    assert bytes_log.otlp["body"] == %{"bytesValue" => "aGVsbG8="}
    assert bytes_log.observed_timestamp_ns == nil
    assert {:ok, blob, _, _} = S3.encode_segment(:logs, logs)
    assert {:ok, decoded} = S3.decode_segment(:logs, blob, nil, nil, [])
    assert :erlang.term_to_binary(decoded, [:deterministic]) == :erlang.term_to_binary(logs, [:deterministic])
  end

  test "JSON null optional fields normalize as unset, not malformed values" do
    payload = %{
      "resourceLogs" => [
        %{
          "resource" => nil,
          "scopeLogs" => [
            %{
              "scope" => nil,
              "logRecords" => [%{"timeUnixNano" => nil, "body" => nil, "attributes" => nil, "flags" => nil}]
            }
          ]
        }
      ]
    }

    assert {:ok, [log], 0} = Logs.decode(payload)
    assert log.timestamp_ns == nil
    assert log.body == nil
    assert log.otlp["body"] == %{}
    assert Value.decode(%{"stringValue" => nil, "intValue" => "42"}) == {:ok, 42, %{"intValue" => "42"}}
    assert Value.decode(%{"arrayValue" => %{"values" => [nil]}}) == :error
  end

  test "invalid semantic records reject individually but invalid resource or scope rejects the request" do
    bad = [
      %{"timeUnixNano" => "9223372036854775808"},
      %{"body" => %{"boolValue" => "true"}},
      %{"body" => %{"kvlistValue" => %{"values" => 1}}}
    ]

    assert {:ok, [good], 3} = Logs.decode(Fixture.payload(bad ++ [List.last(Fixture.records())]))
    assert good.body == "aGVsbG8="

    for field <- ["resource", "scope"] do
      path =
        if field == "resource",
          do: ["resourceLogs", Access.at(0), "resource"],
          else: ["resourceLogs", Access.at(0), "scopeLogs", Access.at(0), "scope"]

      bad = put_in(Fixture.json(), path, %{"attributes" => [%{"key" => "broken", "value" => %{"boolValue" => "true"}}]})
      assert Logs.decode(bad) == {:error, :invalid_otlp}
    end
  end

  test "bodies are not subject to the 16 KiB attribute string limit, in either encoding" do
    raw = %{"body" => %{"stringValue" => String.duplicate("x", 32_768)}}
    payload = Fixture.payload([raw])
    assert {:ok, [_], 0} = Logs.decode(payload)
    assert {:ok, [_], 0} = Logs.decode_protobuf(Fixture.protobuf(payload))
    bad = Map.put(raw, "attributes", [%{"key" => "large", "value" => raw["body"]}])
    assert Logs.decode(Fixture.payload([bad])) == {:error, :attributes_too_large}
    assert Logs.decode_protobuf(Fixture.protobuf(Fixture.payload([bad]))) == {:error, :attributes_too_large}
  end

  test "normalized repeated metadata and escaped body amplification reject before row allocation" do
    body = %{"body" => %{"stringValue" => :binary.copy(<<0>>, 1_500_000)}}
    assert Logs.decode(Fixture.payload([body])) == {:error, :payload_too_large}
    assert Logs.decode_protobuf(Fixture.protobuf(Fixture.payload([body]))) == {:error, :payload_too_large}
    payload = Fixture.payload(List.duplicate(%{}, 400))
    path = ["resourceLogs", Access.at(0), "resource", "attributes"]
    payload = put_in(payload, path, [%{"key" => "large", "value" => %{"stringValue" => String.duplicate("r", 16_384)}}])

    payload =
      put_in(payload, ["resourceLogs", Access.at(0), "scopeLogs", Access.at(0), "scope", "attributes"], [
        %{"key" => "large", "value" => %{"stringValue" => String.duplicate("s", 16_384)}}
      ])

    assert Logs.decode(payload) == {:error, :payload_too_large}
  end

  test "request-node and duplicate supplied attribute budgets run before semantic rejection" do
    Runtime.put_env(:pulse, IngestLimits, max_otlp_nodes: 8)
    assert Logs.decode(Fixture.json()) == {:error, :too_many_otlp_nodes}
    assert Logs.decode_protobuf(Fixture.protobuf()) == {:error, :too_many_otlp_nodes}
    Runtime.put_env(:pulse, IngestLimits, max_attributes: 2)
    payload = Fixture.payload([%{"attributes" => List.duplicate(%{"key" => "a", "value" => %{"intValue" => 1}}, 3)}])
    assert Logs.decode(payload) == {:error, :attributes_too_large}
    assert Logs.decode_protobuf(Fixture.protobuf(payload)) == {:error, :attributes_too_large}
    Runtime.put_env(:pulse, IngestLimits, max_value_bytes: 4)
    invalid_oneof = %{"stringValue" => "ok", "intValue" => "123456789"}

    assert Logs.decode(Fixture.payload([%{"attributes" => [%{"key" => "a", "value" => invalid_oneof}]}])) ==
             {:error, :attributes_too_large}
  end

  test "duplicate singular messages merge while malformed UTF-8 fails closed" do
    alias OTLPTraceFixture, as: Wire

    resource = Wire.bytes(1, Wire.message(%{}, :resource))
    assert Logs.decode_protobuf(Wire.bytes(1, resource <> resource)) == {:ok, [], 0}

    payload =
      put_in(Fixture.payload([]), ["resourceLogs", Access.at(0), "scopeLogs", Access.at(0), "scope", "name"], <<255>>)

    assert Logs.decode_protobuf(Fixture.protobuf(payload)) == {:error, :invalid_protobuf}
    assert Logs.decode_protobuf(<<10, 128>>) == {:error, :invalid_protobuf}
  end

  test "known unsupported entity references reject in JSON and protobuf rather than disappear" do
    alias OTLPTraceFixture, as: Wire

    payload = put_in(Fixture.json(), ["resourceLogs", Access.at(0), "resource", "entityRefs"], [%{}])
    assert Logs.decode(payload) == {:error, :invalid_otlp}
    assert Logs.decode_protobuf(Wire.bytes(1, Wire.bytes(1, Wire.bytes(3, "")))) == {:error, :invalid_protobuf}
  end

  test "size counter agrees with reference encoding and checks inclusive byte boundaries" do
    assert {:ok, logs, 0} = Logs.decode(Fixture.json())
    assert {:ok, json, _, _, _} = NIF.encode_log_segment(logs, :storage, :array)
    size = byte_size(json)
    assert NIF.log_payload_size(logs, size) == {:ok, size}
    assert NIF.log_payload_size(logs, size - 1) == {:error, :payload_too_large}
    assert NIF.encode_log_segment_bounded(logs, size) == {:ok, json}
    assert NIF.encode_log_segment_bounded(logs, size - 1) == {:error, :query_result_limit}
    assert NIF.log_metadata_api_version() == 1
    assert NIF.ensure_log_metadata_api!() == :ok
  end

  test "integer conversion rejects oversized significant decimals without constructing bignums" do
    assert Value.integer(String.duplicate("1", 100_000), 0, 10) == :error
    # Match public ProtoJSON: leading-zero integer strings are invalid, while
    # a canonical wide fractional coefficient can still be exact and bounded.
    assert Value.integer(String.duplicate("0", 100_000) <> "7", 0, 10) == :error
    assert Value.integer("0." <> String.duplicate("0", 100_000) <> "7e100001", 0, 10) == {:ok, 7}
    assert Value.integer("-9223372036854775808", -9_223_372_036_854_775_808, 0) == {:ok, -9_223_372_036_854_775_808}
    assert Value.integer("+", 0, 10) == :error
  end

  test "retained values do not pin an unrelated large JSON input arena" do
    arena = String.duplicate("z", 1_000_000)
    selected = binary_part(arena, 0, 128)
    assert :binary.referenced_byte_size(selected) > byte_size(selected)
    assert {:ok, value, raw} = Value.decode(%{"stringValue" => selected})
    assert :binary.referenced_byte_size(value) == 128
    assert :binary.referenced_byte_size(raw["stringValue"]) == 128
  end

  defp float_bits(value), do: <<value::float-64>>
end
