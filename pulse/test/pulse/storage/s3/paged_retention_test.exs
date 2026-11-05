defmodule Pulse.Storage.S3.PagedRetentionTest do
  @moduledoc """
  Enforced retention on format-4 (paged) manifests: the default
  `retention_manifest_format`, which keeps manifest backups and hour
  finalization working.
  """
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestBackup
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.PagedManifest
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore

  @day 86_400_000_000_000
  @hour 3_600_000_000_000

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
      access_key_id: "paged-retention-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    tenant = "paged-retention-#{System.unique_integer([:positive])}"

    # Zero graces: expired segments are due as soon as a backup records them.
    retention =
      Map.merge(config, %{
        metrics_retention_days: 30,
        logs_retention_days: 30,
        retention_mode: "enforce",
        retention_delete_grace_ms: 0,
        compaction_options: [grace_ms: 0],
        manifest_page_grace_ms: 0
      })

    %{agent: agent, config: config, retention: retention, tenant: tenant, now: System.os_time(:nanosecond)}
  end

  defp append(tenant, ts, value) do
    record = %MetricSample{timestamp_ns: ts, value: value, labels: %{"__name__" => "up", "v" => "#{value}"}}
    S3.append(:metrics, tenant, [record])
  end

  defp stored(ctx), do: Agent.get(ctx.agent, &Map.keys(&1.objects))
  defp root(ctx, signal \\ "metrics"), do: ctx.tenant |> Retention.load(signal, ctx.config) |> elem(1)

  defp values(ctx) do
    {:ok, samples} = S3.query(:metrics, ctx.tenant, start_ts: 0)
    samples |> Enum.map(& &1.value) |> Enum.sort()
  end

  defp segment_keys(ctx), do: Enum.filter(stored(ctx), &String.ends_with?(&1, ".parquet"))

  # Deadlines a second in the past, so a backup taken right after the
  # retirement already releases it.
  defp advance(ctx, signal \\ "metrics"),
    do: Retention.advance(ctx.tenant, signal, ctx.retention, now_ms: System.system_time(:millisecond) - 1000)

  test "enforced retention keeps format 4, hides and deletes expired segments, and backups still restore", ctx do
    for {age, value} <- [{40 * @day, 1.0}, {35 * @day, 2.0}, {31 * @day, 3.0}, {2 * @hour, 4.0}, {@hour, 5.0}],
        do: assert(:ok = append(ctx.tenant, ctx.now - age, value))

    assert %Manifest{version: 4} = root(ctx)
    expired = segment_keys(ctx)
    assert length(expired) == 5
    assert values(ctx) == [1.0, 2.0, 3.0, 4.0, 5.0]

    # Enabling enforcement on an existing format-4 prefix converts nothing.
    assert {:ok, %{format: 4, retired: 3, floor_ns: floor}} = advance(ctx)
    assert floor <= ctx.now - 30 * @day and floor > ctx.now - 30 * @day - @hour
    assert %Manifest{version: 4} = root = root(ctx)
    assert Retention.retention_floor(root) == floor
    assert {:ok, false} = PagedManifest.managed?(ctx.config, ctx.tenant, "metrics")

    # Hidden at once, deleted only after a backup records the retirement.
    assert values(ctx) == [4.0, 5.0]
    assert length(segment_keys(ctx)) == 5
    assert {:ok, 3} = Retention.cleanup_retired(ctx.tenant, "metrics", ctx.retention)
    assert length(segment_keys(ctx)) == 2
    assert {:ok, taken} = ManifestBackup.latest(ctx.tenant, "metrics", ctx.config)
    assert is_integer(taken)

    # The newest backup restores without referencing a deleted object.
    :ok = ObjectStore.delete(ctx.config, Manifest.manifest_key(ctx.tenant, "metrics"))
    assert {:ok, %{segments: 2, adopted: 0}} = ManifestBackup.restore(ctx.tenant, "metrics", ctx.config)
    restored = root(ctx)
    assert Enum.all?(restored.segments, &(&1.key in stored(ctx)))
    assert values(ctx) == [4.0, 5.0]

    # The next pass puts the floor back on the restored root.
    assert {:ok, %{format: 4, retired: 0, floor_ns: ^floor}} = advance(ctx)
    assert values(ctx) == [4.0, 5.0]
  end

  test "deletions wait for a backup taken after the retirement", ctx do
    assert :ok = append(ctx.tenant, ctx.now - @hour, 1.0)
    assert {:ok, %{taken_ms: _}} = ManifestBackup.backup(ctx.tenant, "metrics", ctx.config)
    assert :ok = append(ctx.tenant, ctx.now - 40 * @day, 2.0)

    # Retired after the newest backup, which still lists it as active.
    assert {:ok, %{retired: 1}} = Retention.advance(ctx.tenant, "metrics", ctx.retention)
    assert {:ok, 0} = Retention.cleanup_retired(ctx.tenant, "metrics", ctx.retention)
    assert length(segment_keys(ctx)) == 2
  end

  test "ingest rejects records below the floor and converts a flat prefix to format 4, not format 3", ctx do
    Runtime.put_env(:pulse, S3, ctx.retention)
    assert :ok = append(ctx.tenant, ctx.now - @hour, 1.0)
    assert %Manifest{version: 4} = root(ctx)
    assert {:ok, %{format: 4}} = advance(ctx)

    assert {:error, :retention_expired} = append(ctx.tenant, ctx.now - 31 * @day, 2.0)
    assert {:error, :timestamp_too_new} = append(ctx.tenant, ctx.now + @day, 3.0)
    assert :ok = append(ctx.tenant, ctx.now - 29 * @day, 4.0)
    assert values(ctx) == [1.0, 4.0]
    assert {:ok, false} = PagedManifest.managed?(ctx.config, ctx.tenant, "metrics")
  end

  test "hour finalization keeps working under enforced retention and skips expired hours", ctx do
    hour = div(ctx.now, @hour) * @hour - 2 * @hour
    old = div(ctx.now - 40 * @day, @hour) * @hour

    for {ts, value} <- [{old + 60, 1.0}, {hour + 60, 2.0}, {hour + 120, 3.0}],
        do: assert(:ok = append(ctx.tenant, ts, value))

    assert {:ok, %{format: 4}} = advance(ctx)
    opts = [settle_ms: 0, grace_ms: 0]
    assert {:ok, %{hour: ^hour, sources: 2}} = MetricTiers.finalize(ctx.tenant, ctx.retention, opts)
    assert {:ok, %{hour: nil}} = MetricTiers.finalize(ctx.tenant, ctx.retention, opts)
    assert %Manifest{version: 4} = root(ctx)
    assert values(ctx) == [2.0, 3.0]
  end

  test "expired pages are rewritten in bounded passes and dropped once cleanup forgets them", ctx do
    scope = JournalManifest.scope(ctx.tenant, "logs")
    old = ctx.now - 60 * @day

    segment = fn i, ts ->
      key = scope <> "date=x/hour=00/#{pad(ts)}-#{pad(ts + 1)}-rand-#{i}.parquet"
      Segment.build(key, ts, ts + 1, 1, 100)
    end

    expired = for i <- 1..1300, do: segment.(i, old + i * 1_000_000)
    recent = for i <- 1..5, do: segment.(10_000 + i, ctx.now - i * @hour)
    flat = %{Manifest.new() | version: 2, segments: expired ++ recent}
    {:ok, root} = JournalManifest.convert(flat, ctx.tenant, "logs", ctx.config)
    {:ok, _} = ObjectStore.put(ctx.config, Manifest.manifest_key(ctx.tenant, "logs"), encode(root))
    assert length(root.paging["refs"]) == 3

    # One leaf per pass.
    retention = Map.put(ctx.retention, :retention_expiry_leaves, 1)
    passes = for _ <- 1..4, do: Retention.advance(ctx.tenant, "logs", retention, now_ms: 0)
    assert Enum.map(passes, fn {:ok, r} -> r.retired end) |> Enum.sum() == 1300
    assert JournalManifest.referenced(root(ctx, "logs")) == 5

    assert {:ok, 1300} = Retention.cleanup_retired(ctx.tenant, "logs", ctx.retention, max_deletions: 2048)
    assert {:ok, %{retired: 0}} = Retention.advance(ctx.tenant, "logs", ctx.retention)

    # Every expired leaf is gone; only the recent one remains, and the pages
    # it superseded await deletion.
    after_drop = root(ctx, "logs")
    assert [%{"n" => 5}] = after_drop.paging["refs"]
    assert after_drop.paging["g"] != []
    assert JournalManifest.referenced(after_drop) == 5
  end

  defp encode(root), do: root |> Manifest.encode() |> IO.iodata_to_binary()

  defp pad(ts), do: ts |> Integer.to_string() |> String.pad_leading(20, "0")
end
