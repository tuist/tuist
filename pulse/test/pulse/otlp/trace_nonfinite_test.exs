defmodule Pulse.OTLP.TraceNonfiniteTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Record.{Span, SpanKey}
  alias Pulse.Storage.S3
  alias Pulse.Storage.SortOrder
  alias Pulse.Test.OTLPTraceFixture, as: Fixture
  alias Pulse.Traces.{Assembly, Tempo, TempoDiscovery}

  @directory Path.expand("../../fixtures/traces", __DIR__)

  defp corpus do
    for {file, hash} <- [
          {"tempo-nonfinite-input.protobuf", "12fa7c9de224f33683faa940b5e565fa0e8ca05c013d7391c272463f6187dd60"},
          {"tempo-nonfinite-oracle.json", "dfe25b842ddfa500c55d61869e0a2b4c5960ffb0cd6b52684627617beb2c6b17"},
          {"produce_tempo_nonfinite.go.txt", "0abf767eb25ea6fbe15f69a93a3b783b902f6a2fb6580ae319a6596db29beb68"}
        ] do
      assert Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(@directory, file))), case: :lower) == hash
    end

    assert {:ok, rows, 0} = Traces.decode_protobuf(File.read!(Path.join(@directory, "tempo-nonfinite-input.protobuf")))
    assert length(rows) == 6
    rows
  end

  defp owners(span),
    do: [
      span.otlp["resource"],
      span.otlp["scope"],
      span.otlp["attributes"],
      hd(span.otlp["events"]),
      hd(span.otlp["links"])
    ]

  defp pairs(owner), do: Map.new(owner, &{&1["key"], &1["value"]})
  defp target("." <> key), do: {"none", key}
  defp target(key), do: key |> String.split(".", parts: 2) |> List.to_tuple()

  test "public protobuf retains nonfinite double classes at all owners and nested values without losing signed zero" do
    rows = corpus()

    for {row, expected} <- Enum.zip(rows, ["NaN", "Infinity", "-Infinity", -0.0, 1.0, "NaN"]), owner <- owners(row) do
      values = pairs(owner)
      assert values["value"] === %{"doubleValue" => expected}

      nested =
        values["nested"]["arrayValue"]["values"] |> hd() |> Map.fetch!("kvlistValue") |> Map.fetch!("values") |> pairs()

      assert nested["value"] === %{"doubleValue" => expected}
      if expected === -0.0, do: assert(<<values["value"]["doubleValue"]::float-64>> == <<0x8000000000000000::64>>)
      assert Map.has_key?(values["literal"], "stringValue")
    end

    assert NIF.trace_metadata_api_version() == 2
    assert NIF.tempo_trace_api_version() == 3
    assert NIF.tempo_discovery_api_version() == 12
  end

  test "JSON and protobuf agree on canonical classes and finite numeric strings; malformed doubles retain rejection semantics" do
    for value <- ["NaN", "Infinity", "-Infinity", "1.25", "-0"] do
      attributes = Fixture.pairs(%{"double" => %{"doubleValue" => value}})
      raw = Map.put(Fixture.span(), "attributes", attributes)
      payload = Fixture.payload([raw])
      assert {:ok, [span], 0} = Traces.decode(payload)
      # Numeric string inputs normalize to finite numeric metadata before protobuf.
      numeric = span.attributes["double"]

      proto_payload =
        Fixture.payload([Map.put(raw, "attributes", Fixture.pairs(%{"double" => %{"doubleValue" => numeric}}))])

      assert Traces.decode_protobuf(Fixture.protobuf(proto_payload)) == Traces.decode(payload)
    end

    for invalid <- ["nan", "+Inf", "NaN.0", "1e10000", true] do
      raw = Map.put(Fixture.span(), "attributes", Fixture.pairs(%{"double" => %{"doubleValue" => invalid}}))
      assert {:ok, [], 1} = Traces.decode(Fixture.payload([raw]))
    end
  end

  test "non-string service names never become promoted string services" do
    # Repeated keys keep their last occurrence, so only a final string promotes.
    for {values, service} <- [
          {[%{"stringValue" => "a"}, %{"stringValue" => "b"}], "b"},
          {[%{"stringValue" => "a"}, %{"doubleValue" => "NaN"}], nil},
          {[%{"doubleValue" => "NaN"}, %{"stringValue" => "b"}], "b"}
        ] do
      attributes = Enum.map(values, &%{"key" => "service.name", "value" => &1})
      payload = put_in(Fixture.payload(), ["resourceSpans", Access.at(0), "resource", "attributes"], attributes)
      assert {:ok, [span], 0} = Traces.decode(payload)
      assert span.service == service
      assert span.otlp["resource"] == [%{"key" => "service.name", "value" => List.last(values)}]
      assert span.resource_dropped_attributes_count == 2
      assert Traces.decode_protobuf(Fixture.protobuf(payload)) == Traces.decode(payload)
    end

    for value <- [
          %{"doubleValue" => "NaN"},
          %{"doubleValue" => "Infinity"},
          %{"doubleValue" => "-Infinity"},
          %{"doubleValue" => 1.5},
          %{"bytesValue" => "TmFO"},
          %{"boolValue" => true}
        ] do
      payload =
        put_in(Fixture.payload(), ["resourceSpans", Access.at(0), "resource", "attributes"], [
          %{"key" => "service.name", "value" => value}
        ])

      assert {:ok, [span], 0} = Traces.decode(payload)
      assert span.service == nil
      assert hd(span.otlp["resource"])["value"] == value
      assert Traces.decode_protobuf(Fixture.protobuf(payload)) == Traces.decode(payload)
      assert {:ok, blob, _, _} = S3.encode_segment(:traces, [span])
      assert {:ok, [decoded]} = S3.decode_segment(:traces, blob, nil, nil, [])
      assert decoded.service == nil

      if Map.has_key?(value, "bytesValue") do
        # Simulate the old projection without claiming a historical artifact capture.
        old = %{span | service: value["bytesValue"]}
        assert {:ok, reference} = Assembly.json(SortOrder.sort([old, span], :traces), span.trace_id)
        assert Pulse.JSON.decode!(reference)["conflicting_span_ids"] == [span.span_id]
        assert {:ok, mixed, _, _} = S3.encode_segment(:traces, [old, span])
        assert {:ok, state} = NIF.trace_query_new_trace(span.trace_id, nil, 10)
        assert {:ok, _} = NIF.trace_query_add(state, mixed)
        assert {:ok, json} = NIF.trace_query_finish_trace(state, 10, span.trace_id)
        assert Pulse.JSON.decode!(json)["conflicting_span_ids"] == [span.span_id]
        assert {:error, _} = NIF.tempo_trace_export(json, "protobuf")
        assert {:error, _} = Tempo.reference(reference, :protobuf)
      end
    end
  end

  test "Parquet compaction, native/reference assembly and both Tempo export envelopes retain types and classes" do
    rows = corpus()
    trace_id = hd(rows).trace_id

    parts =
      for row <- rows do
        assert {:ok, blob, _, _} = S3.encode_segment(:traces, [row])
        blob
      end

    assert {:ok, merged, _, _, 6, _, _} = NIF.compact_trace_segments(parts, 100)
    assert {:ok, decoded} = S3.decode_segment(:traces, merged, nil, nil, [])
    assert Enum.sort_by(decoded, & &1.span_id) === Enum.sort_by(rows, & &1.span_id)
    # Raw compatibility regexes inspect string projections; typed selectors do not.
    assert {:ok, projected} = S3.decode_segment(:traces, merged, nil, nil, attributes_regex: %{"value" => "NaN"})
    assert length(projected) == 2
    assert {:ok, predicates} = TempoDiscovery.filter("span", "literal", ~s({span.value="NaN"}))
    assert {:ok, state} = NIF.tempo_filtered_discovery_new(0, "span", "literal", predicates)
    assert {:ok, _} = NIF.tempo_discovery_add(state, merged)
    assert {:ok, empty} = NIF.tempo_discovery_finish(state)
    assert Pulse.JSON.decode!(empty) == %{"tagValues" => []}
    assert {:ok, empty_ref} = TempoDiscovery.json(rows, "span", "literal", discovery_query: ~s({span.value="NaN"}))
    assert Pulse.JSON.decode!(empty_ref) == %{"tagValues" => []}
    assert {:ok, query} = NIF.trace_query_new_trace(trace_id, nil, 100)
    assert {:ok, _} = NIF.trace_query_add(query, merged)
    assert {:ok, native} = NIF.trace_query_finish_trace(query, 100, trace_id)
    assert {:ok, reference} = Assembly.json(SortOrder.sort(rows, :traces), trace_id)
    assert Pulse.JSON.decode!(native) == Pulse.JSON.decode!(reference)

    for format <- ["json", "json_v2", "protobuf", "protobuf_v2"] do
      assert {:ok, exported} = NIF.tempo_trace_export(native, format)
      assert {:ok, expected} = Tempo.reference(reference, format)

      if String.starts_with?(format, "json"),
        do: assert(Pulse.JSON.decode!(exported) == Pulse.JSON.decode!(expected)),
        else: assert(exported == expected)
    end

    first = hd(rows)
    # Identical query projections do not erase original string/double identity.
    other =
      put_in(
        first.otlp["attributes"],
        Enum.map(first.otlp["attributes"], fn pair ->
          if pair["key"] == "value", do: %{pair | "value" => %{"stringValue" => "NaN"}}, else: pair
        end)
      )

    assert first.attributes == other.attributes
    refute SpanKey.encode(Span.to_map(first)) == SpanKey.encode(Span.to_map(other))
    assert {:ok, conflicts} = Assembly.json([first, other], trace_id)
    assert Pulse.JSON.decode!(conflicts)["conflicting_span_ids"] == [first.span_id]

    for bad <- ["NaN.0", "+Inf", "not-a-number"] do
      invalid = put_in(first.otlp["attributes"], [%{"key" => "value", "value" => %{"doubleValue" => bad}}])
      assert :fallback = NIF.encode_trace_segment_parquet([Span.to_map(invalid)])
    end
  end

  test "actual public Tempo engine dictionaries agree across five owners, unscoped values and string contrasts" do
    rows = corpus()
    oracle = File.read!(Path.join(@directory, "tempo-nonfinite-oracle.json")) |> Pulse.JSON.decode!()
    assert length(oracle["cases"]) == 14
    assert {:ok, forward, _, _} = S3.encode_segment(:traces, rows)
    assert {:ok, reverse, _, _} = S3.encode_segment(:traces, Enum.reverse(rows))

    for c <- oracle["cases"] do
      {scope, key} = target(c["target"])
      assert {:ok, predicates} = TempoDiscovery.filter(scope, key, c["query"])

      for sources <- [[forward], [reverse], [forward, reverse]] do
        result =
          if predicates == [],
            do: NIF.tempo_discovery_new(0, scope, key),
            else: NIF.tempo_filtered_discovery_new(0, scope, key, predicates)

        assert {:ok, state} = result
        for blob <- sources, do: assert({:ok, _} = NIF.tempo_discovery_add(state, blob))
        assert {:ok, json} = NIF.tempo_discovery_finish(state)
        assert Pulse.JSON.decode!(json) == c["response"]
      end

      assert {:ok, reference} = TempoDiscovery.json(rows, scope, key, discovery_query: c["query"])
      assert Pulse.JSON.decode!(reference) == c["response"]
    end
  end
end
