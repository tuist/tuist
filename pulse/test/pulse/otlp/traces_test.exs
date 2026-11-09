defmodule Pulse.OTLP.TracesTest do
  use Pulse.Test.Case, async: true

  alias Pulse.OTLP.Traces
  alias Pulse.Test.OTLPTraceFixture, as: Fixture

  test "decodes a synthetic payload from the Erlang OTel SDK's independent generated encoder" do
    body = File.read!(Path.expand("../../fixtures/otlp/erlang-exporter-traces.protobuf", __DIR__))
    assert {:ok, [span], 0} = Traces.decode_protobuf(body)
    assert span.service == "tuist-server"
    assert span.scope["name"] == "opentelemetry_phoenix"
    assert span.name == "GET /api/builds"
    assert span.kind == 2
    assert span.parent_span_id == nil
    assert span.flags == 257
    assert span.timestamp_ns == 1_700_000_000_123_456_789
    assert span.attributes["auth_account_handle"] == "acme"
    assert span.attributes["request_kind"] == "api"
    assert span.attributes["metrics.skip"] == false
    assert span.status["code"] == 2
    assert [%{"name" => "exception"}] = span.events
  end

  test "JSON and native protobuf retain all span metadata identically" do
    assert {:ok, [span], 0} = decoded = Traces.decode(Fixture.payload())
    assert Traces.decode_protobuf(Fixture.protobuf()) == decoded
    assert span.timestamp_ns == 1_700_000_000_123_456_789
    assert span.end_timestamp_ns - span.timestamp_ns == 1000
    assert span.service == "tuist-server"
    assert span.attributes["metrics.skip"] == false
    assert span.attributes["negative"] == -42
    assert span.attributes["http.response.status_code"] == 500
    assert span.attributes["bytes"] == "aGVsbG8="
    assert span.attributes["nested"] == [true, %{"unicode" => "🌍\n"}]
    assert span.resource_schema_url =~ "1.27.0"
    assert span.scope["name"] == "opentelemetry_phoenix"
    assert span.flags == 257
    assert span.dropped_attributes_count == 4
    assert span.dropped_events_count == 5
    assert span.dropped_links_count == 6
    assert span.resource_dropped_attributes_count == 1
    assert span.scope["dropped_attributes_count"] == 2
    assert [%{"name" => "exception", "dropped_attributes_count" => 2}] = span.events
    assert [%{"flags" => 1, "dropped_attributes_count" => 3}] = span.links
  end

  test "AnyValue empty containers and integral double values normalize consistently" do
    attrs =
      Fixture.pairs(%{
        "array" => %{"arrayValue" => %{}},
        "kv" => %{"kvlistValue" => %{}},
        "empty" => %{},
        "double" => %{"doubleValue" => 1}
      })

    payload = Fixture.payload([Map.put(Fixture.span(), "attributes", attrs)])
    assert {:ok, [span], 0} = decoded = Traces.decode(payload)
    assert span.attributes == %{"array" => [], "kv" => %{}, "empty" => nil, "double" => 1.0}
    assert Traces.decode_protobuf(Fixture.protobuf(payload)) == decoded
    huge = Fixture.pairs(%{"double" => %{"doubleValue" => Integer.pow(10, 400)}})
    assert {:ok, [], 1} = Traces.decode(Fixture.payload([Map.put(Fixture.span(), "attributes", huge)]))
  end

  test "unknown AnyValue fields are ignored rather than rejecting otherwise valid spans" do
    attrs =
      Fixture.pairs(%{
        "bool" => %{"boolValue" => false, "futureField" => [1, 2]},
        "empty" => %{"futureField" => "unknown"}
      })

    payload = Fixture.payload([Map.put(Fixture.span(), "attributes", attrs)])
    assert {:ok, [span], 0} = decoded = Traces.decode(payload)
    assert span.attributes == %{"bool" => false, "empty" => nil}
    assert Traces.decode_protobuf(Fixture.protobuf(payload)) == decoded
  end

  test "defaults, unknown fields, case-normalized IDs and multi-resource order" do
    span = Map.take(Fixture.span(), ["traceId", "spanId", "startTimeUnixNano", "endTimeUnixNano"])
    span = Map.put(span, "traceId", String.upcase(span["traceId"]))
    payload = Fixture.payload([span, Map.put(span, "name", "second")])
    assert {:ok, [first, second], 0} = Traces.decode(payload)
    assert first.trace_id == Fixture.trace_id()
    assert first.parent_span_id == nil
    assert first.status == %{"code" => 0, "message" => ""}
    assert second.name == "second"
    assert Traces.decode_protobuf(Fixture.protobuf(payload) <> Fixture.bytes(99, "future")) == Traces.decode(payload)
    assert {:ok, [], 0} = Traces.decode(%{})
    assert {:ok, [], 0} = Traces.decode_protobuf(<<>>)
  end

  test "rejects bad spans individually and malformed containers as invalid requests" do
    invalid = [
      "bad",
      Map.put(Fixture.span(), "traceId", String.duplicate("0", 32)),
      Map.put(Fixture.span(), "spanId", "bad"),
      Map.put(Fixture.span(), "endTimeUnixNano", "1"),
      Map.put(Fixture.span(), "startTimeUnixNano", "9223372036854775808"),
      Map.put(Fixture.span(), "kind", "SPAN_KIND_SERVER"),
      Map.put(Fixture.span(), "status", nil),
      Map.put(Fixture.span(), "attributes", [%{"key" => "bad", "value" => %{"boolValue" => "true"}}]),
      Map.put(Fixture.span(), "events", [nil]),
      Map.put(Fixture.span(), "links", [%{}])
    ]

    assert {:ok, [_], count} = Traces.decode(Fixture.payload([Fixture.span() | invalid]))
    assert count == length(invalid)

    for body <- [
          [],
          %{"resourceSpans" => nil},
          %{"resourceSpans" => [nil]},
          %{"resourceSpans" => [%{"resource" => nil}]},
          %{"resourceSpans" => [%{"scopeSpans" => [nil]}]}
        ] do
      assert {:error, :invalid_otlp} = Traces.decode(body)
    end

    for bytes <- [<<0>>, <<10, 255>>, <<8, 1>>, <<10, 1, 0>>] do
      assert {:error, :invalid_protobuf} = Traces.decode_protobuf(bytes)
    end
  end

  test "count and attribute budgets include invalid records and duplicate keys before expansion" do
    Pulse.Runtime.put_env(:pulse, Pulse.IngestLimits, max_records: 1)
    assert {:error, :too_many_records} = Traces.decode(Fixture.payload([Fixture.span(), nil]))

    assert {:error, :too_many_records} =
             Traces.decode_protobuf(Fixture.protobuf(Fixture.payload([Fixture.span(), %{}])))

    Pulse.Runtime.put_env(:pulse, Pulse.IngestLimits, max_attributes: 1)
    duplicate = [%{"key" => "x", "value" => %{"intValue" => 1}}, %{"key" => "x", "value" => %{"intValue" => 2}}]

    payload = %{
      "resourceSpans" => [%{"scopeSpans" => [%{"spans" => [Map.put(Fixture.span(), "attributes", duplicate)]}]}]
    }

    assert {:error, :attributes_too_large} = Traces.decode(payload)
    assert {:error, :attributes_too_large} = Traces.decode_protobuf(Fixture.protobuf(payload))
  end

  test "event/link floods and deeply nested values are rejected before record expansion" do
    Pulse.Runtime.put_env(:pulse, Pulse.IngestLimits, max_records: 1)

    for key <- ["events", "links"] do
      raw = Map.put(Fixture.span(), key, [%{}, %{}])
      payload = Fixture.payload([raw])
      assert {:error, :too_many_records} = Traces.decode(payload)
      assert {:error, :too_many_records} = Traces.decode_protobuf(Fixture.protobuf(payload))
    end

    Pulse.Runtime.put_env(:pulse, Pulse.IngestLimits, max_depth: 3)
    nested = Enum.reduce(1..20, %{"stringValue" => "x"}, fn _, v -> %{"arrayValue" => %{"values" => [v]}} end)
    payload = Fixture.payload([Map.put(Fixture.span(), "attributes", Fixture.pairs(%{"nested" => nested}))])
    assert {:error, :attributes_too_large} = Traces.decode(payload)
    assert {:error, :attributes_too_large} = Traces.decode_protobuf(Fixture.protobuf(payload))
  end

  test "nested metadata counts accumulate across spans and resource/scope groups cannot flood" do
    Pulse.Runtime.put_env(:pulse, Pulse.IngestLimits, max_records: 2)

    for key <- ["events", "links"] do
      raw = Map.put(Fixture.span(), key, [%{}, %{}])
      payload = Fixture.payload([raw, raw])
      assert {:error, :too_many_records} = Traces.decode(payload)
      assert {:error, :too_many_records} = Traces.decode_protobuf(Fixture.protobuf(payload))
    end

    payload = %{"resourceSpans" => List.duplicate(%{}, 5)}
    assert {:error, :too_many_records} = Traces.decode(payload)
    assert {:error, :too_many_records} = Traces.decode_protobuf(Fixture.protobuf(payload))
  end

  test "non-finite protobuf doubles retain typed values and agree with JSON" do
    good = Fixture.message(Fixture.span(), :span)

    for {bits, spelling} <- [
          {0x7FF8000000000000, "NaN"},
          {0x7FF0000000000000, "Infinity"},
          {0xFFF0000000000000, "-Infinity"}
        ] do
      pair = Fixture.bytes(1, "nonfinite") <> Fixture.bytes(2, <<33, bits::little-64>>)
      bad = good <> Fixture.bytes(9, pair)
      wire = Fixture.bytes(1, Fixture.bytes(2, Fixture.bytes(2, good) <> Fixture.bytes(2, bad)))

      raw =
        Map.update!(Fixture.span(), "attributes", fn attrs ->
          attrs ++ [%{"key" => "nonfinite", "value" => %{"doubleValue" => spelling}}]
        end)

      json = %{"resourceSpans" => [%{"scopeSpans" => [%{"spans" => [Fixture.span(), raw]}]}]}
      assert {:ok, [_, span], 0} = decoded = Traces.decode_protobuf(wire)
      assert span.attributes["nonfinite"] == spelling
      assert %{"key" => "nonfinite", "value" => %{"doubleValue" => spelling}} in span.otlp["attributes"]
      assert decoded == Traces.decode(json)
    end
  end

  test "request-wide node budget prevents small-attribute term amplification on both encodings" do
    Pulse.Runtime.put_env(:pulse, Pulse.IngestLimits, max_trace_nodes: 65_536)
    attrs = Fixture.pairs(Map.new(1..128, &{"k#{&1}", %{"boolValue" => true}}))

    raw =
      Fixture.span()
      |> Map.take(["traceId", "spanId", "startTimeUnixNano", "endTimeUnixNano"])
      |> Map.put("attributes", attrs)

    payload = Fixture.payload(List.duplicate(raw, 129))
    assert {:error, :too_many_trace_nodes} = Traces.decode(payload)
    assert {:error, :too_many_trace_nodes} = Traces.decode_protobuf(Fixture.protobuf(payload))
  end

  test "default request nodes accommodate a realistic 2048-span SDK burst" do
    payload = Fixture.payload(List.duplicate(Fixture.span(), 2048))
    assert {:ok, json, 0} = Traces.decode(payload)
    assert {:ok, proto, 0} = Traces.decode_protobuf(Fixture.protobuf(payload))
    assert length(json) == 2048
    assert proto == json
  end

  test "duplicate empty singular protobuf messages merge without inventing records" do
    duplicate_resource = Fixture.bytes(1, Fixture.bytes(1, "") <> Fixture.bytes(1, ""))
    assert {:ok, [], 0} = Traces.decode_protobuf(duplicate_resource)
  end

  test "randomized valid inputs keep JSON/protobuf parity and malformed wire cannot crash" do
    :rand.seed(:exsss, {12, 34, 56})

    for i <- 1..100 do
      raw =
        Fixture.span(i * 1000)
        |> Map.put("kind", rem(i, 6))
        |> Map.put("flags", :rand.uniform(0xFFFFFFFF))
        |> Map.put(
          "attributes",
          Fixture.pairs(%{
            "int" => %{"intValue" => Integer.to_string(:rand.uniform(1_000_000) - 500_000)},
            "string" => %{"stringValue" => "#{i} 🌍"},
            "bool" => %{"boolValue" => rem(i, 2) == 0}
          })
        )

      payload = Fixture.payload([raw])
      assert Traces.decode_protobuf(Fixture.protobuf(payload)) == Traces.decode(payload)
    end

    bytes = Fixture.protobuf()

    for i <- 1..100 do
      pos = rem(i * 17, byte_size(bytes))
      <<prefix::binary-size(^pos), _old, suffix::binary>> = bytes
      result = Traces.decode_protobuf(prefix <> <<rem(i * 31, 256)>> <> suffix)
      assert match?({:ok, _, _}, result) or match?({:error, _}, result)
    end
  end
end
