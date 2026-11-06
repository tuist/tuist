defmodule Pulse.Test.SDKIngestHarness do
  @moduledoc false
  import Pulse.Test.Case, only: [start_supervised!: 1]

  alias Pulse.Auth.SharedSecret
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Test.CollectorBridgeTap
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.ExternalCommand
  alias Pulse.Test.MCPMessages
  alias Pulse.Test.RuntimePlug
  alias Pulse.Traces.TempoSearch

  def start!(tmp_dir, tenants) do
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
    {:ok, {_, store_port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "sdk-fixture",
      region: "us-east-1",
      endpoint: "http://127.0.0.1:#{store_port}",
      access_key_id: tmp_dir,
      secret_access_key: "fixture",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, S3, config)

    hashes =
      Map.new(
        tenants,
        &{&1,
         "sha256$" <>
           Base.encode16(:crypto.hash(:sha256, if(&1 == "denied", do: "not-the-producer-token", else: "token-#{&1}")),
             case: :lower
           )}
      )

    Runtime.put_env(:pulse, Pulse.Auth, module: SharedSecret, tokens: hashes)
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    manifest = start_supervised!(S3.ManifestSupervision)
    runtime = Runtime.current()

    api =
      start_supervised!(
        Supervisor.child_spec(
          {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: runtime}, ip: {127, 0, 0, 1}, port: 0},
          id: :sdk_api
        )
      )

    {:ok, {_, api_port}} = ThousandIsland.listener_info(api)
    limited = %{runtime | configs: Map.put(runtime.configs, {:pulse, Pulse.IngestLimits}, max_records: 1)}

    small =
      start_supervised!(
        Supervisor.child_spec(
          {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: limited}, ip: {127, 0, 0, 1}, port: 0},
          id: :sdk_small
        )
      )

    {:ok, {_, small_port}} = ThousandIsland.listener_info(small)
    owner = self()

    capture =
      start_supervised!(
        Supervisor.child_spec(
          {Agent, fn -> %{owner: owner, requests: [], failures: %{"unavailable" => [503], "rate" => [429]}} end},
          id: :sdk_capture
        )
      )

    targets = Map.new(tenants, &{&1, "http://127.0.0.1:#{if(&1 == "oversize", do: small_port, else: api_port)}"})

    tap =
      start_supervised!(
        Supervisor.child_spec(
          {Bandit, plug: {CollectorBridgeTap, agent: capture, targets: targets}, ip: {127, 0, 0, 1}, port: 0},
          id: :sdk_tap
        )
      )

    {:ok, {_, tap_port}} = ThousandIsland.listener_info(tap)

    %{
      api: "http://127.0.0.1:#{api_port}",
      tap: "http://127.0.0.1:#{tap_port}",
      capture: capture,
      tmp_dir: tmp_dir,
      manifest: manifest,
      runtime: runtime,
      store: store
    }
  end

  def collector!(harness, binary, tenant) do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, active: false)
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)

    config = """
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 127.0.0.1:#{port}
    exporters:
      otlphttp:
        endpoint: #{harness.tap}/#{tenant}
        compression: gzip
        headers:
          authorization: Bearer token-#{tenant}
          x-scope-orgid: #{tenant}
        sending_queue:
          enabled: false
        retry_on_failure:
          enabled: false
    service:
      telemetry:
        metrics:
          level: none
      pipelines:
        traces:
          receivers: [otlp]
          exporters: [otlphttp]
    """

    path = Path.join(harness.tmp_dir, "elixir-collector.yaml")
    File.write!(path, config)

    process =
      start_supervised!(
        Supervisor.child_spec({ExternalCommand, path: binary, args: ["--config", path]}, id: :sdk_collector)
      )

    :ok = ExternalCommand.ready(process)
    {process, "http://127.0.0.1:#{port}"}
  end

  def mcp!(harness, tenant, tool, arguments) do
    response =
      Req.post!(harness.api <> "/mcp",
        headers:
          headers(tenant) ++ [{"mcp-protocol-version", "2026-07-28"}, {"mcp-method", "tools/call"}, {"mcp-name", tool}],
        json:
          MCPMessages.request(1, "tools/call", %{
            "name" => tool,
            "arguments" => Map.put_new(arguments, "tenant", tenant)
          })
      )

    response.body
  end

  def headers(tenant), do: [{"authorization", "Bearer token-#{tenant}"}, {"x-scope-orgid", tenant}]
end
