defmodule PulseWeb.RemoteWriteRichSamplesTest do
  # Native histograms and exemplars over both Remote Write versions, through
  # storage to `/api/v1/query_exemplars`.
  use PulseWeb.ConnCase, async: true

  import Bitwise

  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.Exemplar
  alias Pulse.Record.MetricSample
  alias Pulse.Record.NativeHistogram
  alias Pulse.Storage
  alias Pulse.Storage.S3

  @ms 1_700_000_000_000

  defp varint(v) when v < 128, do: <<v>>
  defp varint(v), do: <<(v &&& 0x7F) ||| 0x80>> <> varint(v >>> 7)
  defp zigzag(v) when v >= 0, do: varint(v <<< 1)
  defp zigzag(v), do: varint((-v <<< 1) - 1)
  defp field(n, bytes), do: varint(n <<< 3 ||| 2) <> varint(byte_size(bytes)) <> bytes
  defp varint_field(n, v), do: varint(n <<< 3) <> varint(v)
  defp double(n, v), do: varint(n <<< 3 ||| 1) <> <<v::little-float-64>>

  defp label(name, value), do: field(1, name) <> field(2, value)
  defp sample(value, ts), do: double(1, value) <> varint_field(2, ts)

  # Prometheus' integer histogram example: 12 observations summing to 18.4,
  # 2 in the zero bucket, buckets 1, 2, 1 at indexes 0..2 and 1 at index 4.
  defp histogram(ts) do
    span = fn offset, length -> field(11, varint(1 <<< 3) <> zigzag(offset) <> varint_field(2, length)) end

    varint_field(1, 12) <>
      double(3, 18.4) <>
      varint(4 <<< 3) <>
      zigzag(1) <>
      double(5, 0.001) <>
      varint_field(6, 2) <>
      span.(0, 3) <>
      span.(1, 1) <>
      field(12, Enum.map_join([1, 1, -1, 0], &zigzag/1)) <>
      varint_field(15, ts)
  end

  defp exemplar_v1(trace, value, ts), do: field(1, label("trace_id", trace)) <> double(2, value) <> varint_field(3, ts)

  defp write(tenant, body, content_type) do
    {:ok, compressed} = :snappyer.compress(body)

    build_conn()
    |> put_req_header("x-scope-orgid", tenant)
    |> put_req_header("content-type", content_type)
    |> put_req_header("content-encoding", "snappy")
    |> post("/api/v1/write", compressed)
  end

  defp tenant, do: "rich-#{System.unique_integer([:positive])}"

  defp exemplars(tenant, query, start, finish) do
    build_conn()
    |> put_req_header("x-scope-orgid", tenant)
    |> get("/api/v1/query_exemplars", %{"query" => query, "start" => start, "end" => finish})
    |> json_response(200)
  end

  test "Remote Write 1.0 stores native histograms and exemplars on the nearest sample" do
    tenant = tenant()

    counter =
      field(1, label("__name__", "requests_total")) <>
        field(2, sample(1.0, @ms)) <>
        field(2, sample(2.0, @ms + 15_000)) <>
        field(3, exemplar_v1("abc", 0.5, @ms + 14_000)) <>
        field(3, exemplar_v1(String.duplicate("x", 200), 1.0, @ms))

    latency = field(1, label("__name__", "latency_seconds")) <> field(4, histogram(@ms))

    assert write(tenant, field(1, counter) <> field(1, latency), "application/x-protobuf") |> response(204)
    assert {:ok, stored} = Storage.query(:metrics, tenant)

    assert [%MetricSample{value: nil, histogram: %NativeHistogram{} = h}] =
             Enum.filter(stored, &(&1.labels["__name__"] == "latency_seconds"))

    assert {h.schema, h.count, h.sum, h.zero_count, h.zero_threshold} == {1, 12.0, 18.4, 2.0, 0.001}

    assert {h.positive_spans, h.positive_buckets, h.counter_reset_hint} ==
             {[{0, 3}, {1, 1}], [1.0, 2.0, 1.0, 1.0], :unknown}

    # The over-long exemplar is dropped; the other lands on the later sample.
    assert [%{value: 1.0, exemplars: nil}, %{value: 2.0, exemplars: [%Exemplar{} = e]}] =
             stored |> Enum.filter(&(&1.labels["__name__"] == "requests_total")) |> Enum.sort_by(& &1.timestamp_ns)

    assert {e.labels, e.value, e.timestamp_ns} == {%{"trace_id" => "abc"}, 0.5, (@ms + 14_000) * 1_000_000}

    seconds = div(@ms, 1000)

    assert exemplars(tenant, "sum(rate(requests_total[5m]))", seconds, seconds + 60) == %{
             "status" => "success",
             "data" => [
               %{
                 "seriesLabels" => %{"__name__" => "requests_total"},
                 "exemplars" => [%{"labels" => %{"trace_id" => "abc"}, "value" => "0.5", "timestamp" => seconds + 14.0}]
               }
             ]
           }

    assert exemplars(tenant, "requests_total", seconds, seconds + 10)["data"] == []
  end

  test "exemplars sent in entries of their own find their samples, or keep a row of their own" do
    tenant = tenant()
    name = field(1, label("__name__", "requests_total"))

    # As Prometheus sends them: the sample and the exemplar in separate
    # entries, and an exemplar whose sample went in an earlier request.
    body =
      field(1, name <> field(2, sample(2.0, @ms))) <>
        field(1, name <> field(3, exemplar_v1("abc", 0.5, @ms - 1_000))) <>
        field(1, field(1, label("__name__", "other_total")) <> field(3, exemplar_v1("def", 1.5, @ms)))

    assert tenant |> write(body, "application/x-protobuf") |> response(204)
    assert {:ok, stored} = Storage.query(:metrics, tenant)
    by_name = Map.new(stored, &{&1.labels["__name__"], &1})
    assert %{value: 2.0, exemplars: [%Exemplar{value: 0.5}]} = by_name["requests_total"]
    assert %{value: nil, histogram: nil, exemplars: [%Exemplar{value: 1.5}]} = by_name["other_total"]

    seconds = div(@ms, 1000)
    assert [_, _] = exemplars(tenant, ~s<{__name__=~".+_total"}>, seconds - 10, seconds)["data"]

    # The exemplar-only row is not a sample.
    assert {:ok, %{"data" => %{"result" => []}}} =
             Evaluator.query("other_total", tenant, %{end_ts_ns: @ms * 1_000_000})
  end

  test "Remote Write 2.0 reports written histograms and exemplars" do
    tenant = tenant()
    symbols = ["", "__name__", "latency_seconds", "trace_id", "abc"]
    exemplar = field(1, varint(3) <> varint(4)) <> double(2, 0.2) <> varint_field(3, @ms)
    series = field(1, varint(1) <> varint(2)) <> field(3, histogram(@ms)) <> field(4, exemplar)
    body = field(5, series) <> Enum.map_join(symbols, &field(4, &1))

    conn = write(tenant, body, "application/x-protobuf;proto=io.prometheus.write.v2.Request")
    assert response(conn, 204)

    assert for(
             kind <- ~w(samples histograms exemplars),
             do: conn |> get_resp_header("x-prometheus-remote-write-#{kind}-written") |> List.first()
           ) == ["0", "1", "1"]

    assert {:ok, [%MetricSample{histogram: %NativeHistogram{count: 12.0}, exemplars: [%Exemplar{value: 0.2}]}]} =
             Storage.query(:metrics, tenant)
  end

  test "native histogram Sum StaleNaN terminates the series in both wire versions and Parquet" do
    for version <- [:v1, :v2] do
      tenant = tenant()
      name = "latency_seconds"
      stale = <<3 <<< 3 ||| 1>> <> <<0x7FF0000000000002::little-64>> <> varint_field(15, @ms + 15_000)
      histograms = [histogram(@ms - 15_000), histogram(@ms), stale]

      {body, content_type} =
        case version do
          :v1 ->
            {field(1, field(1, label("__name__", name)) <> Enum.map_join(histograms, &field(4, &1))),
             "application/x-protobuf"}

          :v2 ->
            symbols = Enum.map_join(["", "__name__", name], &field(4, &1))
            series = field(1, varint(1) <> varint(2)) <> Enum.map_join(histograms, &field(3, &1))
            {symbols <> field(5, series), "application/x-protobuf;proto=io.prometheus.write.v2.Request"}
        end

      conn = write(tenant, body, content_type)
      assert response(conn, 204)

      if version == :v2 do
        assert get_resp_header(conn, "x-prometheus-remote-write-histograms-written") == ["3"]
        assert get_resp_header(conn, "x-prometheus-remote-write-samples-written") == ["0"]
      end

      at = (@ms + 15_001) * 1_000_000
      assert {:ok, %{"data" => %{"result" => []}}} = Evaluator.query(name, tenant, %{end_ts_ns: at})

      assert {:ok, %{"data" => %{"result" => []}}} =
               Evaluator.query("histogram_count(#{name})", tenant, %{end_ts_ns: at})

      assert {:ok, %{"data" => %{"result" => [%{"value" => [_, "1"]}]}}} =
               Evaluator.query("absent(#{name})", tenant, %{end_ts_ns: at})

      assert {:ok, %{"data" => %{"result" => [%{"value" => [_, "0"]}]}}} =
               Evaluator.query("histogram_sum(rate(#{name}[1m]))", tenant, %{end_ts_ns: at})

      assert {:ok, stored} = Storage.query(:metrics, tenant)
      assert Enum.any?(stored, &match?(%{histogram: %NativeHistogram{sum: :stale}}, &1))
      assert {:ok, blob, _, _} = S3.encode_segment(:metrics, stored)
      assert {:ok, decoded} = S3.decode_segment(:metrics, blob, nil, nil, [])
      assert Enum.sort(decoded) == Enum.sort(stored)
      assert {:ok, compacted, _, _} = S3.encode_segment(:metrics, decoded)
      assert {:ok, ^decoded} = S3.decode_segment(:metrics, compacted, nil, nil, [])
    end
  end

  test "segments round-trip histograms and exemplars, and plain segments stay unchanged" do
    histogram = %NativeHistogram{
      schema: 0,
      count: 3.0,
      sum: :nan,
      zero_count: 1.0,
      positive_spans: [{-1, 2}],
      positive_buckets: [1.0, 1.0],
      counter_reset_hint: :gauge
    }

    exemplar = %Exemplar{labels: %{"trace_id" => "t"}, value: :infinity, timestamp_ns: 5}

    rich = [
      %MetricSample{labels: %{"__name__" => "h"}, timestamp_ns: 10, histogram: histogram},
      %MetricSample{labels: %{"__name__" => "c"}, timestamp_ns: 10, value: 1.0, exemplars: [exemplar]},
      %MetricSample{labels: %{"__name__" => "c"}, timestamp_ns: 20, value: 2.0},
      # Exemplars whose sample came in another request.
      %MetricSample{labels: %{"__name__" => "e"}, timestamp_ns: 15, exemplars: [exemplar]}
    ]

    assert {:ok, blob, 10, 20} = S3.encode_segment(:metrics, rich)
    assert {:ok, decoded} = S3.decode_segment(:metrics, blob, nil, nil, [])
    by_name = Enum.group_by(decoded, & &1.labels["__name__"])
    assert [%{value: nil, histogram: ^histogram, exemplars: nil}] = by_name["h"]
    assert [%{exemplars: [^exemplar]}, %{exemplars: nil}] = Enum.sort_by(by_name["c"], & &1.timestamp_ns)
    assert [%{value: nil, histogram: nil, exemplars: [^exemplar]}] = by_name["e"]
    assert {:ok, exemplar_rows} = S3.decode_segment(:metrics, blob, nil, nil, exemplars: true)
    assert exemplar_rows |> Enum.map(& &1.timestamp_ns) |> Enum.sort() == [10, 15]

    # Re-encoding what was decoded, as compaction does, keeps every row.
    assert {:ok, reencoded, 10, 20} = S3.encode_segment(:metrics, decoded)
    assert {:ok, again} = S3.decode_segment(:metrics, reencoded, nil, nil, [])
    assert Enum.sort(again) == Enum.sort(decoded)

    plain = [%MetricSample{labels: %{"__name__" => "c"}, timestamp_ns: 20, value: 2.0}]
    assert {:ok, plain_blob, _, _} = S3.encode_segment(:metrics, plain)
    refute plain_blob =~ "histogram"
    refute plain_blob =~ "exemplars"
  end
end
