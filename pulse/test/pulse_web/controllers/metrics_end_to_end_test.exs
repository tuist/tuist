defmodule PulseWeb.MetricsEndToEndTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.OTLP.JSON
  alias Pulse.OTLP.Metrics
  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.QuerySlots
  alias Pulse.PromQL.TaskSupervisor
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.MCPMessages
  alias Pulse.Test.OTLPMetricFixture, as: Fixture
  alias Pulse.Test.RuntimePlug

  setup tags do
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

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      metric_footer_pruning_enabled: true,
      manifest_format: Map.get(tags, :manifest_format, "paged")
    }

    tenant = "metric-http-#{System.unique_integer([:positive])}"
    token = "test-token"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => digest})
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    url = start_api(Runtime.current(), :metric_api)
    peer = %{Runtime.current() | instance: __MODULE__.Peer}

    Runtime.with(peer, fn ->
      start_supervised!(Supervisor.child_spec(ManifestSupervision, id: :peer_manifest))
      start_supervised!({Task.Supervisor, name: TaskSupervisor}, id: :peer_queries)
      start_supervised!({Registry, keys: :unique, name: QuerySlots}, id: :peer_slots)
    end)

    peer_url = start_api(peer, :metric_peer_api)
    %{store: store, config: config, tenant: tenant, token: token, url: url, peer_url: peer_url}
  end

  test "public histogram/summary JSON and protobuf publish across instances with keyed replay and native queries",
       ctx do
    directory = "test/fixtures/otlp/distributions/"
    json = File.read!(directory <> "input.json")
    wire = File.read!(directory <> "input.protobuf")

    for {url, type, body} <- [{ctx.url, "application/json", json}, {ctx.peer_url, "application/x-protobuf", wire}] do
      response =
        Req.post!(url <> "/v1/metrics",
          headers:
            headers(ctx) ++
              [
                {"content-type", type},
                {"content-encoding", "gzip"},
                {"idempotency-key", "same-protocol-point"}
              ],
          body: :zlib.gzip(body),
          retry: false
        )

      assert response.status == 200
    end

    assert length(query(ctx, ctx.peer_url)) == 24

    earlier = JSON.decode!(json)

    earlier =
      update_in(earlier, ["resourceMetrics", Access.at(0), "scopeMetrics", Access.at(0), "metrics"], fn metrics ->
        Enum.map(metrics, fn metric ->
          kind = if Map.has_key?(metric, "histogram"), do: "histogram", else: "summary"

          update_in(metric, [kind, "dataPoints"], fn points ->
            Enum.map(points, &earlier_point(&1, metric["name"]))
          end)
        end)
      end)

    assert Req.post!(ctx.peer_url <> "/v1/metrics",
             headers: headers(ctx) ++ [{"idempotency-key", "earlier-point"}],
             json: earlier,
             retry: false
           ).status == 200

    before = query(ctx, ctx.url)
    assert length(before) == 48
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    after_merge = query(ctx, ctx.peer_url)

    assert Enum.sort_by(before, &{&1["labels"], &1["timestamp_ns"]}) ===
             Enum.sort_by(after_merge, &{&1["labels"], &1["timestamp_ns"]})

    response =
      Req.get!(ctx.peer_url <> "/api/v1/query",
        headers: headers(ctx),
        params: [
          query: "histogram_quantile(0.5, request_duration_bucket)",
          time: "1700000000.123456789"
        ]
      )

    assert response.status == 200
    assert [%{"value" => [_, "1.5"]}] = response.body["data"]["result"]

    for {time, expected} <- [{"1700000000.123456788", "11"}, {"1700000000.123456789", nil}] do
      result =
        Req.get!(ctx.peer_url <> "/api/v1/query",
          headers: headers(ctx),
          params: [query: "stale_values_count", time: time]
        )

      assert result.status == 200

      if expected,
        do: assert([%{"value" => [_, ^expected]}] = result.body["data"]["result"]),
        else: assert(result.body["data"]["result"] == [])
    end

    assert Enum.any?(after_merge, &(&1["otlp"]["point"]["count"] == "18446744073709551615"))
  end

  test "distribution safety and keyed partial failures never publish a subset", ctx do
    payload = "test/fixtures/otlp/distributions/input.json" |> File.read!() |> JSON.decode!()

    payload =
      update_in(payload, ["resourceMetrics", Access.at(0), "scopeMetrics", Access.at(0), "metrics"], &Enum.take(&1, 1))

    original = Runtime.get_env(:pulse, Pulse.IngestLimits, [])
    Runtime.put_env(:pulse, Pulse.IngestLimits, max_records: 4)
    response = Req.post!(ctx.url <> "/v1/metrics", headers: headers(ctx), json: payload, retry: false)
    assert response.status == 413
    Runtime.put_env(:pulse, Pulse.IngestLimits, original)
    assert Agent.get(ctx.store, &map_size(&1.objects)) == 0

    original_point =
      get_in(payload, [
        "resourceMetrics",
        Access.at(0),
        "scopeMetrics",
        Access.at(0),
        "metrics",
        Access.at(0),
        "histogram",
        "dataPoints",
        Access.at(0)
      ])

    scalar =
      Fixture.gauge([original_point |> Map.take(["timeUnixNano", "attributes"]) |> Map.put("asDouble", 1.0)])
      |> Map.put("name", "request_duration_count")

    aliased =
      update_in(payload, ["resourceMetrics", Access.at(0), "scopeMetrics", Access.at(0), "metrics"], &(&1 ++ [scalar]))

    assert Req.post!(ctx.url <> "/v1/metrics", headers: headers(ctx), json: aliased, retry: false).status == 400
    assert Agent.get(ctx.store, &map_size(&1.objects)) == 0

    mixed =
      update_in(
        payload,
        [
          "resourceMetrics",
          Access.at(0),
          "scopeMetrics",
          Access.at(0),
          "metrics",
          Access.at(0),
          "histogram",
          "dataPoints"
        ],
        fn [point] ->
          [point, Map.put(point, "count", "999")]
        end
      )

    response =
      Req.post!(ctx.url <> "/v1/metrics",
        headers: headers(ctx) ++ [{"idempotency-key", "no-subset"}],
        json: mixed,
        retry: false
      )

    assert response.status == 400
    assert Agent.get(ctx.store, &map_size(&1.objects)) == 0
    response = Req.post!(ctx.url <> "/v1/metrics", headers: headers(ctx), json: mixed, retry: false)
    assert response.status == 200
    assert response.body["partialSuccess"]["rejectedDataPoints"] == "1"
    assert length(query(ctx, ctx.peer_url)) == 5
  end

  test "metric discovery reads gzip JSON/protobuf across instances, restart, compaction and retention", ctx do
    payload = fn name, host, env, timestamp ->
      point =
        Fixture.point()
        |> Map.put("timeUnixNano", timestamp)
        |> Map.put("attributes", [
          %{"key" => "host", "value" => %{"stringValue" => host}},
          %{"key" => "env", "value" => %{"stringValue" => env}}
        ])

      Fixture.payload([Fixture.gauge([point]) |> Map.put("name", name)])
    end

    requests = payload.("requests", "a", "prod", "10000000001")
    latency = payload.("latency", "b", "dev", "30000000000")

    for {url, type, body} <- [
          {ctx.url, "application/json", Pulse.JSON.encode!(requests)},
          {ctx.peer_url, "application/x-protobuf", Fixture.protobuf(latency)}
        ] do
      assert Req.post!(url <> "/v1/metrics",
               headers: headers(ctx) ++ [{"content-type", type}, {"content-encoding", "gzip"}],
               body: :zlib.gzip(body),
               retry: false
             ).status == 200
    end

    selectors = [{"match[]", ~s(requests{env="prod"})}, {"match[]", ~s(latency{env="dev"})}]
    suffix = "?" <> URI.encode_query(selectors)

    for url <- [ctx.url, ctx.peer_url] do
      assert Req.get!(url <> "/api/v1/labels", headers: headers(ctx)).body["data"] == ["__name__", "env", "host"]
      Agent.update(ctx.store, &%{&1 | requests: []})
      assert Req.get!(url <> "/api/v1/label/host/values" <> suffix, headers: headers(ctx)).body["data"] == ["a", "b"]

      data_gets =
        Agent.get(ctx.store, fn state ->
          for {"GET", key} <- state.requests, String.ends_with?(key, ".parquet"), do: key
        end)

      assert length(data_gets) == 2
      assert length(Enum.uniq(data_gets)) == 2

      response =
        Req.post!(url <> "/api/v1/series",
          headers: headers(ctx) ++ [{"content-type", "application/x-www-form-urlencoded"}],
          body: URI.encode_query(selectors),
          retry: false
        )

      assert response.status == 200
      assert Enum.map(response.body["data"], & &1["__name__"]) == ["latency", "requests"]

      assert Req.get!(url <> "/api/v1/label/host/values?start=10.000000001&end=10.000000001", headers: headers(ctx)).body[
               "data"
             ] == ["a"]
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert Req.get!(ctx.url <> "/api/v1/label/host/values", headers: headers(ctx)).body["data"] == ["a", "b"]
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config)

    assert Req.get!(ctx.peer_url <> "/api/v1/label/host/values" <> suffix, headers: headers(ctx)).body["data"] == [
             "a",
             "b"
           ]

    mcp =
      Req.post!(ctx.peer_url <> "/mcp",
        headers:
          headers(ctx) ++
            [
              {"content-type", "application/json"},
              {"mcp-protocol-version", MCPMessages.version()},
              {"mcp-method", "tools/call"},
              {"mcp-name", "discover_metrics"}
            ],
        json:
          MCPMessages.request(1, "tools/call", %{
            "name" => "discover_metrics",
            "arguments" => %{
              "tenant" => ctx.tenant,
              "mode" => "values",
              "label" => "env",
              "selectors" => ["requests", "latency"]
            }
          })
      )

    assert mcp.status == 200
    refute mcp.body["result"]["isError"] == true
    [%{"text" => text}] = mcp.body["result"]["content"]
    assert Pulse.JSON.decode!(text)["data"] == ["dev", "prod"]
    assert Req.get!(ctx.url <> "/api/v1/labels", headers: [{"x-scope-orgid", ctx.tenant}]).status == 401

    config =
      ctx.config
      |> Map.put(:metrics_retention_days, 1)
      |> Map.put(:retention_mode, "enforce")
      |> Map.put(:retention_manifest_format, "bucketed")

    assert {:ok, _} = Retention.advance(ctx.tenant, "metrics", config, now_ns: 3 * 86_400_000_000_000)
    assert Req.get!(ctx.url <> "/api/v1/labels", headers: headers(ctx)).body["data"] == []
  end

  @tag manifest_format: "flat"
  test "discovery charges actual footer rows despite an undercounted flat manifest and shares OR scan limits", ctx do
    rows =
      for n <- 1..3, do: %MetricSample{timestamp_ns: n, value: 1.0, labels: %{"__name__" => "metric", "host" => "a"}}

    assert :ok = Storage.append(:metrics, ctx.tenant, rows)

    {key, {_etag, body}} =
      Agent.get(ctx.store, fn state ->
        Enum.find(state.objects, fn {key, _} -> String.ends_with?(key, "/manifest.json") end)
      end)

    wire = Pulse.JSON.decode!(body) |> Map.update!("s", fn segments -> Enum.map(segments, &Map.put(&1, "r", 0)) end)
    assert {:ok, _} = Pulse.ObjectStore.put(ctx.config, key, Pulse.JSON.encode!(wire))
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_rows: 2)
    response = Req.get!(ctx.url <> "/api/v1/label/host/values", headers: headers(ctx))
    assert response.status == 422
    refute Map.has_key?(response.body, "data")
    Runtime.put_env(:pulse, Evaluator, max_scan_rows: 2)
    query = Req.get!(ctx.url <> "/api/v1/query", headers: headers(ctx), params: [query: "metric", time: "0.000000003"])
    assert query.status == 422
    refute Map.has_key?(query.body, "data")
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_scan_bytes: 1)
    assert Req.get!(ctx.url <> "/api/v1/labels", headers: headers(ctx)).status == 422
  end

  test "PromQL charges the scan-row budget with the rows its selectors match, not whole segments", ctx do
    # Each remote-write-like batch holds one sample of a small metric among
    # many rows of another, so every segment is a candidate for both.
    for batch <- 1..4 do
      ts = batch * 15_000_000_000
      wanted = %MetricSample{timestamp_ns: ts, value: batch * 1.0, labels: %{"__name__" => "wanted"}}

      noise =
        for i <- 1..499,
            do: %MetricSample{timestamp_ns: ts, value: 1.0, labels: %{"__name__" => "noise", "i" => "#{i}"}}

      assert :ok = Storage.append(:metrics, ctx.tenant, [wanted | noise])
    end

    # 2,000 stored rows in candidate segments, four of them matched.
    Runtime.put_env(:pulse, Evaluator, max_scan_rows: 1000)
    opts = %{start_ts_ns: 15_000_000_000, end_ts_ns: 60_000_000_000, step_ns: 15_000_000_000}

    # One selector (footer-first reads) and two selectors (one shared pass).
    for query <- ["wanted", "wanted unless on () absent_metric"] do
      assert {:ok, result} = Evaluator.query(query, ctx.tenant, opts)
      assert [%{"values" => values}] = result["data"]["result"]
      assert Enum.map(values, &List.last/1) == ["1", "2", "3", "4"]
    end

    # Matched rows still bind: this selector matches 1,996 rows.
    for query <- ["count(noise)", "count(noise unless on () absent_metric)"] do
      response =
        Req.get!(ctx.url <> "/api/v1/query_range",
          headers: headers(ctx),
          params: [query: query, start: "15", end: "60", step: "15"]
        )

      assert response.status == 422
      assert %{"limit" => "max_scan_rows", "value" => 1000, "observed" => observed} = response.body["limit"]
      assert observed in 1001..1996
    end
  end

  test "a conflicting existing object is permanent HTTP409 and is never overwritten or republished", ctx do
    headers = headers(ctx) ++ [{"content-type", "application/x-protobuf"}, {"idempotency-key", "conflict"}]
    assert Req.post!(ctx.url <> "/v1/metrics", headers: headers, body: Fixture.protobuf(), retry: false).status == 200

    [{key, {_, bytes}}] =
      Agent.get(ctx.store, &Enum.filter(&1.objects, fn {key, _} -> String.ends_with?(key, ".parquet") end))

    # Model a pre-existing incoherent/old writer, not a supported semantic
    # recovery. The retry must preserve evidence rather than repair by PUT.
    assert {:ok, _} = Pulse.ObjectStore.put(ctx.config, key, bytes <> "different")
    before = Agent.get(ctx.store, & &1.objects)
    response = Req.post!(ctx.peer_url <> "/v1/metrics", headers: headers, body: Fixture.protobuf(), retry: false)
    assert response.status == 409
    assert response.headers["retry-after"] == nil
    assert Agent.get(ctx.store, & &1.objects) == before
  end

  test "independent instance contexts concurrently publish the same JSON/protobuf key exactly once", ctx do
    jobs = [
      {ctx.url, "application/json", File.read!("test/fixtures/otlp/protoc-metrics.json")},
      {ctx.peer_url, "application/x-protobuf", Fixture.protobuf()}
    ]

    jobs
    |> Task.async_stream(
      fn {url, type, body} ->
        Req.post!(url <> "/v1/metrics",
          headers:
            headers(ctx) ++
              [{"content-type", type}, {"content-encoding", "gzip"}, {"idempotency-key", "compiled-fixture"}],
          body: :zlib.gzip(body),
          retry: false
        )
      end,
      timeout: 15_000
    )
    |> Enum.each(fn {:ok, response} -> assert response.status == 200 end)

    assert Agent.get(ctx.store, fn state ->
             Enum.count(state.objects, fn {key, _} -> String.ends_with?(key, ".parquet") end)
           end) == 1

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    for url <- [ctx.url, ctx.peer_url] do
      records = query(ctx, url)
      assert length(records) == 7

      zero =
        Enum.find(
          records,
          &(&1["timestamp_ns"] == "1700000000123456789" or &1["timestamp_ns"] == 1_700_000_000_123_456_789)
        )

      assert <<zero["value"]::float-64>> == <<0x8000000000000000::64>>
      assert zero["otlp"]["point"]["asDouble"] === -0.0
      assert zero["otlp"]["resource"]["droppedAttributesCount"] == 1
    end

    bad =
      Req.post!(ctx.peer_url <> "/v1/metrics",
        headers: headers(ctx) ++ [{"content-type", "application/x-protobuf"}, {"idempotency-key", "compiled-fixture"}],
        body: Fixture.protobuf(Fixture.payload([Fixture.gauge([Fixture.point(99.0)])])),
        retry: false
      )

    # Idempotency is content-addressed, not exclusive ownership of a key.
    assert bad.status == 200
    assert length(query(ctx, ctx.url)) == 8
  end

  test "metadata survives compacted Parquet and both instances return the same complete raw records", ctx do
    for url <- [ctx.url, ctx.peer_url] do
      assert Req.post!(url <> "/v1/metrics",
               headers: headers(ctx) ++ [{"content-type", "application/x-protobuf"}],
               body: Fixture.protobuf()
             ).status == 200
    end

    before = query(ctx, ctx.url)
    assert length(before) == 14
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config)

    for url <- [ctx.url, ctx.peer_url] do
      assert :erlang.term_to_binary(query(ctx, url), [:deterministic]) ==
               :erlang.term_to_binary(before, [:deterministic])
    end

    assert {:ok, records, 0} = Metrics.decode_protobuf(Fixture.protobuf())
    assert Enum.all?(records, &is_map(&1.otlp))
  end

  test "optional native postings survive gzip ingest, independent readers and complete compaction", ctx do
    points =
      for {host, env, value} <- [{"a", "prod", 0.0}, {"b", "dev", 1.0}, {"", "", 2.0}, {nil, nil, 3.0}] do
        attributes =
          for {key, value} <- [{"host", host}, {"env", env}],
              not is_nil(value),
              do: %{"key" => key, "value" => %{"stringValue" => value}}

        Fixture.point(value) |> Map.put("attributes", attributes)
      end

    payload = Fixture.payload([Fixture.gauge(points)])

    for {url, type, body} <- [
          {ctx.url, "application/json", Pulse.JSON.encode!(payload)},
          {ctx.peer_url, "application/x-protobuf", Fixture.protobuf(payload)}
        ] do
      assert Req.post!(url <> "/v1/metrics",
               headers: headers(ctx) ++ [{"content-type", type}, {"content-encoding", "gzip"}],
               body: :zlib.gzip(body),
               retry: false
             ).status == 200
    end

    objects = Agent.get(ctx.store, &Enum.filter(&1.objects, fn {key, _} -> String.ends_with?(key, ".parquet") end))
    assert length(objects) == 2
    assert Enum.all?(objects, fn {_, {_, bytes}} -> :binary.match(bytes, "pulse.metric.postings.v1") != :nomatch end)

    # Model an otherwise-compatible writer without a recognized footer index.
    # Equal-length replacement preserves the Parquet footer and all source rows.
    {key, {_, bytes}} = hd(objects)
    old = :binary.replace(bytes, "pulse.metric.postings.v1", "pulse.metric.postings.v0", [:global])
    assert {:ok, _} = Pulse.ObjectStore.put(ctx.config, key, old)
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    impossible = [{"host", :eq, "a"}, {"env", :eq, "dev"}]
    assert {:error, :query_scan_limit} = S3.query(:metrics, ctx.tenant, matchers: impossible, max_scan_segments: 1)
    assert {:ok, []} = S3.query(:metrics, ctx.tenant, matchers: impossible)

    filters = [
      [],
      [%{"name" => "host", "op" => "=", "value" => "a"}],
      [%{"name" => "host", "op" => "=", "value" => ""}],
      [%{"name" => "host", "op" => "=", "value" => "a"}, %{"name" => "env", "op" => "=", "value" => "dev"}]
    ]

    before = for matchers <- filters, do: query(ctx, ctx.url, %{"matchers" => matchers})
    assert Enum.map(before, &length/1) == [8, 2, 4, 0]
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    for url <- [ctx.url, ctx.peer_url] do
      after_compaction = for matchers <- filters, do: query(ctx, url, %{"matchers" => matchers})
      assert after_compaction == before

      response =
        Req.get!(url <> "/api/v1/query",
          headers: headers(ctx),
          params: [query: ~s(metric{host="a",env="prod"}), time: "1700000000.123456789"],
          retry: false
        )

      assert response.status == 200
      assert [%{"value" => [_, "0"]}] = response.body["data"]["result"]
    end

    assert Agent.get(ctx.store, fn state ->
             state.objects
             |> Enum.filter(fn {key, _} ->
               String.ends_with?(key, ".parquet") and not Map.has_key?(Map.new(objects), key)
             end)
             |> Enum.any?(fn {_, {_, bytes}} -> :binary.match(bytes, "pulse.metric.postings.v1") != :nomatch end)
           end)
  end

  test "pinned SDK wire replays through gzip HTTP to native S3 without SDK tooling", ctx do
    wire = File.read!("test/fixtures/otlp/python-sdk-metrics.protobuf")

    response =
      Req.post!(ctx.url <> "/v1/metrics",
        headers:
          headers(ctx) ++
            [{"content-type", "application/x-protobuf"}, {"content-encoding", "gzip"}],
        body: :zlib.gzip(wire)
      )

    assert response.status == 200
    records = query(ctx, ctx.peer_url)
    assert length(records) == 2
    counter = Enum.find(records, &(&1["labels"]["__name__"] == "sdk_requests_total"))
    assert counter["value"] == 7.0
    [exemplar] = counter["otlp"]["point"]["exemplars"]
    assert exemplar["traceId"] == "0123456789abcdef0123456789abcdef"
    assert exemplar["asInt"] == "7"
  end

  test "consumed large protobuf failures respond promptly and auth/safety errors publish nothing", ctx do
    body =
      Fixture.protobuf(Fixture.payload([Fixture.gauge([Fixture.point()])])) <>
        <<0xFA, 0x7F>> <> varint(1_500_000) <> :crypto.strong_rand_bytes(1_500_000) <> <<0>>

    response =
      Req.post!(ctx.url <> "/v1/metrics",
        headers: headers(ctx) ++ [{"content-type", "application/x-protobuf"}],
        body: body,
        retry: false,
        receive_timeout: 5000
      )

    assert response.status == 400

    response =
      Req.post!(ctx.peer_url <> "/v1/metrics",
        headers: [{"content-type", "application/x-protobuf"}, {"x-scope-orgid", ctx.tenant}],
        body: Fixture.protobuf(),
        retry: false
      )

    assert response.status == 401
    payload = Fixture.payload([Fixture.gauge([Fixture.point() |> Map.put("asDouble", String.duplicate("1", 1025))])])

    assert Req.post!(ctx.url <> "/v1/metrics",
             headers: headers(ctx) ++ [{"content-type", "application/json"}],
             json: payload
           ).status == 413

    assert Agent.get(ctx.store, &map_size(&1.objects)) == 0
  end

  defp start_api(runtime, id) do
    api =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: runtime}, ip: {127, 0, 0, 1}, port: 0},
        id: id
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(api)
    "http://127.0.0.1:#{port}"
  end

  defp earlier_point(point, "stale.values"),
    do: Map.merge(point, %{"timeUnixNano" => "1700000000123456788", "flags" => 0, "count" => "11", "sum" => 11.0})

  defp earlier_point(point, _), do: Map.put(point, "timeUnixNano", "1700000000123456788")

  defp headers(ctx), do: [{"authorization", "Bearer " <> ctx.token}, {"x-scope-orgid", ctx.tenant}]

  defp query(ctx, url, arguments \\ %{}) do
    response =
      Req.post!(url <> "/mcp",
        headers:
          headers(ctx) ++
            [
              {"content-type", "application/json"},
              {"mcp-protocol-version", MCPMessages.version()},
              {"mcp-method", "tools/call"},
              {"mcp-name", "query_metrics"}
            ],
        json:
          MCPMessages.request(1, "tools/call", %{
            "name" => "query_metrics",
            "arguments" => Map.put(arguments, "tenant", ctx.tenant)
          })
      )

    assert response.status == 200
    assert response.body["result"]["isError"] != true
    [%{"text" => text}] = response.body["result"]["content"]
    Pulse.JSON.decode!(text)
  end

  defp varint(n) when n < 128, do: <<n>>
  defp varint(n), do: [<<Bitwise.bor(Bitwise.band(n, 127), 128)>>, varint(Bitwise.bsr(n, 7))] |> IO.iodata_to_binary()
end
