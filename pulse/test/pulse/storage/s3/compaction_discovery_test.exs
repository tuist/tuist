defmodule Pulse.Storage.S3.CompactionDiscoveryTest do
  # Every maintenance lane discovers tenants each pass. The durable listing
  # is a billed LIST, so it is reused for an interval; tenants this node has
  # cached manifests for are found on every pass without one.
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.CompactionDiscovery
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore

  setup do
    agent =
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

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: agent}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "discovery-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    %{agent: agent, config: config}
  end

  test "the durable tenant listing is reused within the discovery interval", ctx do
    {:ok, _} = ObjectStore.put(ctx.config, "tenants/dormant/v4/signal=metrics/manifest.json", "{}")
    lists = fn -> Agent.get(ctx.agent, & &1.lists) end

    assert {:ok, ["dormant"]} = CompactionDiscovery.tenants(ctx.config)
    assert lists.() == 1

    # A tenant ingested here appears at once; one written elsewhere waits for
    # the next listing.
    ManifestCache.put("local", "logs", Manifest.new(), "etag")
    {:ok, _} = ObjectStore.put(ctx.config, "tenants/remote/v4/signal=metrics/manifest.json", "{}")
    for _ <- 1..5, do: assert({:ok, ["dormant", "local"]} = CompactionDiscovery.tenants(ctx.config))
    assert lists.() == 1

    expired = Map.put(ctx.config, :compaction_discovery_interval_ms, 0)
    assert {:ok, ["dormant", "local", "remote"]} = CompactionDiscovery.tenants(expired)
    assert lists.() == 2
  end
end
