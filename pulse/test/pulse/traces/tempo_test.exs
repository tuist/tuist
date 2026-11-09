defmodule Pulse.Traces.TempoTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.JSON
  alias Pulse.OTLP.Traces
  alias Pulse.Record.SpanKey
  alias Pulse.Test.OTLPTraceFixture, as: Fixture
  alias Pulse.Traces.{Assembly, Tempo}
  alias Pulse.Traces.TempoFilter

  defp official do
    wire = File.read!(Path.expand("../../fixtures/otlp/protoc-trace-values.protobuf", __DIR__))
    assert {:ok, [span], 0} = Traces.decode_protobuf(wire)
    {wire, span}
  end

  test "native Tempo protobuf matches independent stored-status wire, preserving all official AnyValue types" do
    {_original_wire, span} = official()
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-v1-stored-trace.protobuf", __DIR__))
    assert {:ok, assembly} = Assembly.json([span], span.trace_id)
    assert {:ok, body} = NIF.tempo_trace_export(assembly, "protobuf")
    assert body == wire
    assert Tempo.reference(assembly, "protobuf") == {:ok, wire}
    assert {:ok, json} = NIF.tempo_trace_export(assembly, "json")
    assert {:ok, ref} = Tempo.reference(assembly, "json")
    assert Pulse.JSON.decode!(json) == Pulse.JSON.decode!(ref)
    fixture = File.read!(Path.expand("../../fixtures/traces/tempo-v1-stored-trace.json", __DIR__))

    assert Base.encode16(:crypto.hash(:sha256, fixture), case: :lower) ==
             "b69f16d31c06e7f2378272f4affd91b5e27533eb8e9089ab26ac92f8cd95213c"

    assert JSON.decode!(fixture) == JSON.decode!(json)
    map = Pulse.JSON.decode!(json)
    stored = hd(hd(hd(map["batches"])["scopeSpans"])["spans"])
    assert stored["status"] == %{}
    assert stored["traceId"] == Base.encode64("0123456789abcdef")
    assert stored["spanId"] == Base.encode64("deadbeef")
    values = Map.new(stored["attributes"], &{&1["key"], &1["value"]})
    assert values["blob"] == %{"bytesValue" => "AP8="}
    assert values["text"] == %{"stringValue" => "AP8="}
    assert values["minimum"] == %{"intValue" => "-9223372036854775808"}
    assert :erlang.term_to_binary(values["negative_zero"]["doubleValue"]) == :erlang.term_to_binary(-0.0)
  end

  test "actual Grafana lookup frame golden preserves unset status and records client byte projection loss" do
    fixture = File.read!(Path.expand("../../fixtures/traces/lookup-frame.json", __DIR__))

    assert Base.encode16(:crypto.hash(:sha256, fixture), case: :lower) ==
             "714d7bd629d93aaa5c303ddabf946a5dff108af4afa2f87cf61b322b83309523"

    frame = Pulse.JSON.decode!(fixture)

    columns =
      Map.new(Enum.zip(frame["schema"]["fields"], frame["data"]["values"]), fn {field, values} ->
        {field["name"], values}
      end)

    assert frame["schema"]["meta"]["preferredVisualisationType"] == "trace"
    assert columns["traceID"] == [Base.encode16("0123456789abcdef", case: :lower)]
    assert columns["spanID"] == [Base.encode16("deadbeef", case: :lower)]
    assert columns["statusCode"] == [0]
    assert columns["statusMessage"] == [""]
    tags = Map.new(hd(columns["tags"]), &{&1["key"], &1["value"]})
    assert tags["blob"] == ""
    assert tags["text"] == "AP8="
    assert tags["minimum"] == -9_223_372_036_854_775_808
    assert tags["maximum"] == 9_223_372_036_854_775_807

    oracle =
      File.read!(Path.expand("../../fixtures/traces/default-status-oracle.json", __DIR__)) |> Pulse.JSON.decode!()

    assert oracle == %{
             "input_status_present" => false,
             "stored_output_status_present" => true,
             "stored_output_status_code" => 0,
             "stored_scope_present" => true,
             "stored_resource_present" => true
           }
  end

  test "mixed default, OK and message-only statuses retain message presence in both wire versions" do
    {_wire, base} = official()

    statuses = [
      %{"code" => 0, "message" => ""},
      %{"code" => 1, "message" => ""},
      %{"code" => 0, "message" => "explanation"}
    ]

    rows =
      statuses
      |> Enum.with_index(1)
      |> Enum.map(fn {status, id} ->
        %{base | status: status, span_id: String.pad_leading(Integer.to_string(id), 16, "0")}
      end)

    assert {:ok, assembly} = Assembly.json(rows, base.trace_id)

    for format <- ["protobuf", "protobuf_v2", "json", "json_v2"] do
      assert {:ok, native} = NIF.tempo_trace_export(assembly, format)
      assert {:ok, reference} = Tempo.reference(assembly, format)

      if String.starts_with?(format, "protobuf") do
        assert native == reference
        assert :binary.match(native, <<0x7A, 0>>) != :nomatch
        assert :binary.match(native, <<0x7A, 2, 0x18, 1>>) != :nomatch
      else
        result = Pulse.JSON.decode!(native)
        assert result == Pulse.JSON.decode!(reference)
        groups = if format == "json", do: result["batches"], else: result["trace"]["resourceSpans"]
        values = for group <- groups, scope <- group["scopeSpans"], span <- scope["spans"], do: span["status"]
        assert values == [%{}, %{"code" => "STATUS_CODE_OK"}, %{"message" => "explanation"}]
      end
    end
  end

  test "native/ref assembly bounds agree and malformed envelopes never export a partial result" do
    {_wire, span} = official()
    assert {:ok, assembly} = Assembly.json([span], span.trace_id)
    data = Pulse.JSON.decode!(assembly)
    excessive = data |> Map.put("spans", List.duplicate(hd(data["spans"]), 5001)) |> Pulse.JSON.encode!()
    assert byte_size(excessive) < 16_777_216
    assert {:error, :query_resource_limit} = NIF.tempo_trace_export(excessive, "protobuf_v2")
    assert {:error, :query_resource_limit} = Tempo.reference(excessive, "protobuf_v2")
    assert {:ok, filter} = TempoFilter.parse(%{"q" => ~s({ span.missing = "no match" })})
    assert {:error, :query_resource_limit} = Tempo.reference(excessive, "protobuf_v2", filter)

    for invalid <- [
          "not json",
          "[]",
          data |> Map.put("coverage", "window_stored_spans") |> Pulse.JSON.encode!(),
          data |> Map.put("trace_id", String.duplicate("f", 32)) |> Pulse.JSON.encode!()
        ] do
      assert {:error, :invalid_trace_export} = Tempo.export(invalid, "json")
    end
  end

  test "filtering cannot hide invalid export fields on a nonmatching span or its owners" do
    assert {:ok, [span], 0} = Traces.decode(Fixture.payload())
    assert {:ok, assembly} = Assembly.json([span], span.trace_id)
    data = Pulse.JSON.decode!(assembly)

    nonmatch =
      hd(data["spans"])
      |> Map.put("span_id", "0000000000000002")
      |> Map.put("attributes", %{})
      |> put_in(["otlp", "attributes"], [])

    filters =
      for value <- ["api", "absent"] do
        assert {:ok, filter} = TempoFilter.parse(%{"q" => ~s({ span.request_kind = "#{value}" })})
        filter
      end

    boundary =
      nonmatch
      |> put_in(["events", Access.at(0), "timestamp_ns"], 9_223_372_036_854_775_807)
      |> put_in(["links", Access.at(0), "flags"], 4_294_967_295)
      |> Map.put("resource_dropped_attributes_count", 4_294_967_295)

    valid = data |> Map.update!("spans", &(&1 ++ [boundary])) |> Pulse.JSON.encode!()

    for format <- ["json_v2", "protobuf_v2"], filter <- [nil | filters] do
      assert {:ok, _body} = Tempo.export(valid, format, filter)
    end

    for {path, value} <- [
          {["parent_span_id"], "00"},
          {["trace_state"], 1},
          {["flags"], 4_294_967_296},
          {["status", "message"], 1},
          {["resource_dropped_attributes_count"], -1},
          {["resource_schema_url"], 1},
          {["scope", "name"], 1},
          {["scope", "dropped_attributes_count"], 4_294_967_296},
          {["scope_schema_url"], 1},
          {["events", Access.at(0), "timestamp_ns"], -1},
          {["events", Access.at(0), "timestamp_ns"], 9_223_372_036_854_775_808},
          {["events", Access.at(0), "name"], 1},
          {["events", Access.at(0), "dropped_attributes_count"], 4_294_967_296},
          {["links", Access.at(0), "trace_id"], "not-a-trace-id"},
          {["links", Access.at(0), "trace_id"], "abcd"},
          {["links", Access.at(0), "trace_id"], String.duplicate("0", 32)},
          {["links", Access.at(0), "span_id"], "abcd"},
          {["links", Access.at(0), "span_id"], String.duplicate("0", 16)},
          {["links", Access.at(0), "trace_state"], 1},
          {["links", Access.at(0), "flags"], 4_294_967_296},
          {["links", Access.at(0), "dropped_attributes_count"], -1}
        ] do
      invalid = data |> Map.update!("spans", &(&1 ++ [put_in(nonmatch, path, value)])) |> Pulse.JSON.encode!()

      for format <- ["json_v2", "protobuf_v2"] do
        assert {:error, :invalid_trace_export} = Tempo.export(invalid, format)
        assert {:error, :invalid_trace_export} = Tempo.reference(invalid, format)

        for filter <- filters do
          assert {:error, :invalid_trace_export} = Tempo.export(invalid, format, filter)
          assert {:error, :invalid_trace_export} = Tempo.reference(invalid, format, filter)
        end
      end
    end
  end

  test "Tempo v2 envelopes match independent gogo/jsonpb output, with stored-query COMPLETE default status" do
    {_wire, span} = official()
    assert {:ok, assembly} = Assembly.json([span], span.trace_id)

    for {format, extension, hash} <- [
          {"protobuf_v2", "protobuf", "d7430bdbe6471534d9777aa82f830a49307bf50b45874b2dc29ac1fd8767a0f7"},
          {"json_v2", "json", "bff9ef17c175328d3539f3b5f23659d14c0559bca9b9f22d52f1169c137fe9e0"}
        ] do
      expected = File.read!(Path.expand("../../fixtures/traces/tempo-v2-stored-trace." <> extension, __DIR__))
      assert Base.encode16(:crypto.hash(:sha256, expected), case: :lower) == hash
      assert {:ok, native} = NIF.tempo_trace_export(assembly, format)
      assert {:ok, reference} = Tempo.reference(assembly, format)

      if extension == "protobuf" do
        assert native == expected and reference == expected
      else
        assert JSON.decode!(native) == JSON.decode!(expected)
        assert JSON.decode!(reference) == JSON.decode!(expected)
      end
    end
  end

  test "duplicate identical IDs are deduplicated; disagreement or unknown metadata never rewrites IDs" do
    {_wire, span} = official()
    assert {:ok, assembly} = Assembly.json([span, span], span.trace_id)
    assert {:ok, single} = Assembly.json([span], span.trace_id)

    for format <- ["json", "protobuf"] do
      assert Tempo.export(assembly, format) == Tempo.export(single, format)
    end

    assert {:ok, assembly} = Assembly.json([span, %{span | name: "changed"}], span.trace_id)
    assert {:error, :trace_span_id_conflict} = NIF.tempo_trace_export(assembly, "json")
    assert {:error, :trace_span_id_conflict} = Tempo.reference(assembly, "json")
    assert {:ok, assembly} = Assembly.json([%{span | otlp: nil}], span.trace_id)
    assert {:error, :trace_metadata_unknown} = NIF.tempo_trace_export(assembly, "protobuf")
    assert {:error, :trace_metadata_unknown} = Tempo.reference(assembly, "protobuf")
    assert {:ok, empty} = Assembly.json([], span.trace_id)
    assert {:error, :not_found} = Tempo.export(empty, "json")
  end

  for format <- ["protobuf", "protobuf_v2"] do
    @tag timeout: 60_000
    test "5,000 spans with 40 attributes share one owner without exhausting aggregate protobuf message plans / #{format}" do
      format = unquote(format)

      attrs =
        Enum.map(Enum.take(Enum.to_list(?a..?z) ++ Enum.to_list(?A..?Z), 40), fn key ->
          %{"key" => <<key>>, "value" => %{"boolValue" => false}}
        end)

      payload = %{
        "resourceSpans" => [
          %{
            "scopeSpans" => [
              %{
                "spans" => [
                  %{
                    "traceId" => String.duplicate("1", 32),
                    "spanId" => String.duplicate("2", 16),
                    "startTimeUnixNano" => "1",
                    "endTimeUnixNano" => "2",
                    "attributes" => attrs
                  }
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, [base], 0} = Traces.decode(payload)
      assert SpanKey.size(base) * 5000 < 16_777_216
      spans = for id <- 1..5000, do: %{base | span_id: id |> Integer.to_string(16) |> String.pad_leading(16, "0")}
      assert {:ok, assembly} = Assembly.json(spans, base.trace_id)
      assert {:ok, filter} = TempoFilter.parse(%{"q" => "{}"})

      assert {:ok, native} = NIF.tempo_trace_export(assembly, format)
      assert {:ok, native} == Tempo.reference(assembly, format)
      assert {:ok, native} == Tempo.reference(assembly, format, filter)
    end
  end

  @tag timeout: 60_000
  test "5,000 rich filtered spans preserve native protobuf within the default query heap" do
    assert {:ok, [base], 0} = Traces.decode(Fixture.payload())

    spans =
      for id <- 1..5000 do
        value = Integer.to_string(rem(id, 100))
        pair = %{"key" => "bucket", "value" => %{"intValue" => value}}

        %{
          base
          | span_id: id |> Integer.to_string(16) |> String.pad_leading(16, "0"),
            attributes: Map.put(base.attributes, "bucket", value),
            otlp: Map.update!(base.otlp, "attributes", &(&1 ++ [pair]))
        }
      end

    assert {:ok, assembly} = Assembly.json(spans, base.trace_id)
    assert {:ok, expected} = NIF.tempo_trace_export(assembly, "protobuf_v2")
    assert {:ok, filter} = TempoFilter.parse(%{"q" => "{ span.bucket >= 0 }"})
    parent = self()

    pid =
      start_supervised!(
        {Task,
         fn ->
           Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: false})
           send(parent, {:export_ready, self()})

           receive do
             :export ->
               send(parent, {:bounded_export, Tempo.export(assembly, "protobuf_v2", filter)})
           end
         end}
      )

    ref = Process.monitor(pid)
    assert_receive {:export_ready, ^pid}
    send(pid, :export)
    assert_receive {:DOWN, ^ref, :process, ^pid, reason}, 30_000
    assert reason == :normal
    assert_receive {:bounded_export, {:ok, ^expected}}
  end

  test "owner grouping shares resource/scope bytes but preserves typed and signed-zero identity" do
    assert {:ok, [base], 0} = Traces.decode(Fixture.payload())
    a = %{base | span_id: "0000000000000001"}
    b = %{base | span_id: "0000000000000002", timestamp_ns: base.timestamp_ns + 1}
    assert {:ok, assembly} = Assembly.json([a, b], base.trace_id)
    assert {:ok, json} = NIF.tempo_trace_export(assembly, "json")
    assert [owner] = Pulse.JSON.decode!(json)["batches"]
    assert length(hd(owner["scopeSpans"])["spans"]) == 2
    assert {:ok, wire} = NIF.tempo_trace_export(assembly, "protobuf")
    assert {:ok, wire} == Tempo.reference(assembly, "protobuf")

    plus = %{
      a
      | otlp: Map.update!(a.otlp, "resource", &(&1 ++ [%{"key" => "zero", "value" => %{"doubleValue" => 0.0}}]))
    }

    minus = %{
      b
      | otlp: Map.update!(b.otlp, "resource", &(&1 ++ [%{"key" => "zero", "value" => %{"doubleValue" => -0.0}}]))
    }

    assert {:ok, assembly} = Assembly.json([plus, minus], base.trace_id)
    assert {:ok, json} = NIF.tempo_trace_export(assembly, "json")
    assert length(Pulse.JSON.decode!(json)["batches"]) == 2
    assert {:ok, ref} = Tempo.reference(assembly, "json")
    assert Pulse.JSON.decode!(ref) == Pulse.JSON.decode!(json)
  end

  test "native/reference enum, source times, flags, owner schemas, events and links preserve protobuf" do
    assert {:ok, [span], 0} = Traces.decode(Fixture.payload())
    assert {:ok, assembly} = Assembly.json([span], span.trace_id)

    for format <- ["json", "protobuf"] do
      assert {:ok, body} = NIF.tempo_trace_export(assembly, format)
      assert {:ok, ref} = Tempo.reference(assembly, format)
      assert body == ref or (format == "json" and Pulse.JSON.decode!(body) == Pulse.JSON.decode!(ref))
    end

    assert {:ok, wire} = Tempo.export(assembly, "protobuf")
    assert {:ok, [roundtrip], 0} = Traces.decode_protobuf(wire)
    assert roundtrip == span
  end
end
