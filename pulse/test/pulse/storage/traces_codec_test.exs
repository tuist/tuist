defmodule Pulse.Storage.TracesCodecTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Record.Span
  alias Pulse.Record.SpanKey
  alias Pulse.Storage.S3
  alias Pulse.Storage.SortOrder
  alias Pulse.Test.OTLPTraceFixture, as: Fixture
  alias Pulse.Traces.Assembly

  defp spans do
    {:ok, spans, 0} = Traces.decode(Fixture.payload([Fixture.span(10), Fixture.span(20)]))
    spans
  end

  test "native complete-trace assembly matches reference reconciliation across objects" do
    [base | _] = spans()
    root = %{base | span_id: String.duplicate("a", 16), parent_span_id: nil}
    child = %{base | span_id: String.duplicate("b", 16), parent_span_id: String.duplicate("c", 16)}
    records = [root, root, %{root | attributes: %{"typed" => 1.0, "zero" => -0.0}}, child]
    assert {:ok, state} = NIF.trace_query_new(nil, nil, %{"limit" => 5001, "trace_id" => base.trace_id}, nil, 10_000)

    for batch <- Enum.chunk_every(records, 2) do
      assert {:ok, blob, _, _} = S3.encode_segment(:traces, batch)
      assert {:ok, {_, nil, 2}} = NIF.trace_query_add(state, blob)
    end

    assert {:ok, json} = NIF.trace_query_finish_trace(state, 5000, base.trace_id)
    assert {:ok, reference} = Assembly.json(SortOrder.sort(records, :traces), base.trace_id)
    assert Pulse.JSON.decode!(json) == Pulse.JSON.decode!(reference)
    assert :fallback = NIF.trace_query_finish_trace(state, 5000, base.trace_id)
  end

  test "dedicated assembly applies only its retention floor and reports it" do
    [base | _] = spans()
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, spans())
    assert {:ok, state} = NIF.trace_query_new_trace(base.trace_id, 20, 1000)
    assert {:ok, _} = NIF.trace_query_add(state, blob)
    assert {:ok, json} = NIF.trace_query_finish_trace(state, 5000, base.trace_id)
    assembled = Pulse.JSON.decode!(json)
    assert assembled["retention_floor_ns"] == 20
    assert assembled["coverage"] == "all_stored_spans_at_or_above_floor"
    assert assembled["span_count"] == 1

    for floor <- [-1, 9_223_372_036_854_775_808, 20.1, "20"],
        do: assert(:fallback = NIF.trace_query_new_trace(base.trace_id, floor, 1000))
  end

  test "native assembly cannot silently truncate oversized or mixed-ID traces" do
    [base | _] = spans()
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, List.duplicate(base, 5001))
    assert {:ok, state} = NIF.trace_query_new(nil, nil, %{"limit" => 5001, "trace_id" => base.trace_id}, nil, 10_000)
    assert {:ok, _} = NIF.trace_query_add(state, blob)
    assert {:error, :query_sample_limit} = NIF.trace_query_finish_trace(state, 5000, base.trace_id)
    assert :fallback = NIF.trace_query_finish_trace(state, 5000, base.trace_id)
    assert {:ok, small, _, _} = S3.encode_segment(:traces, [base])
    assert {:ok, state} = NIF.trace_query_new(nil, nil, %{"limit" => 5001}, nil, 10_000)
    assert {:ok, _} = NIF.trace_query_add(state, small)
    assert :fallback = NIF.trace_query_finish_trace(state, 5000, String.duplicate("d", 32))

    for {start, finish, filters, fields} <- [
          {nil, nil, %{"trace_id" => base.trace_id, "limit" => 1}, nil},
          {1, nil, %{"trace_id" => base.trace_id, "limit" => 5001}, nil},
          {nil, 100, %{"trace_id" => base.trace_id, "limit" => 5001}, nil},
          {nil, nil, %{"trace_id" => base.trace_id, "limit" => 5001, "service" => base.service}, nil},
          {nil, nil, %{"trace_id" => base.trace_id, "limit" => 5001}, ["span_id"]}
        ] do
      assert {:ok, state} = NIF.trace_query_new(start, finish, filters, fields, 10_000)
      assert {:ok, _} = NIF.trace_query_add(state, small)
      assert :fallback = NIF.trace_query_finish_trace(state, 5000, base.trace_id)
    end
  end

  test "Parquet retains every trace field and bounds use start times" do
    assert {:ok, blob, 10, 20} = S3.encode_segment(:traces, spans())
    assert <<"PAR1", _::binary>> = blob
    assert {:ok, decoded} = S3.decode_segment(:traces, blob, nil, nil, [])
    assert SortOrder.sort(decoded, :traces) == SortOrder.sort(spans(), :traces)
    assert {:ok, second, 10, 20} = S3.encode_segment(:traces, decoded)
    assert {:ok, ^decoded} = S3.decode_segment(:traces, second, nil, nil, [])
    assert {:ok, []} = S3.decode_segment(:traces, blob, 21, 100, [])

    assert {:ok, [%Span{timestamp_ns: 20}]} =
             S3.decode_segment(:traces, blob, 20, 20,
               service: "tuist-server",
               trace_id: Fixture.trace_id(),
               status_code: 2,
               attributes: %{"metrics.skip" => false},
               resource: %{"deployment.environment" => "production"}
             )

    for opts <- [
          [trace_id: String.duplicate("a", 32)],
          [span_id: String.duplicate("b", 16)],
          [service: "other"],
          [name: "other"],
          [kind: 3],
          [status_code: 1],
          [attributes: %{"metrics.skip" => true}],
          [attributes: %{"http.response.status_code" => 500.0}],
          [attributes: %{"missing" => nil}],
          [resource: %{"service.name" => "other"}]
        ] do
      assert {:ok, []} = S3.decode_segment(:traces, blob, nil, nil, opts)
    end
  end

  test "native bounded decoder errors rather than truncating and malformed segments fail closed" do
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, spans())
    assert {:error, :query_sample_limit} = S3.decode_segment(:traces, blob, nil, nil, max_records: 1)
    assert {:error, {:decode_failed, _}} = S3.decode_segment(:traces, "not parquet", nil, nil, [])
    assert :fallback = NIF.encode_trace_segment_parquet([%{}])
    assert {:error, {:encode_failed, _}} = S3.encode_segment(:traces, [%Span{timestamp_ns: -1}])
  end

  test "native top-k agrees with the Elixir ordering even for metadata ties and typed filters" do
    [base | _] = spans()

    records =
      for i <- 1..250 do
        %{
          base
          | timestamp_ns: 10,
            end_timestamp_ns: 10 + i,
            service: "service-#{rem(i, 3)}",
            parent_span_id: if(rem(i, 2) != 0, do: base.parent_span_id),
            attributes:
              Map.merge(Map.new(1..40, &{"key-#{&1}", &1}), %{
                "n" => i,
                "float" => i / 3,
                "zero" => if(rem(i, 2) == 0, do: -0.0, else: 0.0),
                "nested" => [false, nil, %{"🌍" => "\n\"\\"}],
                "unsigned" => 18_446_744_073_709_551_615
              })
        }
      end

    for record <- records do
      assert SpanKey.size(record) == byte_size(SpanKey.encode(Span.to_map(record)))
    end

    sorted = SortOrder.sort(records, :traces)
    {left, right} = Enum.split(sorted, 127)
    assert SortOrder.merge_spans(left, right, 80) == Enum.take(sorted, 80)
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, records)

    for opts <- [
          [limit: 1],
          [limit: 7],
          [limit: 40],
          [limit: 10, root_only: true],
          [limit: 10, min_duration_ns: 20, max_duration_ns: 70],
          [limit: 10, parent_span_id: base.parent_span_id],
          [limit: 10, attributes: %{"zero" => 0.0, "nested" => [false, nil, %{"🌍" => "\n\"\\"}]}]
        ] do
      expected = records |> Enum.filter(&Span.matches?(&1, opts)) |> SortOrder.sort(:traces) |> Enum.take(opts[:limit])
      assert {:ok, ^expected} = S3.decode_segment(:traces, blob, nil, nil, opts)
      filters = Map.new(opts, fn {key, value} -> {Atom.to_string(key), value} end)
      assert {:ok, state} = NIF.trace_query_new(nil, nil, filters, nil, 1000)

      for batch <- Enum.chunk_every(Enum.reverse(records), 63) do
        assert {:ok, segment, _, _} = S3.encode_segment(:traces, batch)
        assert {:ok, {_, _, _}} = NIF.trace_query_add(state, segment)
      end

      assert {:ok, json} = NIF.trace_query_finish(state, 5000)
      maps = Enum.map(expected, &Map.put(Span.to_map(&1), "duration_ns", &1.end_timestamp_ns - &1.timestamp_ns))
      assert Pulse.JSON.decode!(json) === maps
      assert :fallback = NIF.trace_query_finish(state, 5000)
    end
  end

  test "failed native queries poison their resource, never finish a partial answer" do
    assert {:ok, state} = NIF.trace_query_new(nil, nil, %{"limit" => 1}, ["trace_id"], 1)
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, spans())
    assert {:error, :query_sample_limit} = NIF.trace_query_add(state, blob)
    assert :fallback = NIF.trace_query_finish(state, 5000)
    assert :fallback = NIF.trace_query_add(state, blob)
  end

  test "normalized payload amplification is bounded before Parquet allocation" do
    [base | _] = spans()
    shared = %{"a" => String.duplicate("a", 16_384), "b" => String.duplicate("b", 16_384)}
    records = List.duplicate(%{base | resource: shared}, 512)
    assert {:error, :payload_too_large} = S3.encode_segment(:traces, records)
  end

  test "idempotency hashes include nested metadata and traces use their own prefix" do
    records = spans()
    assert S3.caller_content_hash(:traces, records) == S3.caller_content_hash(:traces, records)
    changed = Enum.map(records, &%{&1 | events: []})
    refute S3.caller_content_hash(:traces, records) == S3.caller_content_hash(:traces, changed)
    {:ok, hash} = S3.caller_content_hash(:traces, records)
    key = S3.object_key("acme", "traces", 10, 20, hash, "request-1")
    assert key =~ "tenants/acme/v4/signal=traces/date=1970-01-01/hour=00/"
    assert key == S3.object_key("acme", "traces", 10, 20, hash, "request-1")
    assert {:error, {:invalid_tenant, _}} = S3.append(:traces, "../bad", records)
  end

  test "randomized nested metadata round trips idempotently on the native path" do
    :rand.seed(:exsss, {4, 5, 6})

    records =
      for i <- 1..200 do
        {:ok, [s], 0} = Traces.decode(Fixture.payload([Fixture.span(:rand.uniform(100_000))]))

        %{
          s
          | span_id: Base.encode16(<<i::64>>, case: :lower),
            service: if(rem(i, 3) != 0, do: "service-#{rem(i, 7)}"),
            attributes: %{"n" => i, "float" => i / 3, "nil" => nil, "nested" => [false, %{"empty" => []}, "🌍\n#{i}"]}
        }
      end

    assert {:ok, blob, _, _} = S3.encode_segment(:traces, records)
    assert {:ok, decoded} = S3.decode_segment(:traces, blob, nil, nil, [])
    assert SortOrder.sort(decoded, :traces) == SortOrder.sort(records, :traces)
    assert {:ok, again, _, _} = S3.encode_segment(:traces, decoded)
    assert {:ok, ^decoded} = S3.decode_segment(:traces, again, nil, nil, [])
  end
end
