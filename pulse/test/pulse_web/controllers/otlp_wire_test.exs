defmodule PulseWeb.OTLPWireTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.IngestLimits
  alias Pulse.Loki.Tail
  alias Pulse.OTLP.JSON
  alias Pulse.OTLP.Logs
  alias Pulse.OTLP.Metrics
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.OTLPMetricFixture, as: MetricFixture
  alias Pulse.Test.OTLPTraceFixture, as: Wire

  @directory "test/fixtures/otlp/wire"
  @signals [{:logs, "logs", 1}, {:metrics, "metrics", 2}, {:traces, "traces", 1}]

  test "gzip merged protobuf and public canonical wire share keyed S3 content across instances" do
    {runtime, peer} = s3_instances()

    for {signal, name, count} <- @signals do
      for {instance, suffix} <- [{runtime, ".protobuf"}, {peer, "-canonical.protobuf"}, {runtime, ".protobuf"}] do
        body = File.read!(Path.join(@directory, name <> suffix))

        response =
          Runtime.with(instance, fn ->
            request(name, :protobuf, :zlib.gzip(body), [
              {"content-encoding", "gzip"},
              {"idempotency-key", "merged-source"}
            ])
          end)

        assert response.status == 200
      end

      assert {:ok, records} = Storage.query(signal, "default")
      assert length(records) == count
    end
  end

  test "raw decimal/exponent JSON, public canonical JSON and protobuf replay one keyed S3 source" do
    {runtime, peer} = s3_instances()
    directory = "test/fixtures/otlp/numbers"

    for {signal, name, decoder, count} <- [
          {:logs, "logs", Logs, 1},
          {:metrics, "metrics", Metrics, 7},
          {:traces, "traces", Traces, 1}
        ] do
      for {instance, suffix, format} <- [
            {runtime, "-input.json", :json},
            {peer, "-canonical.json", :json},
            {runtime, ".protobuf", :protobuf}
          ] do
        body = File.read!(Path.join(directory, name <> suffix))

        response =
          Runtime.with(instance, fn ->
            request(name, format, :zlib.gzip(body), [
              {"content-encoding", "gzip"},
              {"idempotency-key", "numeric-source"}
            ])
          end)

        assert response.status == 200
      end

      assert {:ok, stored} = Storage.query(signal, "default")
      assert length(stored) == count
      assert Enum.all?(stored, &(&1.timestamp_ns == 1_700_000_000_123_456_789))
      canonical = directory |> Path.join(name <> "-canonical.json") |> File.read!() |> JSON.decode!()
      assert {:ok, expected, 0} = decoder.decode(canonical)

      metadata = fn records ->
        records |> Enum.map(&:erlang.term_to_binary(&1.otlp, [:deterministic])) |> Enum.sort()
      end

      assert metadata.(stored) == metadata.(expected)
    end
  end

  test "quoted trace uint32 fields replay exact keyed S3 bytes across instances and protobuf" do
    {runtime, peer} = s3_instances()
    directory = "test/fixtures/otlp/trace_integers"

    for {instance, name, format} <- [
          {runtime, "traces-input.json", :json},
          {peer, "traces-canonical.json", :json},
          {peer, "traces.protobuf", :protobuf}
        ] do
      response =
        Runtime.with(instance, fn ->
          request("traces", format, :zlib.gzip(File.read!(Path.join(directory, name))), [
            {"content-encoding", "gzip"},
            {"idempotency-key", "quoted-trace-u32"}
          ])
        end)

      assert response.status == 200
    end

    assert {:ok, [span]} = Storage.query(:traces, "default")
    assert span.flags == 4_294_967_295
    assert span.resource_dropped_attributes_count == 1
    assert span.scope["dropped_attributes_count"] == 2
    assert [%{"dropped_attributes_count" => 4}] = span.events
    assert [%{"flags" => 257, "dropped_attributes_count" => 5}] = span.links
  end

  test "invalid quoted trace integers never publish keyed subsets and preserve unkeyed partial success" do
    source = File.read!("test/fixtures/otlp/trace_integers/traces-canonical.json") |> JSON.decode!(:traces)
    path = ["resourceSpans", Access.at(0), "scopeSpans", Access.at(0), "spans"]
    [valid] = get_in(source, path)

    for literal <- ["1e-1000", "4294967296", "01", "+1", " 1"] do
      payload = put_in(source, path, [Map.put(valid, "flags", literal), valid])
      body = Pulse.JSON.encode!(payload)

      assert request("traces", :json, :zlib.gzip(body), [
               {"content-encoding", "gzip"},
               {"idempotency-key", "never-a-quoted-subset"}
             ]).status == 400

      assert {:ok, []} = Storage.query(:traces, "default")
    end

    body = source |> put_in(path, [Map.put(valid, "flags", "1e-1000"), valid]) |> Pulse.JSON.encode!()
    response = request("traces", :json, body, [])
    assert json_response(response, 200)["partialSuccess"]["rejectedSpans"] == "1"
    assert {:ok, [_]} = Storage.query(:traces, "default")
  end

  test "quoted trace uint32 fields replay public JSON/protobuf bytes across keyed S3 instances" do
    {runtime, peer} = s3_instances()
    directory = "test/fixtures/otlp/trace_uint32"

    for {instance, name, format} <- [
          {runtime, "input.json", :json},
          {peer, "canonical.json", :json},
          {peer, "request.protobuf", :protobuf},
          {runtime, "input.json", :json}
        ] do
      body = File.read!(Path.join(directory, name))

      response =
        Runtime.with(instance, fn ->
          request("traces", format, :zlib.gzip(body), [
            {"content-encoding", "gzip"},
            {"idempotency-key", "quoted-uint32"}
          ])
        end)

      assert response.status == 200
    end

    assert {:ok, expected, 0} = Traces.decode_protobuf(File.read!(Path.join(directory, "request.protobuf")))
    assert {:ok, ^expected} = Storage.query(:traces, "default")
    assert Runtime.with(peer, fn -> Storage.query(:traces, "default") end) == {:ok, expected}
  end

  test "invalid quoted uint32 fields never publish a keyed valid neighbor and retain unkeyed rejection counts" do
    base = "test/fixtures/otlp/trace_uint32/canonical.json" |> File.read!() |> JSON.decode!(:traces)
    resource = ["resourceSpans", Access.at(0), "resource"]
    scope = ["resourceSpans", Access.at(0), "scopeSpans", Access.at(0)]
    span = scope ++ ["spans", Access.at(0)]

    paths = [
      {resource ++ ["droppedAttributesCount"], true},
      {scope ++ ["scope", "droppedAttributesCount"], true},
      {span ++ ["droppedAttributesCount"], false},
      {span ++ ["droppedEventsCount"], false},
      {span ++ ["droppedLinksCount"], false},
      {span ++ ["flags"], false},
      {span ++ ["events", Access.at(0), "droppedAttributesCount"], false},
      {span ++ ["links", Access.at(0), "droppedAttributesCount"], false},
      {span ++ ["links", Access.at(0), "flags"], false}
    ]

    for {{path, whole?}, index} <- Enum.with_index(paths) do
      bad = put_in(base, path, "4294967296")
      mixed = %{"resourceSpans" => base["resourceSpans"] ++ bad["resourceSpans"]}
      body = mixed |> Pulse.JSON.encode!() |> :zlib.gzip()
      tenant = "uint32-#{index}"
      headers = [{"x-scope-orgid", tenant}, {"content-encoding", "gzip"}]

      assert request("traces", :json, body, [{"idempotency-key", "no-subset"} | headers]).status == 400
      assert {:ok, []} = Storage.query(:traces, tenant)

      response = request("traces", :json, body, headers)

      if whole? do
        assert response.status == 400
        assert {:ok, []} = Storage.query(:traces, tenant)
      else
        assert json_response(response, 200)["partialSuccess"]["rejectedSpans"] == "1"
        assert {:ok, [_span]} = Storage.query(:traces, tenant)
      end
    end
  end

  test "fractional timestamps cannot underflow into unknown-time fallback or a keyed subset" do
    for {signal, name, _count} <- @signals do
      body =
        "test/fixtures/otlp/numbers"
        |> Path.join(name <> "-input.json")
        |> File.read!()
        |> String.replace("1.700000000123456789e18", "1e-1000")

      assert request(name, :json, body, [{"idempotency-key", "fractional-time"}]).status == 400
      assert {:ok, []} = Storage.query(signal, "default")
    end
  end

  test "a keyed request with a valid neighbor never publishes the fractional integer subset" do
    body =
      ~s({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"1","body":{"intValue":1e-1000}},{"timeUnixNano":"1","body":{"intValue":9007199254740993.0}}]}]}]})

    assert request("logs", :json, body, [{"idempotency-key", "never-a-subset"}]).status == 400
    assert {:ok, []} = Storage.query(:logs, "default")
  end

  test "invalid fractional integer points are counted, not rounded into stored zero" do
    body =
      ~s({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"1","body":{"intValue":1e-1000}},{"timeUnixNano":"1","body":{"intValue":9007199254740993.0}}]}]}]})

    response = request("logs", :json, body, [])
    assert json_response(response, 200)["partialSuccess"]["rejectedLogRecords"] == "1"
    assert {:ok, [log]} = Storage.query(:logs, "default")
    assert log.body == 9_007_199_254_740_993
  end

  test "known JSON duplicates after a valid earlier resource publish nothing, keyed or unkeyed" do
    for {signal, name, _count} <- @signals do
      root = %{logs: "resourceLogs", metrics: "resourceMetrics", traces: "resourceSpans"}[signal]
      body = File.read!(Path.join("test/fixtures/otlp/numbers", name <> "-input.json"))
      prefix = ~s({"#{root}":[)
      assert String.starts_with?(body, prefix)
      group = binary_part(body, byte_size(prefix), byte_size(body) - byte_size(prefix) - 2)
      duplicate = ~s({"resource":{"droppedAttributesCount":null,"droppedAttributesCount":0}})
      invalid = prefix <> group <> "," <> duplicate <> "]}"

      for headers <- [[], [{"idempotency-key", "known-duplicate"}]] do
        assert_error_sent 400, fn ->
          request(name, :json, :zlib.gzip(invalid), [{"content-encoding", "gzip"} | headers])
        end

        assert {:ok, []} = Storage.query(signal, "default")
      end
    end
  end

  test "receiver-scoped unknown duplicates preserve typed S3 content and cross-instance keyed replay" do
    {runtime, peer} = s3_instances()

    for {signal, name, other, count} <- [
          {:logs, "logs", "resourceMetrics", 1},
          {:metrics, "metrics", "resourceSpans", 7},
          {:traces, "traces", "resourceLogs", 1}
        ] do
      source = File.read!(Path.join("test/fixtures/otlp/numbers", name <> "-input.json"))

      extra =
        ~s({"#{other}":[],"#{other}":[],"future":{"intValue":7,"intValue":8,"number":1e1000000},"futureTiny":-1e-1000000,)

      body = extra <> binary_part(source, 1, byte_size(source) - 1)

      for instance <- [runtime, peer] do
        response =
          Runtime.with(instance, fn ->
            request(name, :json, :zlib.gzip(body), [{"content-encoding", "gzip"}, {"idempotency-key", "scoped-unknown"}])
          end)

        assert response.status == 200
      end

      canonical = File.read!(Path.join("test/fixtures/otlp/numbers", name <> "-canonical.json"))

      assert Runtime.with(peer, fn -> request(name, :json, canonical, [{"idempotency-key", "scoped-unknown"}]) end).status ==
               200

      assert {:ok, stored} = Storage.query(signal, "default")
      assert length(stored) == count
      assert Enum.all?(stored, &(&1.timestamp_ns == 1_700_000_000_123_456_789))
    end
  end

  test "JSON parser preserves general first-key semantics outside OTLP and scopes encoded OTLP paths" do
    body = ~s({"resourceLogs":[],"resourceLogs":[]})
    options = PulseWeb.OTLPJSONParser.init(json_decoder: Pulse.JSON)
    conn = Plug.Test.conn(:post, "/other", body)

    assert {:ok, %{"resourceLogs" => []}, _conn} =
             PulseWeb.OTLPJSONParser.parse(conn, "application", "json", [], options)

    assert_error_sent 400, fn -> request("%6cogs", :json, body, []) end
    assert_error_sent 400, fn -> request("logs", :json, body, []) end
  end

  test "public exponential boundaries preserve exact keyed S3 content across JSON and protobuf instances" do
    {runtime, peer} = s3_instances()
    directory = "test/fixtures/otlp/exponential_boundaries"

    for {instance, name, format} <- [{runtime, "request.json", :json}, {peer, "request.protobuf", :protobuf}] do
      body = File.read!(Path.join(directory, name))

      response =
        Runtime.with(instance, fn ->
          request("metrics", format, :zlib.gzip(body), [
            {"content-encoding", "gzip"},
            {"idempotency-key", "exponential-boundaries"}
          ])
        end)

      assert response.status == 200
    end

    assert {:ok, stored} = Storage.query(:metrics, "default")
    assert {:ok, expected, 0} = Metrics.decode_protobuf(File.read!(Path.join(directory, "request.protobuf")))
    assert length(stored) == length(expected)
    metadata = fn rows -> rows |> Enum.map(&:erlang.term_to_binary(&1.otlp, [:deterministic])) |> Enum.sort() end
    assert metadata.(stored) == metadata.(expected)
  end

  test "exponential safety ceilings publish no valid scalar subset over gzip HTTP, keyed or unkeyed" do
    point = %{
      "timeUnixNano" => "1700000000123456789",
      "count" => "161",
      "scale" => -10,
      "positive" => %{"bucketCounts" => List.duplicate(1, 161)}
    }

    raw = %{point | "scale" => 0, "count" => "0", "positive" => %{"bucketCounts" => List.duplicate(0, 65_537)}}

    for point <- [point, raw],
        headers <- [[], [{"idempotency-key", "no-exponential-subset"}]],
        format <- [:json, :protobuf] do
      metric = %{"name" => "wide", "exponentialHistogram" => %{"aggregationTemporality" => 2, "dataPoints" => [point]}}
      payload = MetricFixture.payload([MetricFixture.gauge([MetricFixture.point()]), metric])
      body = if format == :json, do: Pulse.JSON.encode!(payload), else: MetricFixture.protobuf(payload)
      assert request("metrics", format, :zlib.gzip(body), [{"content-encoding", "gzip"} | headers]).status == 413
      assert {:ok, []} = Storage.query(:metrics, "default")
    end
  end

  test "a later split owner exhausting admission publishes none of an otherwise valid keyed request" do
    Runtime.put_env(:pulse, IngestLimits, max_attributes: 2)

    parts =
      for key <- ["a", "b", "c"] do
        Wire.bytes(1, Wire.message(%{"key" => key, "value" => %{"boolValue" => true}}, :pair))
      end

    bad = Wire.bytes(1, Wire.bytes(1, Enum.at(parts, 0) <> Enum.at(parts, 1)) <> Wire.bytes(1, Enum.at(parts, 2)))

    for {signal, name, _count} <- @signals do
      valid = File.read!(Path.join(@directory, name <> ".protobuf"))
      assert request(name, :protobuf, valid <> bad, [{"idempotency-key", "split-limit"}]).status == 413
      assert {:ok, []} = Storage.query(signal, "default")
    end
  end

  test "quoted integer exponent times keep exact nanoseconds over HTTP JSON" do
    for {signal, name, count} <- @signals do
      body =
        @directory
        |> Path.join(name <> ".json")
        |> File.read!()
        |> String.replace("1700000000123456789", "1.700000000123456789e18")

      assert request(name, :json, body, [{"idempotency-key", "exact-exponent"}]).status == 200
      assert {:ok, records} = Storage.query(signal, "default")
      assert length(records) == count
      assert Enum.all?(records, &(&1.timestamp_ns == 1_700_000_000_123_456_789))
    end
  end

  test "losing data members cannot hide source points from HTTP record admission" do
    Runtime.put_env(:pulse, IngestLimits, max_records: 3)
    body = File.read!(Path.join(@directory, "metrics.protobuf"))
    assert request("metrics", :protobuf, body, [{"idempotency-key", "losing-members"}]).status == 413
    assert {:ok, []} = Storage.query(:metrics, "default")
  end

  setup do
    Memory.reset()
    :ok
  end

  defp s3_instances do
    Runtime.share()

    store =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    Runtime.put_env(:pulse, Storage, adapter: S3)

    Runtime.put_env(:pulse, S3, %{
      bucket: "wire",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "wire-#{System.unique_integer([:positive])}",
      secret_access_key: "fixture",
      allow_http: true,
      refresh_stale_ms: 0
    })

    start_supervised!(S3.ManifestSupervision)
    runtime = Runtime.current()
    peer = %{runtime | instance: __MODULE__.Peer}

    Runtime.with(peer, fn ->
      start_supervised!(Supervisor.child_spec(S3.ManifestSupervision, id: :wire_peer))
      start_supervised!(Supervisor.child_spec(Tail, id: :wire_peer_tail))
    end)

    {runtime, peer}
  end

  defp request(name, format, body, headers) do
    mime = if format == :json, do: "application/json", else: "application/x-protobuf"

    conn =
      Enum.reduce(headers, put_req_header(build_conn(), "content-type", mime), fn {key, value}, conn ->
        put_req_header(conn, key, value)
      end)

    post(conn, "/v1/" <> name, body)
  end
end
