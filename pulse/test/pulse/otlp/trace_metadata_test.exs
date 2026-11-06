defmodule Pulse.OTLP.TraceMetadataTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Record.{Span, SpanKey}
  alias Pulse.Storage.S3
  alias Pulse.Storage.SortOrder
  alias Pulse.Test.OTLPTraceFixture, as: Fixture
  alias Pulse.Traces.Assembly

  defp official do
    wire = File.read!(Path.expand("../../fixtures/otlp/protoc-trace-values.protobuf", __DIR__))

    assert Base.encode16(:crypto.hash(:sha256, wire), case: :lower) ==
             "345cbbcb764b0e9959735462671d4ed65265b726ed7d75bb98461d637db95234"

    assert {:ok, [span], 0} = Traces.decode_protobuf(wire)
    span
  end

  defp values(pairs), do: Map.new(pairs, &{&1["key"], &1["value"]})

  test "independent official protobuf preserves type and order at every attribute owner" do
    span = official()
    assert span.trace_id == "30313233343536373839616263646566"
    assert span.span_id == "6465616462656566"
    assert span.otlp["version"] == 1

    owners = [
      span.otlp["resource"],
      span.otlp["scope"],
      span.otlp["attributes"],
      hd(span.otlp["events"]),
      hd(span.otlp["links"])
    ]

    for owner <- owners do
      assert values(owner)["blob"] == %{"bytesValue" => "AP8="}
      assert values(owner)["text"] == %{"stringValue" => "AP8="}
    end

    attributes = values(span.otlp["attributes"])
    assert attributes["integer"] == %{"intValue" => "1"}
    assert attributes["double"] === %{"doubleValue" => 1.0}
    assert attributes["minimum"] == %{"intValue" => "-9223372036854775808"}
    assert attributes["maximum"] == %{"intValue" => "9223372036854775807"}
    assert attributes["empty"] == %{}
    assert <<128, 0, 0, 0, 0, 0, 0, 0>> == <<attributes["negative_zero"]["doubleValue"]::float-64>>

    assert [%{"boolValue" => false}, %{"kvlistValue" => %{"values" => nested}}] =
             attributes["nested"]["arrayValue"]["values"]

    assert values(nested) == %{"blob" => %{"bytesValue" => "AP8="}, "text" => %{"stringValue" => "AP8="}}

    assert Enum.map(span.otlp["attributes"], & &1["key"]) ==
             ~w(blob text integer double negative_zero minimum maximum empty nested)
  end

  test "native Parquet, mixed legacy compaction, projection and complete assembly retain the envelope" do
    span = official()
    legacy = %{span | otlp: nil}
    refute Map.has_key?(Span.to_map(legacy), "otlp")
    assert Span.from_map(Span.to_map(legacy)) === legacy
    assert SpanKey.size(legacy) == byte_size(SpanKey.encode(Span.to_map(legacy)))
    assert SpanKey.size(span) == byte_size(SpanKey.encode(Span.to_map(span)))
    assert {:ok, rich, _, _} = S3.encode_segment(:traces, [span])
    assert {:ok, old, _, _} = S3.encode_segment(:traces, [legacy])
    assert {:ok, [decoded]} = S3.decode_segment(:traces, rich, nil, nil, [])
    assert :erlang.term_to_binary(decoded.otlp) == :erlang.term_to_binary(span.otlp)
    assert {:ok, merged, _, _, 2, _, _} = NIF.compact_trace_segments([old, rich], 100)
    assert {:ok, records} = S3.decode_segment(:traces, merged, nil, nil, [])
    assert Enum.count(records, &is_nil(&1.otlp)) == 1
    assert Enum.find(records, & &1.otlp).otlp === span.otlp
    # Legacy and rich copies of one span need complete keys to order.
    assert {:ok, query} = NIF.trace_query_new(nil, nil, %{"limit" => 2}, ["otlp"], 100)
    assert {:error, :trace_projection_tie} = NIF.trace_query_add(query, merged)
    assert {:ok, query} = NIF.trace_query_new(nil, nil, %{"limit" => 2, "full_sort_keys" => true}, ["otlp"], 100)
    assert {:ok, _} = NIF.trace_query_add(query, merged)
    assert {:ok, json} = NIF.trace_query_finish(query, 100)
    assert Enum.find(Pulse.JSON.decode!(json), &Map.has_key?(&1, "otlp"))["otlp"] === span.otlp
    assert {:ok, query} = NIF.trace_query_new_trace(span.trace_id, nil, 100)
    assert {:ok, _} = NIF.trace_query_add(query, merged)
    assert {:ok, json} = NIF.trace_query_finish_trace(query, 100, span.trace_id)
    assembled = Pulse.JSON.decode!(json)
    assert assembled["span_count"] == 2
    assert assembled["conflicting_span_ids"] == []
    assert assembled["metadata_unknown_span_ids"] == [span.span_id]
  end

  test "independent legacy Arrow stays readable and malformed rich Arrow fails closed on reads and compaction" do
    read = fn name -> File.read!(Path.expand("../../fixtures/traces/trace-#{name}.parquet", __DIR__)) end
    old = read.("legacy")
    assert {:ok, [legacy]} = S3.decode_segment(:traces, old, nil, nil, [])
    assert legacy.otlp == nil
    assert legacy.attributes == %{"blob" => "AP8="}

    for name <- ~w(invalid-type invalid-version invalid-value) do
      blob = read.(name)
      assert {:error, {:decode_failed, _}} = S3.decode_segment(:traces, blob, nil, nil, [])
      assert :fallback = NIF.compact_trace_segments([old, blob], 100)
      assert {:ok, query} = NIF.trace_query_new(nil, nil, %{"limit" => 1}, nil, 100)
      assert :fallback = NIF.trace_query_add(query, blob)
      assert :fallback = NIF.trace_query_finish(query, 100)
    end
  end

  test "typed metadata participates in keyed identity; nil leaves legacy maps unchanged" do
    span = official()

    other =
      put_in(
        span.otlp["attributes"],
        Enum.map(span.otlp["attributes"], fn pair ->
          if pair["key"] == "blob", do: %{pair | "value" => %{"stringValue" => "AP8="}}, else: pair
        end)
      )

    assert span.attributes == other.attributes
    refute S3.caller_content_hash(:traces, [span]) == S3.caller_content_hash(:traces, [other])
    assert {:ok, reference} = Assembly.json(SortOrder.sort([span, other], :traces), span.trace_id)
    assert Pulse.JSON.decode!(reference)["conflicting_span_ids"] == [span.span_id]
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, [span, other])
    assert {:ok, query} = NIF.trace_query_new_trace(span.trace_id, nil, 100)
    assert {:ok, _} = NIF.trace_query_add(query, blob)
    assert {:ok, native} = NIF.trace_query_finish_trace(query, 100, span.trace_id)
    assert Pulse.JSON.decode!(native) == Pulse.JSON.decode!(reference)
    assert SpanKey.encode(Span.to_map(span)) != SpanKey.encode(Span.to_map(other))
  end

  test "counter proves the escaped full payload budget and closes malformed envelope shapes" do
    span = official()
    map = Span.to_map(span)
    expected = byte_size(Pulse.JSON.encode!(map))
    assert {:ok, ^expected} = NIF.trace_payload_size([map], expected)
    assert {:error, :payload_too_large} = NIF.trace_payload_size([map], expected - 1)

    for invalid <- [[], "bad", %{}, Map.put(span.otlp, "version", 2), Map.put(span.otlp, "events", [])] do
      assert :fallback = NIF.encode_trace_segment_parquet([Map.put(map, "otlp", invalid)])
    end
  end

  test "rich sort keys fail full results whole, while narrow projections budget only what they return" do
    raw = Fixture.span() |> Map.put("events", []) |> Map.put("links", [])
    attrs = Map.new(1..25, &{"attr.#{&1}", %{"stringValue" => "v#{&1}"}})
    raw = Map.put(raw, "attributes", Fixture.pairs(attrs))
    id = fn i -> i |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(16, "0") end

    spans =
      for chunk <- Enum.chunk_every(1..5000, 500) do
        assert {:ok, spans, 0} = Traces.decode(Fixture.payload(for i <- chunk, do: Map.put(raw, "spanId", id.(i))))
        spans
      end
      |> List.flatten()

    assert SpanKey.size(hd(spans)) * 5000 > 16_777_216
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, spans)

    for mode <- [nil, %{"full_sort_keys" => true}] do
      filters = Map.merge(%{"limit" => 5000}, mode || %{})
      fields = if mode, do: ["span_id"]
      assert {:ok, query} = NIF.trace_query_new(nil, nil, filters, fields, 10_000)
      assert {:error, :query_resource_limit} = NIF.trace_query_add(query, blob)
    end

    assert {:ok, query} = NIF.trace_query_new(nil, nil, %{"limit" => 5000}, ["span_id"], 10_000)
    assert {:ok, {5000, _, 5000}} = NIF.trace_query_add(query, blob)
    assert {:ok, json} = NIF.trace_query_finish(query, 10_000)
    expected = spans |> SortOrder.sort(:traces) |> Enum.map(&%{"span_id" => &1.span_id})
    assert Pulse.JSON.decode!(json) == expected
  end

  test "projected candidates rerun with complete keys only for different copies of one span" do
    raw = Fixture.span() |> Map.put("events", []) |> Map.put("links", [])
    assert {:ok, [span, copy], 0} = Traces.decode(Fixture.payload([raw, Map.put(raw, "name", "other")]))
    ordered = SortOrder.sort([span, copy], :traces)

    # Identical copies share a digest and need no complete key.
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, [span, span])
    assert {:ok, query} = NIF.trace_query_new(nil, nil, %{"limit" => 2}, ["name"], 10)
    assert {:ok, _} = NIF.trace_query_add(query, blob)
    assert {:ok, json} = NIF.trace_query_finish(query, 10)
    assert Pulse.JSON.decode!(json) == [%{"name" => span.name}, %{"name" => span.name}]

    # A different copy in a later segment still conflicts with the retained one.
    assert {:ok, first, _, _} = S3.encode_segment(:traces, [span])
    assert {:ok, second, _, _} = S3.encode_segment(:traces, [copy])
    assert {:ok, query} = NIF.trace_query_new(nil, nil, %{"limit" => 1}, ["name"], 10)
    assert {:ok, _} = NIF.trace_query_add(query, first)
    assert {:error, :trace_projection_tie} = NIF.trace_query_add(query, second)

    filters = %{"limit" => 1, "full_sort_keys" => true}
    assert {:ok, query} = NIF.trace_query_new(nil, nil, filters, ["name", "duration_ns"], 10)
    assert {:ok, _} = NIF.trace_query_add(query, first)
    assert {:ok, _} = NIF.trace_query_add(query, second)
    assert {:ok, json} = NIF.trace_query_finish(query, 10)
    [winner | _] = ordered

    assert Pulse.JSON.decode!(json) == [
             %{"name" => winner.name, "duration_ns" => winner.end_timestamp_ns - winner.timestamp_ns}
           ]
  end

  test "repeated owner metadata exceeding normalized ceiling rejects before append" do
    payload = Fixture.payload(List.duplicate(Fixture.span(), 1000))

    payload =
      put_in(payload, ["resourceSpans", Access.at(0), "resource", "attributes"], [
        %{"key" => "large", "value" => %{"stringValue" => String.duplicate("x", 16_384)}}
      ])

    assert {:error, :payload_too_large} = Traces.decode(payload)
  end
end
