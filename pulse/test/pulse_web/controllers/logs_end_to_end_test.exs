defmodule PulseWeb.LogsEndToEndTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.MCPMessages
  alias Pulse.Test.OTLPLogFixture, as: Fixture
  alias Pulse.Test.RuntimePlug

  test "large rejected Snappy requests retain consumed HTTP connection state", ctx do
    # Incompressible wire bytes ensure read_body consumes TCP data beyond the
    # header buffer. A zero decoded-size prefix plus extra bytes is invalid.
    body = <<0>> <> :crypto.strong_rand_bytes(1_500_000)

    for endpoint <- ["/loki/api/v1/push", "/api/v1/write"] do
      response =
        Req.post!(ctx.url <> endpoint,
          body: body,
          retry: false,
          headers: headers(ctx) ++ [{"content-type", "application/x-protobuf"}, {"content-encoding", "snappy"}]
        )

      assert response.status == 400
      assert response.body["error"] == "invalid_snappy"
    end

    response =
      Req.post!(ctx.url <> "/v1/traces",
        body: body,
        retry: false,
        headers: headers(ctx) ++ [{"content-type", "application/x-protobuf"}]
      )

    assert response.status == 400
    assert is_binary(response.body)
    assert Agent.get(ctx.store, &map_size(&1.objects)) == 0
  end

  setup do
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
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    tenant = "log-http-#{System.unique_integer([:positive])}"
    token = "test-token"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => digest})
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)

    api =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0},
        id: :log_api
      )

    {:ok, {_ip, api_port}} = ThousandIsland.listener_info(api)
    %{store: store, config: config, tenant: tenant, token: token, url: "http://127.0.0.1:#{api_port}"}
  end

  test "public OTLP gzip protobuf to real native S3/Parquet/CAS to MCP survives cache loss and keyed retry", ctx do
    headers =
      headers(ctx) ++
        [
          {"idempotency-key", "compiled-fixture"},
          {"content-type", "application/x-protobuf"},
          {"content-encoding", "gzip"}
        ]

    for _ <- 1..2 do
      response = Req.post!(ctx.url <> "/v1/logs", headers: headers, body: :zlib.gzip(Fixture.protobuf()))
      assert response.status == 200
      assert response.headers["content-type"] == ["application/x-protobuf"]
      assert response.body == ""
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    [bytes_log, structured] = query(ctx, %{"service" => "example-api"})
    assert bytes_log["body"] == "aGVsbG8="
    assert bytes_log["otlp"]["body"] == %{"bytesValue" => "aGVsbG8="}
    assert structured["otlp"]["scope"]["name"] == "fixture.logger"
    assert structured["otlp"]["scope"]["attributes"] == [%{"key" => "enabled", "value" => %{"boolValue" => false}}]
    assert structured["otlp"]["flags"] == 4_294_967_295
    assert structured["otlp"]["eventName"] == "example.login"
    assert structured["trace_id"] == "30313233343536373839616263646566"
    assert structured["span_id"] == "6465616462656566"

    assert structured["body"]["numbers"] == [
             9_223_372_036_854_775_807,
             -9_223_372_036_854_775_808,
             -0.0,
             "NaN",
             "Infinity",
             "-Infinity",
             nil
           ]

    assert <<Enum.at(structured["body"]["numbers"], 2)::float-64>> == <<0x8000000000000000::64>>
    assert structured["resource"]["deployment.environment"] == "production"
    assert structured["resource"]["deployment.environment.name"] == "production"
    # The independent JSON representation of the same batch has the same keyed identity.
    response =
      Req.post!(ctx.url <> "/v1/logs",
        headers: headers(ctx) ++ [{"idempotency-key", "compiled-fixture"}],
        json: Fixture.json()
      )

    assert response.status == 200
    assert length(query(ctx, %{})) == 2
  end

  test "observed-only logs are range-queryable and admitted into managed retention", ctx do
    Runtime.put_env(
      :pulse,
      S3,
      Map.merge(ctx.config, %{retention_mode: "enforce", retention_manifest_format: "bucketed", logs_retention_days: 1})
    )

    now = System.system_time(:nanosecond)
    observed = %{"observedTimeUnixNano" => Integer.to_string(now), "body" => %{"stringValue" => "observed"}}
    event = %{"timeUnixNano" => Integer.to_string(now + 1), "body" => %{"stringValue" => "event"}}

    response =
      Req.post!(ctx.url <> "/v1/logs",
        headers: headers(ctx) ++ [{"idempotency-key", "observed-retry"}],
        json: Fixture.payload([observed, event])
      )

    assert response.status == 200
    [event, observed] = query(ctx, %{"start_ts_ns" => now, "end_ts_ns" => now + 1})
    assert event["body"] == "event"
    assert observed["body"] == "observed"
    assert observed["timestamp_ns"] == now
    assert observed["otlp"]["timeUnixNano"] == "0"
    assert observed["otlp"]["observedTimeUnixNano"] == Integer.to_string(now)
  end

  test "whole-request safety failures do not upload, while protobuf partial success remains explicit", ctx do
    before = Agent.get(ctx.store, &map_size(&1.objects))
    body = %{"body" => %{"stringValue" => :binary.copy(<<0>>, 1_500_000)}}

    response =
      Req.post!(ctx.url <> "/v1/logs",
        headers: headers(ctx) ++ [{"content-type", "application/x-protobuf"}],
        body: Fixture.protobuf(Fixture.payload([body]))
      )

    assert response.status == 413
    assert <<8, 8, _::binary>> = response.body
    assert Agent.get(ctx.store, &map_size(&1.objects)) == before
    payload = Fixture.payload([%{"severityNumber" => 99}, List.last(Fixture.records())])

    response =
      Req.post!(ctx.url <> "/v1/logs",
        headers: headers(ctx) ++ [{"content-type", "application/x-protobuf"}],
        body: Fixture.protobuf(payload)
      )

    assert response.status == 200
    assert <<10, _, 8, 1, _::binary>> = response.body
    assert length(query(ctx, %{})) == 1
  end

  test "tenant authorization does not leak ingestion or raw query data", ctx do
    response =
      Req.post!(ctx.url <> "/v1/logs",
        headers: [{"authorization", "Bearer wrong"}, {"x-scope-orgid", ctx.tenant}],
        json: Fixture.json()
      )

    assert response.status == 401
    assert Agent.get(ctx.store, &map_size(&1.objects)) == 0
    response = mcp(ctx, %{"tenant" => "other"})
    assert response.body["result"]["isError"]
    assert query(ctx, %{}) == []
  end

  defp headers(ctx), do: [{"authorization", "Bearer #{ctx.token}"}, {"x-scope-orgid", ctx.tenant}]

  defp mcp(ctx, args) do
    headers = [
      {"authorization", "Bearer #{ctx.token}"},
      {"mcp-protocol-version", MCPMessages.version()},
      {"mcp-method", "tools/call"},
      {"mcp-name", "query_logs"}
    ]

    Req.post!(ctx.url <> "/mcp",
      headers: headers,
      json:
        MCPMessages.request(1, "tools/call", %{
          "name" => "query_logs",
          "arguments" => Map.put_new(args, "tenant", ctx.tenant)
        })
    )
  end

  defp query(ctx, args) do
    response = mcp(ctx, args)
    assert response.status == 200
    refute response.body["result"]["isError"]
    [%{"text" => text}] = response.body["result"]["content"]
    Pulse.JSON.decode!(text)
  end
end
