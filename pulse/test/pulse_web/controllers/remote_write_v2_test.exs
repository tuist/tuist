defmodule PulseWeb.RemoteWriteV2Test do
  # Remote Write 2.0 (`io.prometheus.write.v2.Request`), encoded by hand as
  # Prometheus and Alloy send it: labels and metadata are references into a
  # request-wide symbol table.
  use PulseWeb.ConnCase, async: true

  import Bitwise

  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3

  @v2 "application/x-protobuf;proto=io.prometheus.write.v2.Request"

  defp varint(v) when v < 128, do: <<v>>
  defp varint(v), do: <<(v &&& 0x7F) ||| 0x80>> <> varint(v >>> 7)
  defp field(n, bytes), do: varint(n <<< 3 ||| 2) <> varint(byte_size(bytes)) <> bytes
  defp varint_field(n, v), do: varint(n <<< 3) <> varint(v)

  defp sample(value, ts_ms), do: field(2, <<0x09, value::little-float-64>> <> varint_field(2, ts_ms))

  # `symbols` is the table; `series` entries name symbols, not indexes.
  defp request(symbols, series) do
    index = symbols |> Enum.with_index() |> Map.new()
    ref = &Map.fetch!(index, &1)

    timeseries =
      Enum.map_join(series, fn s ->
        refs = s.labels |> Enum.flat_map(fn {n, v} -> [ref.(n), ref.(v)] end) |> Enum.map_join(&varint/1)
        samples = Enum.map_join(s[:samples] || [], fn {v, ts} -> sample(v, ts) end)
        # A float histogram whose span claims a bucket it never sends.
        invalid = <<0x11, 1.0::little-float-64>> <> field(11, <<0x08, 0x00, 0x10, 0x01>>)
        histograms = String.duplicate(field(3, invalid), s[:invalid_histograms] || 0)

        metadata =
          case s[:metadata] do
            nil ->
              ""

            {type, help, unit} ->
              field(5, varint_field(1, type) <> varint_field(3, ref.(help)) <> varint_field(4, ref.(unit)))
          end

        field(5, field(1, refs) <> samples <> histograms <> metadata)
      end)

    timeseries <> Enum.map_join(symbols, &field(4, &1))
  end

  defp post_v2(tenant, body, content_type \\ @v2) do
    {:ok, compressed} = :snappyer.compress(body)

    build_conn()
    |> put_req_header("x-scope-orgid", tenant)
    |> put_req_header("content-type", content_type)
    |> put_req_header("content-encoding", "snappy")
    |> put_req_header("x-prometheus-remote-write-version", "2.0.0")
    |> post("/api/v1/write", compressed)
  end

  defp written(conn) do
    for kind <- ~w(samples histograms exemplars) do
      conn |> get_resp_header("x-prometheus-remote-write-#{kind}-written") |> List.first()
    end
  end

  defp tenant, do: "rw2-#{System.unique_integer([:positive])}"

  @fixtures Path.expand("../../fixtures/metrics/remote_write_start", __DIR__)

  test "public Prometheus schemas and real receivers preserve source starts without zero injection" do
    for version <- ["3.5.0", "3.8.0"],
        c <- File.read!(Path.join(@fixtures, "prometheus-#{version}.json")) |> JSON.decode!() do
      tenant = tenant()
      compressed = Base.decode64!(c["snappy_base64"])

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", tenant)
        |> put_req_header("content-type", @v2)
        |> put_req_header("content-encoding", "snappy")
        |> post("/api/v1/write", compressed)

      assert conn.status == c["status"], "#{version}: #{c["name"]}"
      assert written(conn) == c["written"]
      assert {:ok, stored} = Storage.query(:metrics, tenant)
      stored = Enum.sort_by(stored, & &1.timestamp_ns)
      assert Enum.map(stored, & &1.start_timestamp_ms) == c["starts_ms"], "#{version}: #{c["name"]}"
      assert length(stored) == 2
      assert {:ok, []} = Storage.query(:metrics, tenant <> "-other")

      [reference] = c["query"]["data"]["result"]
      {plural, singular} = if c["kind"] == "float", do: {"values", "value"}, else: {"histograms", "histogram"}

      for [seconds, _value] = pair <- reference[plural] do
        assert {:ok, [%{"text" => actual}]} =
                 Tools.call("query_promql", %{
                   "tenant" => tenant,
                   "query" => c["name"],
                   "end_ts_ns" => seconds * 1_000_000_000
                 })

        assert Pulse.JSON.decode!(actual) == %{
                 "status" => "success",
                 "data" => %{
                   "resultType" => "vector",
                   "result" => [
                     %{"metric" => reference["metric"], singular => pair}
                   ]
                 }
               }
      end

      # Native and fallback raw JSON both expose starts; histograms exercise
      # the fallback while ordinary floats must actually use the native path.
      assert {:ok, [%{"text" => raw}]} = Tools.call("query_metrics", %{"tenant" => tenant})

      assert raw |> Pulse.JSON.decode!() |> Enum.sort_by(& &1["timestamp_ns"]) |> Enum.map(& &1["start_timestamp_ms"]) ==
               c["starts_ms"]

      if c["kind"] == "float", do: assert({:ok, _} = NIF.encode_metric_samples(stored))

      assert {:ok, blob, 1_700_000_000_000_000_000, 1_700_000_015_000_000_000} = S3.encode_segment(:metrics, stored)
      assert {:ok, ^stored} = S3.decode_segment(:metrics, blob, nil, nil, [])
      assert {:ok, again, _, _} = S3.encode_segment(:metrics, stored)
      assert {:ok, ^stored} = S3.decode_segment(:metrics, again, nil, nil, [])
    end
  end

  test "modern starts override legacy starts, zero unsets, and singular occurrences are last-wins" do
    symbols = Enum.map_join(["", "__name__", "starts"], &field(4, &1))
    labels = field(1, <<1, 2>>)
    point = fn ts, extra -> field(2, <<9, -0.0::little-float-64>> <> varint_field(2, ts) <> extra) end

    body =
      symbols <>
        field(
          5,
          labels <>
            point.(10, "") <>
            point.(11, varint_field(3, 0)) <>
            point.(12, varint_field(3, 3) <> varint_field(3, 7)) <>
            point.(13, varint_field(3, 4) <> varint_field(3, 0)) <>
            varint_field(6, 1) <> varint_field(6, 2)
        ) <>
        field(5, labels <> point.(13, varint_field(3, 8)) <> varint_field(6, 9))

    tenant = tenant()
    assert tenant |> post_v2(body) |> response(204)
    assert {:ok, stored} = Storage.query(:metrics, tenant)
    stored = Enum.sort_by(stored, & &1.timestamp_ns)
    assert Enum.map(stored, & &1.start_timestamp_ms) == [2, nil, 7, nil, 8]
    assert stored |> Enum.map(& &1.series_id) |> Enum.uniq() |> length() == 1
    assert Enum.all?(stored, &(<<&1.value::float-64>> == <<0x8000000000000000::64>>))
    # Same labels/time/value but different starts must not share a decoded row.
    assert {:ok, blob, _, _} = S3.encode_segment(:metrics, stored)
    assert {:ok, ^stored} = S3.decode_segment(:metrics, blob, nil, nil, [])

    # Unset starts do not create a new physical column; plain keyed bytes stay
    # byte-identical to the pinned pre-change encoder fixture.
    assert {:ok, legacy} =
             NIF.decode_metric_segment_parquet(
               File.read!(Path.join(@fixtures, "../keyed_metric_v2.parquet")),
               nil,
               nil,
               []
             )

    assert Enum.all?(legacy, &is_nil(&1.start_timestamp_ms))
    assert {:ok, exact, _, _, _} = NIF.encode_metric_segment_parquet_v2(legacy)
    assert exact == File.read!(Path.join(@fixtures, "../keyed_metric_v2.parquet"))
  end

  test "start-bearing requests retain supplied-record admission before storage, including keyed requests" do
    Runtime.put_env(:pulse, Pulse.IngestLimits, max_records: 1)

    for version <- ["3.5.0", "3.8.0"] do
      c = File.read!(Path.join(@fixtures, "prometheus-#{version}.json")) |> JSON.decode!() |> Enum.at(1)
      tenant = tenant()

      conn =
        build_conn()
        |> put_req_header("x-scope-orgid", tenant)
        |> put_req_header("idempotency-key", "start-key")
        |> put_req_header("content-type", @v2)
        |> put_req_header("content-encoding", "snappy")
        |> post("/api/v1/write", Base.decode64!(c["snappy_base64"]))

      assert json_response(conn, 413) == %{"error" => "too_many_records"}
      assert {:ok, []} = Storage.query(:metrics, tenant)
    end
  end

  test "malformed start fields fail whole before any valid sibling or metadata is published" do
    symbols = Enum.map_join(["", "__name__", "starts"], &field(4, &1))
    labels = field(1, <<1, 2>>)
    metadata = field(5, varint_field(1, 1))
    good = field(5, labels <> sample(1.0, 10) <> metadata)
    control = tenant()
    assert control |> post_v2(symbols <> good) |> response(204)
    assert {:ok, %{"starts" => _}} = Storage.metric_metadata(control)

    bad_points = [
      field(2, <<9, 1.0::little-float-64, 16, 11>> <> field(3, "bad")),
      field(3, <<8, 1, 120, 11>> <> field(17, "bad")),
      sample(1.0, 11) <> field(6, "bad"),
      field(2, <<9, 1.0::little-float-64, 16, 11, 24, 128>>),
      field(3, <<8, 1, 120, 11, 136, 1, 128>>),
      # Malformed point framing is wire corruption even without a start.
      field(2, <<9, 1.0::little-float-64, 16>>)
    ]

    for bad <- bad_points do
      tenant = tenant()
      conn = tenant |> post_v2(symbols <> good <> field(5, labels <> bad))
      assert json_response(conn, 400) == %{"error" => "invalid_protobuf"}
      assert {:ok, []} = Storage.query(:metrics, tenant)
      assert {:ok, %{}} = Storage.metric_metadata(tenant)
    end
  end

  @symbols [
    "",
    "__name__",
    "http_requests_total",
    "job",
    "api",
    "Requests served.",
    "latency_seconds_bucket",
    "le",
    "0.5",
    "Latency.",
    "seconds"
  ]

  test "stores samples, reports written counts and retains per-series metadata" do
    tenant = tenant()

    body =
      request(@symbols, [
        %{
          labels: [{"__name__", "http_requests_total"}, {"job", "api"}],
          samples: [{1.0, 1_700_000_000_000}, {2.0, 1_700_000_015_000}],
          metadata: {1, "Requests served.", ""}
        },
        %{
          labels: [{"__name__", "latency_seconds_bucket"}, {"le", "0.5"}],
          samples: [{3.0, 1_700_000_000_000}],
          metadata: {3, "Latency.", "seconds"}
        }
      ])

    conn = post_v2(tenant, body)
    assert response(conn, 204) == ""
    assert written(conn) == ["3", "0", "0"]

    assert {:ok, stored} = Storage.query(:metrics, tenant)

    assert stored |> Enum.map(&{&1.labels["__name__"], &1.value}) |> Enum.sort() == [
             {"http_requests_total", 1.0},
             {"http_requests_total", 2.0},
             {"latency_seconds_bucket", 3.0}
           ]

    assert [%MetricSample{labels: %{"job" => "api"}} | _] = Enum.sort_by(stored, & &1.labels["__name__"])

    assert build_conn() |> put_req_header("x-scope-orgid", tenant) |> get("/api/v1/metadata") |> json_response(200) ==
             %{
               "status" => "success",
               "data" => %{
                 "http_requests_total" => [%{"type" => "counter", "help" => "Requests served.", "unit" => ""}],
                 "latency_seconds" => [%{"type" => "histogram", "help" => "Latency.", "unit" => "seconds"}]
               }
             }
  end

  test "stores valid series of a partly invalid request and answers 400 with the written count" do
    tenant = tenant()

    body =
      request(@symbols, [
        %{labels: [{"__name__", "http_requests_total"}], samples: [{1.0, 1_700_000_000_000}], invalid_histograms: 1},
        %{labels: [{"__name__", "latency_seconds_bucket"}], invalid_histograms: 2},
        %{labels: [{"job", "api"}, {"job", "api"}], samples: [{1.0, 1_700_000_000_000}]}
      ])

    conn = post_v2(tenant, body)
    assert json_response(conn, 400) == %{"error" => "rejected_records", "rejected" => 4}
    assert written(conn) == ["1", "0", "0"]
    assert get_resp_header(conn, "x-pulse-rejected-records") == ["4"]
    assert {:ok, [%MetricSample{value: 1.0}]} = Storage.query(:metrics, tenant)
  end

  test "selects the message by the Content-Type proto parameter" do
    tenant = tenant()
    body = request(@symbols, [%{labels: [{"__name__", "http_requests_total"}], samples: [{1.0, 1_700_000_000_000}]}])

    for content_type <- [
          "application/x-protobuf; proto=\"io.prometheus.write.v2.Request\"",
          "Application/X-Protobuf;PROTO=io.prometheus.write.v2.Request"
        ] do
      assert tenant |> post_v2(body, content_type) |> response(204)
    end

    assert {:ok, [_, _]} = Storage.query(:metrics, tenant)

    assert tenant |> post_v2(body, "application/x-protobuf;proto=io.prometheus.write.v3.Request") |> response(415)
    assert tenant |> post_v2(body, "text/plain") |> response(415)

    # Read as 1.0, a 2.0 body has no series: nothing is stored and no
    # written counts are claimed.
    conn = post_v2(tenant, body, "application/x-protobuf;proto=prometheus.WriteRequest")
    assert response(conn, 204)
    assert written(conn) == [nil, nil, nil]
    assert {:ok, [_, _]} = Storage.query(:metrics, tenant)
  end

  test "malformed requests store nothing" do
    tenant = tenant()
    assert tenant |> post_v2(<<0x2A, 0x10, 0x01>>) |> json_response(400) == %{"error" => "invalid_protobuf"}
    assert {:ok, []} = Storage.query(:metrics, tenant)
  end
end
