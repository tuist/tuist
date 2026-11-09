defmodule Pulse.Storage.S3.MaintenancePublicationTest do
  @moduledoc """
  Maintenance of format-4 manifests (compaction, cleanup) writes its manifest
  pages outside the manifest owner, so ingest publications of the same prefix
  never wait on page I/O. With pages written inside the owner, one maintenance
  publication held every append of the prefix for a page round trip per
  rewritten page, past the 19 s ingest timeout on a busy prefix.

  Backups of format-4 manifests copy the root instead of materializing every
  page, and cleanup holds the pages a backup references.
  """
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestBackup
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore

  @t0 1_700_000_000_000_000_000

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
      access_key_id: "maintenance-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      manifest_page_grace_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    %{agent: agent, config: config, tenant: "maintenance-#{System.unique_integer([:positive])}"}
  end

  # 600 one-sample segments, sharing one stored object body, published in one
  # registration: the tail spills them into leaf pages.
  defp paged_history(ctx) do
    sample = %MetricSample{timestamp_ns: @t0, value: 1.0, labels: %{"__name__" => "up"}}
    {:ok, body, _min, _max} = S3.encode_segment(:metrics, [sample])

    segments =
      for i <- 1..600 do
        key = S3.object_key(ctx.tenant, "metrics", @t0, @t0, "h#{i}", nil)
        Segment.build(key, @t0, @t0, 1, byte_size(body))
      end

    # Registered before upload, so creating the manifest lists no objects.
    assert :ok = ManifestOwner.register_segments(ctx.tenant, "metrics", segments, ctx.config)
    Enum.each(segments, &({:ok, _} = ObjectStore.put(ctx.config, &1.key, body)))
    assert {:ok, %Manifest{version: 4, segments: []} = root, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    assert JournalManifest.referenced(root) == 600
    segments
  end

  defp append(ctx, i) do
    record = %MetricSample{timestamp_ns: @t0 + i, value: 2.0, labels: %{"__name__" => "fresh", "i" => "#{i}"}}
    S3.append(:metrics, ctx.tenant, [record])
  end

  defp hold_pages(ctx) do
    test = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", :page} => test}})
  end

  # While maintenance waits on a manifest page write, an append publishes.
  defp assert_ingest_proceeds(ctx, maintenance) do
    assert_receive {:storage_barrier, server, "PUT", page}, 10_000
    ingest = Task.async(fn -> append(ctx, 1) end)
    published = Task.yield(ingest, 5_000)

    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    send(server, {:release_storage, page})
    release_held()
    result = Task.await(maintenance, 30_000)

    assert published == {:ok, :ok}, "ingest waited for maintenance page I/O"
    result
  end

  defp release_held do
    receive do
      {:storage_barrier, server, _method, key} ->
        send(server, {:release_storage, key})
        release_held()
    after
      100 -> :ok
    end
  end

  test "compaction of paged sources writes its pages outside the manifest owner", ctx do
    paged_history(ctx)
    hold_pages(ctx)

    compaction = Task.async(fn -> MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0) end)
    assert {:ok, %{merged: 32}} = assert_ingest_proceeds(ctx, compaction)

    # Both publications landed: the merge and the concurrent append.
    {:ok, root, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    assert JournalManifest.referenced(root) == 600 - 32 + 1 + 1
  end

  test "cleanup of paged retirements writes its pages outside the manifest owner", ctx do
    paged_history(ctx)
    assert {:ok, %{merged: 32}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    hold_pages(ctx)

    cleanup = Task.async(fn -> MetricsCompactor.cleanup(ctx.tenant, ctx.config) end)
    assert {:ok, 32} = assert_ingest_proceeds(ctx, cleanup)

    # Every retirement is recorded as deleted: a second pass has nothing to do.
    assert {:ok, 0} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
  end

  defp root_puts(ctx) do
    ctx.agent
    |> Agent.get(& &1.requests)
    |> Enum.count(fn {method, key} -> method == "PUT" and String.ends_with?(key, "/manifest.json") end)
  end

  # With spaced publications (the ingest window), a maintenance change waits
  # for the next publication and shares its root write with the appends and
  # changes queued by then. Each used to write the root on its own.
  defp await_queued(ctx) do
    {:ok, owner} = ManifestOwner.ensure_started(ctx.tenant, "metrics", ctx.config)

    if :sys.get_state(owner).transactions == [] do
      Process.sleep(10)
      await_queued(ctx)
    end
  end

  defp spaced(ctx), do: %{ctx | config: Map.put(ctx.config, :ingest_flush_interval_ms, 1_000)}

  test "a merge and concurrent appends share one root write per ingest window", ctx do
    ctx = spaced(ctx)
    Runtime.put_env(:pulse, S3, ctx.config)
    paged_history(ctx)
    # A first append starts a window; the rest of the work falls inside it.
    assert :ok = append(ctx, 1)
    Agent.update(ctx.agent, &%{&1 | requests: []})

    compaction = Task.async(fn -> MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0) end)
    await_queued(ctx)
    work = [compaction, Task.async(fn -> append(ctx, 2) end), Task.async(fn -> append(ctx, 3) end)]
    assert [{:ok, %{merged: 32}}, :ok, :ok] = Enum.map(work, &Task.await(&1, 30_000))
    assert root_puts(ctx) == 1

    {:ok, root, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    # Appends 2 and 3 may share one coalesced segment.
    assert JournalManifest.referenced(root) in (600 - 32 + 1 + 2)..(600 - 32 + 1 + 3)

    # The cleanup of the merge's sources folds into a later window too.
    Agent.update(ctx.agent, &%{&1 | requests: []})
    assert {:ok, 32} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert root_puts(ctx) == 1
    assert {:ok, 0} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
  end

  test "a folded maintenance change is applied again after another writer's root write", ctx do
    ctx = spaced(ctx)
    Runtime.put_env(:pulse, S3, ctx.config)
    paged_history(ctx)
    assert :ok = append(ctx, 1)

    # Another instance republishes the root just before this owner's write.
    key = Manifest.manifest_key(ctx.tenant, "metrics")

    Agent.update(ctx.agent, fn state ->
      hook = fn state ->
        {_etag, body} = Map.fetch!(state.objects, key)
        etag = "\"#{state.version + 1}\""
        %{state | objects: Map.put(state.objects, key, {etag, body}), version: state.version + 1}
      end

      %{state | hook: hook}
    end)

    compaction = Task.async(fn -> MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0) end)
    await_queued(ctx)
    work = [compaction, Task.async(fn -> append(ctx, 2) end)]

    assert [{:ok, %{merged: 32}}, :ok] = Enum.map(work, &Task.await(&1, 30_000))
    assert Agent.get(ctx.agent, &Map.get(&1, :manifest_conflicts, 0)) == 1
    {:ok, root, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    assert JournalManifest.referenced(root) == 600 - 32 + 1 + 2
  end

  test "a format-4 backup copies the root, and cleanup keeps the pages it references", ctx do
    paged_history(ctx)
    assert {:ok, %{key: key, taken_ms: taken, segments: 600}} = ManifestBackup.backup(ctx.tenant, "metrics", ctx.config)

    # One small object however long the history: materializing every page
    # into one flat copy read hundreds of pages and outgrew maintenance heaps.
    {:ok, body} = ObjectStore.get(ctx.config, key)
    assert byte_size(body) < 4096
    assert {:ok, %Manifest{version: 4} = backed_up} = Manifest.decode(body)
    {:ok, pages} = JournalManifest.page_keys(backed_up, ctx.tenant, "metrics", ctx.config)

    # Compaction supersedes the leaves the backup references. Their page grace
    # (0) is shorter than the compaction grace, yet the hold keeps them.
    assert {:ok, %{merged: 32}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 3_600_000)
    hold = ManifestBackup.hold_ms(taken, 3_600_000, ctx.config)
    assert {:ok, 0} = MetricsCompactor.cleanup(ctx.tenant, ctx.config, now_ms: hold)
    stored = Agent.get(ctx.agent, &Map.keys(&1.objects))
    assert pages != [] and Enum.all?(pages, &(&1 in stored))

    :ok = ObjectStore.delete(ctx.config, Manifest.manifest_key(ctx.tenant, "metrics"))
    assert {:ok, %{segments: 600, adopted: 0}} = ManifestBackup.restore(ctx.tenant, "metrics", ctx.config)
  end
end
