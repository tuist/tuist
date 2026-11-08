defmodule PulseWeb.CollectorBridgeLiveTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.IngestLimits
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.{CollectorBridgeTap, CompactionStore, ExternalCommand, MCPMessages, RuntimePlug, SDKBridgeAssertions}

  @moduletag :collector_bridge
  @moduletag :tmp_dir
  @moduletag timeout: 120_000

  test "real SDK HTTP propagation and gRPC Collector bridge preserve traces, isolate tenants and classify delivery",
       ctx do
    collector = System.fetch_env!("PULSE_TEST_OTELCOL")
    sdk = System.fetch_env!("PULSE_TEST_TRACE_SDK")

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

    object_server = start_supervised!({Bandit, plug: {CompactionStore, agent: store}, ip: {127, 0, 0, 1}, port: 0})
    object_url = url(object_server)
    tokens = Map.new(~w(alpha beta denied oversize partial), &{&1, "token-#{&1}"})

    hashes =
      Map.new(tokens, fn {tenant, token} ->
        {tenant, "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)}
      end)

    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: hashes)
    Runtime.put_env(:pulse, Storage, adapter: S3)

    Runtime.put_env(:pulse, S3, %{
      bucket: "pulse",
      endpoint: object_url,
      region: "us-east-1",
      access_key_id: ctx.tmp_dir,
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    })

    start_supervised!(ManifestSupervision)
    runtime = Runtime.current()

    api =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: runtime}, ip: {127, 0, 0, 1}, port: 0},
        id: :bridge_api
      )

    limited = %{runtime | configs: Map.put(runtime.configs, {:pulse, IngestLimits}, max_records: 1)}

    small =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: limited}, ip: {127, 0, 0, 1}, port: 0},
        id: :small_api
      )

    owner = self()

    capture =
      start_supervised!({Agent, fn -> %{owner: owner, requests: [], failures: %{"alpha" => [429, 503]}} end},
        id: :capture
      )

    targets = Map.new(tokens, fn {tenant, _} -> {tenant, if(tenant == "oversize", do: url(small), else: url(api))} end)

    tap =
      start_supervised!(
        {Bandit, plug: {CollectorBridgeTap, agent: capture, targets: targets}, ip: {127, 0, 0, 1}, port: 0},
        id: :bridge_tap
      )

    endpoints = ports(Map.keys(tokens))
    config = Path.join(ctx.tmp_dir, "collector.yaml")
    File.write!(config, config(endpoints, url(tap)))
    process = start_supervised!({ExternalCommand, path: collector, args: ["--config", config]}, id: :collector)
    assert :ok = ExternalCommand.ready(process)

    for tenant <- ~w(alpha beta denied oversize partial) do
      oracle = Path.join(ctx.tmp_dir, "#{tenant}-oracle.json")
      args = ["--endpoint", endpoints[tenant], "--tenant", tenant, "--oracle", oracle]
      args = if tenant == "partial", do: args ++ ["--partial"], else: args
      producer = start_supervised!({ExternalCommand, path: sdk, args: args}, id: {:sdk, tenant})
      assert {0, _} = ExternalCommand.await(producer)
      result = Pulse.JSON.decode!(File.read!(oracle))

      if tenant != "partial" do
        assert result["sdk"] == "go.opentelemetry.io/otel v1.43.0"
        assert length(result["spans"]) == 3

        if tenant in ~w(alpha beta) do
          assert result["export_errors"] == []
          assert result["flush_errors"] == []
        else
          assert result["export_errors"] != []
          expected_error = if tenant == "denied", do: "code = Unauthenticated", else: "HTTP Status Code 413"
          assert Enum.all?(result["export_errors"], &String.contains?(&1, expected_error))
        end
      end
    end

    await_deliveries(%{})
    # SDK End is asynchronous; the fixture's Collector does not queue/rebatch.
    # Inspect actual backend acknowledgments, not just producer process exit.
    assert {0, logs} = ExternalCommand.stop(process)
    File.write!(Path.join(ctx.tmp_dir, "collector.log"), logs)
    entries = Agent.get(capture, &Enum.reverse(&1.requests))

    for {entry, i} <- Enum.with_index(entries) do
      File.write!(
        Path.join(ctx.tmp_dir, "request-#{i}-#{entry.tenant}-#{entry.status}.protobuf"),
        :zlib.gunzip(entry.body)
      )
    end

    File.write!(
      Path.join(ctx.tmp_dir, "requests.json"),
      Pulse.JSON.encode!(
        Enum.map(entries, fn entry ->
          entry
          |> Map.drop([:body, :response])
          |> Map.update!(:headers, fn headers -> headers |> Map.new() |> Map.put("authorization", "[test-redacted]") end)
        end)
      )
    )

    for entry <- entries do
      assert {"content-encoding", "gzip"} in entry.headers
      assert {"content-type", "application/x-protobuf"} in entry.headers
      assert entry.tenant in Map.keys(tokens)
    end

    alpha = Enum.filter(entries, &(&1.tenant == "alpha"))
    assert Enum.any?(alpha, &(&1.status == 429))
    assert Enum.any?(alpha, &(&1.status == 503))

    for {_body, attempts} <- Enum.group_by(alpha, &:zlib.gunzip(&1.body)) do
      assert List.last(attempts).status == 200
      assert Enum.count(attempts, &(&1.status == 200)) == 1
    end

    for tenant <- ~w(denied oversize) do
      negative = Enum.filter(entries, &(&1.tenant == tenant))
      assert length(negative) == 2
      assert length(Enum.uniq_by(negative, &:zlib.gunzip(&1.body))) == 2
      expected = if tenant == "denied", do: [401, 401], else: [200, 413]
      assert Enum.sort(Enum.map(negative, & &1.status)) == expected
    end

    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)

    for tenant <- ~w(alpha beta) do
      assert {:ok, spans} = Storage.query(:traces, tenant)
      oracle = Pulse.JSON.decode!(File.read!(Path.join(ctx.tmp_dir, "#{tenant}-oracle.json")))
      SDKBridgeAssertions.assert_spans(spans, oracle)
      sdk_wire = File.read!(Path.join(ctx.tmp_dir, "#{tenant}-sdk.protobuf"))
      assert {:ok, sdk_rows, 0} = Traces.decode_protobuf(sdk_wire)
      assert Enum.sort_by(sdk_rows, & &1.span_id) === Enum.sort_by(spans, & &1.span_id)
      assert Enum.all?(spans, &(&1.resource["deployment.environment.name"] == tenant))
      response = mcp(url(api), tenant, tokens[tenant])
      refute response.body["result"]["isError"]
      [%{"text" => text}] = response.body["result"]["content"]
      trace = Pulse.JSON.decode!(text)
      assert trace["span_count"] == 3
      assert trace["missing_parent_span_ids"] == []
      assert trace["conflicting_span_ids"] == []

      wire =
        entries
        |> Enum.filter(&(&1.tenant == tenant and &1.status == 200))
        |> Enum.map(&:zlib.gunzip(&1.body))
        |> IO.iodata_to_binary()

      File.write!(Path.join(ctx.tmp_dir, "#{tenant}-collector.protobuf"), wire)
    end

    assert [%{status: 200, response: <<10, _size, 8, 1, _rest::binary>>}] =
             Enum.filter(entries, &(&1.tenant == "partial"))

    assert {:ok, [accepted]} = Storage.query(:traces, "partial")
    assert accepted.name == "partial valid"
    assert {:ok, []} = Storage.query(:traces, "denied")
    assert {:ok, [singleton]} = Storage.query(:traces, "oversize")
    assert singleton.name == "frontend request"
    denied = mcp(url(api), "beta", tokens["alpha"])
    assert denied.body["result"]["isError"]
    assert {:ok, []} = Storage.query(:traces, "untrusted-incoming-tenant")
    IO.puts("Collector bridge artifacts: #{ctx.tmp_dir}")
  end

  defp await_deliveries(counts) do
    done? =
      Enum.all?(~w(alpha beta), &(Map.get(counts, {&1, :accepted}, 0) == 3)) and
        Enum.all?(~w(denied oversize), &(Map.get(counts, {&1, :requests}, 0) == 2)) and
        Map.get(counts, {"partial", :requests}, 0) == 1

    if !done? do
      receive do
        {:collector_request, entry} ->
          counts = Map.update(counts, {entry.tenant, :requests}, 1, &(&1 + 1))

          counts =
            if entry.status == 200 do
              {:ok, rows, _rejected} = Traces.decode_protobuf(:zlib.gunzip(entry.body))
              Map.update(counts, {entry.tenant, :accepted}, length(rows), &(&1 + length(rows)))
            else
              counts
            end

          await_deliveries(counts)
      after
        10_000 -> flunk("Collector delivery did not reach expected complete outcomes: #{inspect(counts)}")
      end
    end
  end

  defp mcp(api, tenant, token) do
    params = %{
      "name" => "get_trace",
      "arguments" => %{"tenant" => tenant, "trace_id" => "0102030405060708090a0b0c0d0e0f10"}
    }

    Req.post!(api <> "/mcp",
      json: MCPMessages.request(1, "tools/call", params),
      headers: [
        {"authorization", "Bearer #{token}"},
        {"mcp-protocol-version", MCPMessages.version()},
        {"mcp-method", "tools/call"},
        {"mcp-name", "get_trace"}
      ]
    )
  end

  defp url(server) do
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}"
  end

  defp ports(tenants) do
    sockets =
      Enum.map(tenants, fn tenant ->
        {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
        {:ok, {_ip, port}} = :inet.sockname(socket)
        {tenant, socket, "127.0.0.1:#{port}"}
      end)

    Enum.each(sockets, fn {_, socket, _} -> :gen_tcp.close(socket) end)
    Map.new(sockets, fn {tenant, _, endpoint} -> {tenant, endpoint} end)
  end

  defp config(endpoints, target) do
    receivers =
      Enum.map_join(endpoints, "", fn {name, endpoint} ->
        "  otlp/#{name}:\n    protocols:\n      grpc:\n        endpoint: #{endpoint}\n"
      end)

    exporters =
      Enum.map_join(endpoints, "", fn {name, _} ->
        token = if name == "denied", do: "token-alpha", else: "token-#{name}"

        "  otlphttp/#{name}:\n    endpoint: #{target}\n    compression: gzip\n    headers:\n      authorization: Bearer #{token}\n      x-scope-orgid: #{name}\n    sending_queue:\n      enabled: false\n    retry_on_failure:\n      initial_interval: 100ms\n      max_interval: 200ms\n      max_elapsed_time: 5s\n"
      end)

    pipelines =
      Enum.map_join(endpoints, "", fn {name, _} ->
        "    traces/#{name}:\n      receivers: [otlp/#{name}]\n      processors: []\n      exporters: [otlphttp/#{name}]\n"
      end)

    "receivers:\n#{receivers}exporters:\n#{exporters}service:\n  telemetry:\n    metrics:\n      level: none\n  pipelines:\n#{pipelines}"
  end
end
