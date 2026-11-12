defmodule Pulse.Storage.S3.ManifestBackupTest do
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestBackup
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore

  @t0 1_699_999_200 * 1_000_000_000

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
      access_key_id: "backup-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    tenant = "backup-#{System.unique_integer([:positive])}"

    {:ok, _} =
      ObjectStore.put(
        config,
        Manifest.manifest_key(tenant, "metrics"),
        IO.iodata_to_binary(Manifest.encode(Manifest.new()))
      )

    %{agent: agent, config: config, tenant: tenant}
  end

  defp append(tenant, i) do
    record = %MetricSample{
      timestamp_ns: @t0 + i * 1_000_000_000,
      value: i * 1.0,
      labels: %{"__name__" => "up", "i" => "#{i}"}
    }

    assert :ok = S3.append(:metrics, tenant, [record])
  end

  defp stored(ctx), do: Agent.get(ctx.agent, &Map.keys(&1.objects))

  defp samples(ctx),
    do: ctx.tenant |> then(&S3.query(:metrics, &1, start_ts: 0)) |> elem(1) |> Enum.map(& &1.value) |> Enum.sort()

  test "cleanup keeps objects retired after the newest backup, and a lost manifest restores from it", ctx do
    for i <- 1..3, do: append(ctx.tenant, i)
    assert {:ok, %{taken_ms: first, segments: 3}} = ManifestBackup.backup(ctx.tenant, "metrics", ctx.config)
    assert {:ok, ^first} = ManifestBackup.latest(ctx.tenant, "metrics", ctx.config)

    assert {:ok, %{merged: 3}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    sources = Enum.filter(stored(ctx), &String.contains?(&1, "-rand-"))
    assert length(sources) == 3

    # The newest backup still lists the sources as active: keep them.
    hold = ManifestBackup.hold_ms(first, 0)
    assert {:ok, 0} = MetricsCompactor.cleanup(ctx.tenant, ctx.config, now_ms: hold)
    assert Enum.all?(sources, &(&1 in stored(ctx)))

    # A backup after the retirement releases them.
    assert {:ok, %{taken_ms: second, segments: 1}} = ManifestBackup.backup(ctx.tenant, "metrics", ctx.config)
    assert {:ok, 3} = MetricsCompactor.cleanup(ctx.tenant, ctx.config, now_ms: second)
    refute Enum.any?(sources, &(&1 in stored(ctx)))

    # Written after the newest backup.
    append(ctx.tenant, 4)
    assert samples(ctx) == [1.0, 2.0, 3.0, 4.0]

    assert {:error, :manifest_exists} = ManifestBackup.restore(ctx.tenant, "metrics", ctx.config)
    :ok = ObjectStore.delete(ctx.config, Manifest.manifest_key(ctx.tenant, "metrics"))

    assert {:ok, %{segments: 2, adopted: 1}} = ManifestBackup.restore(ctx.tenant, "metrics", ctx.config)
    # A format-4 root is backed up and restored as itself, not flattened.
    assert {:ok, %Manifest{version: 4} = restored, _etag} = Retention.load(ctx.tenant, "metrics", ctx.config)
    assert JournalManifest.referenced(restored) == 2
    assert samples(ctx) == [1.0, 2.0, 3.0, 4.0]
  end

  test "without a backup nothing is deleted" do
    assert ManifestBackup.hold_ms(nil, 3_600_000) == 0
    now = System.system_time(:millisecond)
    assert ManifestBackup.hold_ms(now - 7_200_000, 3_600_000) == now - 3_600_001
  end

  test "only the newest backups are kept", ctx do
    append(ctx.tenant, 1)

    for _ <- 1..3 do
      assert {:ok, _} = ManifestBackup.backup(ctx.tenant, "metrics", ctx.config, keep: 2)
      Process.sleep(2)
    end

    assert {:ok, keys} = ObjectStore.list(ctx.config, ManifestBackup.prefix(ctx.tenant, "metrics"))
    assert length(keys) == 2
  end
end
