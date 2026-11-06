defmodule Pulse.Storage.S3.RetentionTest do
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Runtime.Registry
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestRegistry
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetadataCache
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Storage.S3.PagedManifest
  alias Pulse.Storage.S3.Retention
  alias Pulse.Storage.S3.RetentionSupervision
  alias Pulse.Storage.S3.RetentionTasks
  alias Pulse.Storage.S3.RetentionWorker
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
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "test",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      retention_enabled: true,
      logs_retention_days: 1,
      metrics_retention_days: 1,
      retention_mode: "enforce",
      retention_manifest_format: "bucketed",
      retention_delete_grace_ms: 5,
      retention_interval_ms: 1,
      retention_tail_entries: 2
    }

    Runtime.put_env(:pulse, S3, config)

    start_supervised!(ManifestSupervision)
    tenant = "retention-#{System.unique_integer([:positive])}"
    %{agent: agent, config: config, tenant: tenant, now: System.system_time(:nanosecond)}
  end

  defp sample(ts, value \\ 1.0),
    do: %MetricSample{timestamp_ns: ts, value: value, labels: %{"__name__" => "requests", "service" => "api"}}

  defp root(ctx, signal \\ "metrics") do
    assert {:ok, root, _} = Retention.load(ctx.tenant, signal, ctx.config)
    root
  end

  defp objects(ctx), do: Agent.get(ctx.agent, & &1.objects)

  defp seed(ctx, signal, manifest) do
    assert {:ok, _} =
             ObjectStore.put(
               ctx.config,
               Manifest.manifest_key(ctx.tenant, signal),
               IO.iodata_to_binary(Manifest.encode(manifest))
             )
  end

  defp expire(ctx, shift \\ 2 * @day) do
    now = ctx.now + shift
    assert {:ok, _} = Retention.advance(ctx.tenant, "metrics", ctx.config, now_ns: now, now_ms: div(now, 1_000_000))
    div(now, 1_000_000) + 10
  end

  defp unconfigured(ctx) do
    config =
      ctx.config
      |> Map.put(:retention_enabled, false)
      |> Map.put(:logs_retention_days, 0)
      |> Map.put(:metrics_retention_days, 0)
      |> Map.put(:retention_mode, "observe")

    Runtime.put_env(:pulse, S3, config)
    config
  end

  defp fail_reads(ctx, keys),
    do: Agent.update(ctx.agent, &%{&1 | faults: Map.new(keys, fn key -> {{"GET", key}, {403, :before, 100}} end)})

  defp manifest_reads(ctx, key), do: Agent.get(ctx.agent, &Enum.count(&1.requests, fn r -> r == {"GET", key} end))

  defp clean(ctx, now, passes \\ 16) do
    for _ <- 1..passes, do: assert(match?({:ok, _}, Retention.cleanup(ctx.tenant, "metrics", ctx.config, now_ms: now)))
  end

  test "bounded native GET and start-after LIST survive deletion", ctx do
    for n <- 1..5, do: assert(match?({:ok, _}, ObjectStore.put(ctx.config, "pages/#{n}", "payload")))
    assert {:error, :response_too_large} = ObjectStore.get_bounded(ctx.config, "pages/1", nil, 6)
    assert {:ok, etag, "payload"} = ObjectStore.get_bounded(ctx.config, "pages/1", nil, 7)
    assert :not_modified = ObjectStore.get_bounded(ctx.config, "pages/1", etag, 7)
    assert {:ok, ["pages/1", "pages/2"], "pages/2"} = ObjectStore.list_page(ctx.config, "pages/", nil, 2)
    assert :ok = ObjectStore.delete(ctx.config, "pages/1")
    assert :ok = ObjectStore.delete(ctx.config, "pages/2")
    assert {:ok, ["pages/3", "pages/4"], "pages/4"} = ObjectStore.list_page(ctx.config, "pages/", "pages/2", 2)
    assert {:ok, ["pages/5"], nil} = ObjectStore.list_page(ctx.config, "pages/", "pages/4", 2)
  end

  test "tenant discovery jumps over telemetry, includes dormant and dotted tenants", ctx do
    for tenant <- ["a", "a.", "a0", "z"] do
      for n <- 1..8, do: assert(match?({:ok, _}, ObjectStore.put(ctx.config, "tenants/#{tenant}/date/#{n}", "")))
    end

    assert {:ok, ["a.", "a"], "a"} = ObjectStore.discover_tenants(ctx.config, nil, 2)
    assert {:ok, ["a0", "z"], "z"} = ObjectStore.discover_tenants(ctx.config, "a", 2)
    assert {:ok, [], nil} = ObjectStore.discover_tenants(ctx.config, "z", 2)
  end

  test "first enforce rejects expired, missing and future timestamps before segment PUT", ctx do
    assert {:error, :retention_expired} = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: ctx.now - 2 * @day}])
    assert {:error, :retention_expired} = S3.append(:logs, ctx.tenant, [%Log{}])
    assert {:error, :timestamp_too_new} = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: ctx.now + @hour}])
    assert root(ctx, "logs").version == 3
    assert Map.has_key?(objects(ctx), PagedManifest.marker(ctx.tenant, "logs"))
    refute Enum.any?(Map.keys(objects(ctx)), &String.ends_with?(&1, ".parquet"))
  end

  test "inline tail spills and idempotent retries find paged entries", ctx do
    for n <- 1..5 do
      assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now + n, n / 1)], idempotency_key: "batch-#{n}")
    end

    for n <- 1..5 do
      assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now + n, n / 1)], idempotency_key: "batch-#{n}")
    end

    manifest = root(ctx)
    assert length(manifest.segments) <= 1
    assert length(manifest.paging["buckets"]) == 1
    assert byte_size(IO.iodata_to_binary(Manifest.encode(manifest))) <= PagedManifest.root_limit()
    assert {:ok, rows} = S3.query(:metrics, ctx.tenant, [])
    assert Enum.sort(Enum.map(rows, & &1.value)) == [1.0, 2.0, 3.0, 4.0, 5.0]
  end

  test "conversion folds expired lifetime hours into bounded closed GC work", ctx do
    segments =
      for n <- 1..100 do
        ts = ctx.now - n * 7 * @day
        key = S3.object_key(ctx.tenant, "metrics", ts, ts, "old#{n}", nil)
        assert {:ok, _} = ObjectStore.put(ctx.config, key, "old")
        Segment.build(key, ts, ts, 1, 3)
      end

    seed(ctx, "metrics", Manifest.merge(Manifest.new(), segments))
    assert {:ok, _} = Retention.advance(ctx.tenant, "metrics", ctx.config)
    manifest = root(ctx)
    assert length(manifest.paging["buckets"]) == 1
    assert hd(manifest.paging["buckets"])["legacy_gc"]
    assert {:ok, []} = S3.query(:metrics, ctx.tenant, [])
    clean(ctx, hd(manifest.paging["buckets"])["deadline"] + 100)
    assert root(ctx).paging["buckets"] == []
    refute Enum.any?(Map.keys(objects(ctx)), &String.ends_with?(&1, ".parquet"))
  end

  test "floor is inclusive, clips spanning segments, and cannot be rewound", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now - 23 * @hour, 1.0), sample(ctx.now, 2.0)])
    advanced = ctx.now + 2 * @hour
    assert {:ok, _} = Retention.advance(ctx.tenant, "metrics", ctx.config, now_ns: advanced)
    floor = root(ctx).paging["floor"]
    assert {:ok, [new]} = S3.query(:metrics, ctx.tenant, [])
    assert new.value == 2.0
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(floor, 3.0)])
    assert {:error, :retention_expired} = S3.append(:metrics, ctx.tenant, [sample(floor - 1), sample(ctx.now)])
    assert {:ok, :ok} = Retention.apply_policy(ctx.tenant, "metrics", ctx.config, 1, 2)
    config = Map.put(ctx.config, :metrics_retention_days, 2)
    assert {:ok, _} = Retention.advance(ctx.tenant, "metrics", config, now_ns: advanced)
    assert root(ctx).paging["floor"] == floor
    Agent.update(ctx.agent, &%{&1 | reads: []})
    assert {:ok, []} = S3.query(:metrics, ctx.tenant, end_ts: floor - 1)

    refute Agent.get(
             ctx.agent,
             &Enum.any?(&1.reads, fn k -> String.ends_with?(k, ".parquet") or String.contains?(k, "/index/") end)
           )
  end

  test "teardown preserves grace and deletes data before metadata; restart needs no deleted index", ctx do
    for n <- 1..3, do: assert(:ok == S3.append(:metrics, ctx.tenant, [sample(ctx.now + n)]))
    now = expire(ctx)
    assert {:ok, 0} = Retention.cleanup(ctx.tenant, "metrics", ctx.config, now_ms: now - 10)
    assert Agent.get(ctx.agent, & &1.deletes) == []
    clean(ctx, now)
    assert root(ctx).paging["buckets"] == []
    deleted = Agent.get(ctx.agent, &Enum.reverse(&1.deletes))
    data = Enum.with_index(deleted) |> Enum.filter(fn {k, _} -> String.ends_with?(k, ".parquet") end)
    pages = Enum.with_index(deleted) |> Enum.filter(fn {k, _} -> String.contains?(k, "/index/") end)
    assert length(data) == 3
    assert Enum.max(Enum.map(data, &elem(&1, 1))) < Enum.min(Enum.map(pages, &elem(&1, 1)))
    assert {:ok, 0} = Retention.cleanup(ctx.tenant, "metrics", ctx.config, now_ms: now)
    assert map_size(objects(ctx)) == 2
  end

  test "paused stops deletes; observe finishes committed teardown", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    now = expire(ctx)
    paused = Map.put(ctx.config, :retention_mode, "paused")
    assert {:ok, 0} = Retention.cleanup(ctx.tenant, "metrics", paused, now_ms: now)
    assert Agent.get(ctx.agent, & &1.deletes) == []
    observed = %{ctx | config: Map.put(ctx.config, :retention_mode, "observe")}
    clean(observed, now)
    assert root(ctx).paging["buckets"] == []
    assert {:error, :retention_expired} = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
  end

  test "failed deletion does not block another bucket or erase its retry", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now - 5 * @hour)])
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    key = Map.keys(objects(ctx)) |> Enum.filter(&String.ends_with?(&1, ".parquet")) |> Enum.min()
    Agent.update(ctx.agent, &%{&1 | faults: %{{"DELETE", key} => {403, :before, 100}}})
    now = expire(ctx)
    clean(ctx, now, 12)
    assert Map.has_key?(objects(ctx), key)
    assert length(root(ctx).paging["buckets"]) == 1
    Agent.update(ctx.agent, &%{&1 | faults: %{}})
    clean(ctx, now)
    assert root(ctx).paging["buckets"] == []
    refute Map.has_key?(objects(ctx), key)
  end

  test "managed missing root never lists or recreates, including cold-cache paths", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    assert :ok = ObjectStore.delete(ctx.config, Manifest.manifest_key(ctx.tenant, "metrics"))
    ManifestCache.drop(ctx.tenant, "metrics")
    initial = Agent.get(ctx.agent, & &1.lists)
    assert {:error, :managed_manifest_missing} = S3.query(:metrics, ctx.tenant, [])
    assert {:error, :managed_manifest_missing} = S3.append(:metrics, ctx.tenant, [sample(ctx.now + 1)])
    assert Agent.get(ctx.agent, & &1.lists) == initial
    refute Map.has_key?(objects(ctx), Manifest.manifest_key(ctx.tenant, "metrics"))
  end

  test "queries fail closed on a stale managed root refresh", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    assert {:ok, [_]} = S3.query(:metrics, ctx.tenant, [])

    Agent.update(
      ctx.agent,
      &%{&1 | faults: %{{"GET", Manifest.manifest_key(ctx.tenant, "metrics")} => {403, :before, 2}}}
    )

    assert {:error, _} = S3.query(:metrics, ctx.tenant, [])
  end

  test "unconfigured nodes serve a cached legacy snapshot when root and marker reads both fail", ctx do
    unconfigured(ctx)
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    assert {:ok, [_]} = S3.query(:metrics, ctx.tenant, [])
    fail_reads(ctx, [Manifest.manifest_key(ctx.tenant, "metrics"), PagedManifest.marker(ctx.tenant, "metrics")])
    assert {:ok, [_]} = S3.query(:metrics, ctx.tenant, [])
  end

  test "cold marker probe errors are advisory but the owner's create fence stays closed", ctx do
    unconfigured(ctx)
    marker = PagedManifest.marker(ctx.tenant, "metrics")
    key = Manifest.manifest_key(ctx.tenant, "metrics")

    # Only the preflight probe fails; the owner's own marker check succeeds.
    Agent.update(ctx.agent, &%{&1 | faults: %{{"GET", marker} => {403, :before, 1}}})
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])

    other = %{ctx | tenant: ctx.tenant <> "-fenced"}
    fail_reads(other, [PagedManifest.marker(other.tenant, "metrics")])
    assert {:error, _} = S3.append(:metrics, other.tenant, [sample(ctx.now)])
    refute Map.has_key?(objects(ctx), Manifest.manifest_key(other.tenant, "metrics"))
    assert Map.has_key?(objects(ctx), key)
  end

  test "observe serves stale legacy snapshots and skips root reads on ingest; enforce fails closed", ctx do
    observe = Map.put(ctx.config, :retention_mode, "observe")
    Runtime.put_env(:pulse, S3, observe)
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    assert root(ctx).version != 3

    reads = manifest_reads(ctx, key)
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now + 1)])
    assert manifest_reads(ctx, key) == reads

    fail_reads(ctx, [key, PagedManifest.marker(ctx.tenant, "metrics")])
    assert {:ok, [_, _]} = S3.query(:metrics, ctx.tenant, [])

    Runtime.put_env(:pulse, S3, ctx.config)
    assert {:error, _} = S3.query(:metrics, ctx.tenant, [])
  end

  test "a legacy CAS conflict retries from the read-back root without a second GET", ctx do
    unconfigured(ctx)
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])

    Agent.update(ctx.agent, fn state ->
      %{
        state
        | hook: fn state ->
            {_, body} = Map.fetch!(state.objects, key)
            %{state | objects: Map.put(state.objects, key, {"\"concurrent\"", body})}
          end
      }
    end)

    reads = manifest_reads(ctx, key)
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now + 1)])
    assert manifest_reads(ctx, key) == reads + 1
    assert {:ok, [_, _]} = S3.query(:metrics, ctx.tenant, [])
  end

  test "a caller deadline that expires during metadata reads is a query timeout", ctx do
    for n <- 1..12, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now + n)]))
    expired = System.monotonic_time(:millisecond) - 1
    assert {:error, :query_timeout} = S3.query(:metrics, ctx.tenant, deadline_ms: expired)

    # Restart the caches so the query must read pages, then hold the first
    # page read until the caller's deadline has passed.
    stop_supervised!(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    manifest = Manifest.manifest_key(ctx.tenant, "metrics")

    pages =
      for key <- Map.keys(objects(ctx)),
          String.contains?(key, ctx.tenant) and String.ends_with?(key, ".json") and key != manifest,
          into: %{},
          do: {{"GET", key}, self()}

    assert map_size(pages) > 1
    Agent.update(ctx.agent, &%{&1 | barriers: pages})
    deadline = System.monotonic_time(:millisecond) + 1_000
    query = Task.async(fn -> S3.query(:metrics, ctx.tenant, deadline_ms: deadline) end)
    assert_receive {:storage_barrier, storage, "GET", key}, 30_000
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    wait = deadline - System.monotonic_time(:millisecond) + 1
    refute_receive :deadline_passed, max(wait, 0)
    send(storage, {:release_storage, key})
    assert {:error, :query_timeout} = Task.await(query, 5_000)
  end

  test "cold root reads are capped at the format-three limit and fall back only for legacy roots", ctx do
    unconfigured(ctx)
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    body = String.duplicate(" ", 600_000) <> IO.iodata_to_binary(Manifest.encode(Manifest.new()))
    Agent.update(ctx.agent, &%{&1 | objects: Map.put(&1.objects, key, {"\"legacy\"", body})})
    assert {:ok, []} = S3.query(:metrics, ctx.tenant, [])
    assert manifest_reads(ctx, key) == 2

    managed = %{ctx | tenant: ctx.tenant <> "-managed"}
    Runtime.put_env(:pulse, S3, ctx.config)
    managed_key = Manifest.manifest_key(managed.tenant, "metrics")
    assert :ok = S3.append(:metrics, managed.tenant, [sample(ctx.now)])
    assert {:ok, [_]} = S3.query(:metrics, managed.tenant, [])

    Agent.update(ctx.agent, fn state ->
      {_, root} = Map.fetch!(state.objects, managed_key)
      oversized = {"\"oversized\"", root <> String.duplicate(" ", 600_000)}
      %{state | objects: Map.put(state.objects, managed_key, oversized)}
    end)

    reads = manifest_reads(managed, managed_key)
    assert {:error, :response_too_large} = S3.query(:metrics, managed.tenant, [])
    assert manifest_reads(managed, managed_key) == reads + 1
  end

  test "enforce keeps large legacy roots readable and gates their ingest on migration", ctx do
    old = ctx.now - 10 * @day

    s = %Segment{
      key: S3.object_key(ctx.tenant, "metrics", old, old, "legacy", nil),
      min_ts: old,
      max_ts: old,
      row_count: 1,
      byte_size: 1
    }

    key = Manifest.manifest_key(ctx.tenant, "metrics")
    encoded = IO.iodata_to_binary(Manifest.encode(Manifest.merge(Manifest.new(), [s])))
    body = String.duplicate(" ", 16_777_217) <> encoded
    Agent.update(ctx.agent, &%{&1 | objects: Map.put(&1.objects, key, {"\"legacy-large\"", body})})

    assert {:ok, []} = S3.query(:metrics, ctx.tenant, start_ts: ctx.now - @hour)
    assert {:error, :retention_migration_required} = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    assert {:error, :response_too_large} = Retention.advance(ctx.tenant, "metrics", ctx.config)
  end

  test "managed compaction preserves retry fences and cleanup revision", ctx do
    for n <- 1..4,
        do: assert(:ok == S3.append(:metrics, ctx.tenant, [sample(ctx.now + n, n / 1)], idempotency_key: "batch#{n}"))

    assert {:ok, %{merged: 4}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, 4} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now + 1, 1.0)], idempotency_key: "batch1")
    assert {:ok, 1} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert {:ok, rows} = S3.query(:metrics, ctx.tenant, [])
    assert Enum.sort(Enum.map(rows, & &1.value)) == [1.0, 2.0, 3.0, 4.0]
    now = expire(ctx)
    clean(ctx, now)
    assert root(ctx).paging["buckets"] == []

    assert {:error, :retention_expired} =
             S3.append(:metrics, ctx.tenant, [sample(ctx.now + 1, 1.0)], idempotency_key: "batch1")
  end

  test "metadata page digest corruption fails rather than omitting records", ctx do
    for n <- 1..2, do: assert(:ok == S3.append(:metrics, ctx.tenant, [sample(ctx.now + n)]))
    ref = hd(root(ctx).paging["buckets"])["index"]
    assert {:ok, _} = ObjectStore.put(ctx.config, ref["k"], "{}")
    # A warm node can legitimately serve its already-validated immutable bytes.
    # Exercise a fresh node/read, which must detect provider corruption.
    MetadataCache.clear()
    assert {:error, :invalid_manifest_page} = S3.query(:metrics, ctx.tenant, [])
  end

  test "orphan sweep uses reclaimed proof, finds late uploads, and never deletes retained data", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    now = expire(ctx)
    clean(ctx, now)
    assert root(ctx).paging["reclaimed"] > ctx.now
    expired = S3.object_key(ctx.tenant, "metrics", ctx.now, ctx.now, "late", nil)
    retained = S3.object_key(ctx.tenant, "metrics", ctx.now + 2 * @day, ctx.now + 2 * @day, "keep", nil)
    for key <- [expired, retained], do: assert(match?({:ok, _}, ObjectStore.put(ctx.config, key, "orphan")))
    for _ <- 1..8, do: assert(match?({:ok, _}, Retention.sweep(ctx.tenant, "metrics", ctx.config)))
    refute Map.has_key?(objects(ctx), expired)
    assert Map.has_key?(objects(ctx), retained)
    assert {:ok, _} = ObjectStore.put(ctx.config, expired, "late-again")
    for _ <- 1..8, do: assert(match?({:ok, _}, Retention.sweep(ctx.tenant, "metrics", ctx.config)))
    refute Map.has_key?(objects(ctx), expired)
  end

  test "repeated retention windows plateau instead of accumulating descriptors and tombstones", ctx do
    for window <- 0..5 do
      ts = ctx.now + window * 2 * @day
      # A future simulated workload uses the storage publication boundary directly.
      config = Map.put(ctx.config, :retention_future_skew_ms, 20 * 86_400_000)
      Runtime.put_env(:pulse, S3, config)
      assert :ok = S3.append(:metrics, ctx.tenant, [sample(ts)])
      assert {:ok, _} = Retention.advance(ctx.tenant, "metrics", config, now_ns: ts + 2 * @day)
      clean(%{ctx | config: config}, div(ts + 2 * @day, 1_000_000) + 100)
      manifest = root(ctx)
      assert manifest.paging["buckets"] == []
      assert manifest.retired == %{}
      assert manifest.segments == []
      assert map_size(objects(ctx)) == 2
      assert byte_size(IO.iodata_to_binary(Manifest.encode(manifest))) < 2048
    end
  end

  test "ordinary unlimited legacy reads remain compatible above sixteen MiB", ctx do
    config =
      ctx.config
      |> Map.put(:retention_enabled, false)
      |> Map.put(:logs_retention_days, 0)
      |> Map.put(:metrics_retention_days, 0)
      |> Map.put(:retention_mode, "observe")

    Runtime.put_env(:pulse, S3, config)
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    body = String.duplicate(" ", 16_777_217) <> IO.iodata_to_binary(Manifest.encode(Manifest.new()))
    Agent.update(ctx.agent, &%{&1 | objects: Map.put(&1.objects, key, {"\"legacy-large\"", body})})
    assert {:ok, []} = S3.query(:metrics, ctx.tenant, [])
    assert {:error, :response_too_large} = Retention.advance(ctx.tenant, "metrics", ctx.config)
  end

  test "nonempty legacy ingest waits for worker conversion without uploading", ctx do
    s = %Segment{
      key: S3.object_key(ctx.tenant, "metrics", ctx.now, ctx.now, "legacy", nil),
      min_ts: ctx.now,
      max_ts: ctx.now,
      row_count: 1,
      byte_size: 1
    }

    seed(ctx, "metrics", Manifest.merge(Manifest.new(), [s]))
    before = map_size(objects(ctx))
    assert {:error, :retention_migration_required} = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    assert map_size(objects(ctx)) == before
    assert {:ok, _} = Retention.advance(ctx.tenant, "metrics", ctx.config)
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now + 1)])
  end

  test "failed and restarted conversion reuses content-addressed pages", ctx do
    s = %Segment{
      key: S3.object_key(ctx.tenant, "metrics", ctx.now - 12 * @hour, ctx.now - 12 * @hour, "legacy", nil),
      min_ts: ctx.now - 12 * @hour,
      max_ts: ctx.now - 12 * @hour,
      row_count: 1,
      byte_size: 1
    }

    seed(ctx, "metrics", Manifest.merge(Manifest.new(), [s]))
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {403, :before, 2}}})
    assert {:error, _} = Retention.advance(ctx.tenant, "metrics", ctx.config, now_ns: ctx.now)
    first = objects(ctx) |> Map.keys() |> Enum.filter(&String.contains?(&1, "/index/")) |> Enum.sort()
    assert length(first) == 2
    assert {:error, _} = Retention.advance(ctx.tenant, "metrics", ctx.config, now_ns: ctx.now + 1_000_000)
    assert first == objects(ctx) |> Map.keys() |> Enum.filter(&String.contains?(&1, "/index/")) |> Enum.sort()
    assert {:ok, _} = Retention.advance(ctx.tenant, "metrics", ctx.config)
  end

  test "expiry can spill the final tail even after mutation and byte quotas are exhausted", ctx do
    for n <- 1..3, do: assert(:ok == S3.append(:metrics, ctx.tenant, [sample(ctx.now + n)]))
    assert length(root(ctx).segments) == 1
    exhausted = ctx.config |> Map.put(:retention_bucket_mutations, 0) |> Map.put(:retention_bucket_metadata_bytes, 0)
    assert {:ok, _} = Retention.advance(ctx.tenant, "metrics", exhausted, now_ns: ctx.now + 2 * @day)
    clean(%{ctx | config: exhausted}, div(ctx.now + 2 * @day, 1_000_000) + 100)
    assert root(ctx).paging["buckets"] == []
    assert map_size(objects(ctx)) == 2
  end

  test "checked-in format-three fixture hashes exact payload bytes across reader upgrades" do
    bytes = File.read!("test/fixtures/retention_manifest_v3.json")
    assert {:ok, %Manifest{version: 3, paging: %{"days" => 1}} = manifest} = Manifest.decode(bytes)
    assert {:ok, ^manifest} = Manifest.decode(IO.iodata_to_binary(Manifest.encode(manifest)))
    changed = String.replace(bytes, "\"days\":1", "\"days\":2")
    assert {:error, :invalid_manifest} = Manifest.decode(changed)
  end

  test "root checksum rejects plausible corruption before any DELETE", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    {_, body} = objects(ctx)[key]
    wire = Pulse.JSON.decode!(body)
    wire = put_in(wire, ["payload", "p", "floor"], wire["payload"]["p"]["floor"] + 1)
    assert {:ok, _} = ObjectStore.put(ctx.config, key, Pulse.JSON.encode!(wire))
    assert {:error, :invalid_manifest} = Retention.advance(ctx.tenant, "metrics", ctx.config)
    assert Agent.get(ctx.agent, & &1.deletes) == []
  end

  test "cross-tenant copied roots cannot expose inline data or foreign pages", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    {_, body} = objects(ctx)[Manifest.manifest_key(ctx.tenant, "metrics")]
    other = ctx.tenant <> "-other"
    assert {:ok, _} = ObjectStore.put(ctx.config, Manifest.manifest_key(other, "metrics"), body)
    assert {:error, :invalid_segment_key} = S3.query(:metrics, other, [])
  end

  test "floor movement while the segment upload is in flight rejects publication", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", :segment} => owner}})
    supervisor = start_supervised!(Task.Supervisor)
    task = Task.Supervisor.async_nolink(supervisor, fn -> S3.append(:metrics, ctx.tenant, [sample(ctx.now + 1)]) end)
    assert_receive {:storage_barrier, storage, "PUT", key}, 30_000
    assert {:ok, _} = Retention.advance(ctx.tenant, "metrics", ctx.config, now_ns: ctx.now + 2 * @day)
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    send(storage, {:release_storage, key})
    assert {:error, :retention_expired} = Task.await(task, 10_000)
    assert {:ok, []} = S3.query(:metrics, ctx.tenant, [])
  end

  test "lost successful root response is resolved without duplicating unkeyed data", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {403, :after, 1}}})
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now + 1)])
    assert {:ok, rows} = S3.query(:metrics, ctx.tenant, [])
    assert length(rows) == 2
  end

  test "native DELETE slots survive termination of a BEAM caller", ctx do
    supervisor = start_supervised!(Task.Supervisor)
    owner = self()
    keys = for n <- 1..4, do: "delete-slots/#{n}"
    for key <- keys, do: assert(match?({:ok, _}, ObjectStore.put(ctx.config, key, "")))
    Agent.update(ctx.agent, &%{&1 | barriers: Map.new(keys, fn key -> {{"DELETE", key}, owner} end)})

    tasks =
      for key <- keys,
          do: Task.Supervisor.async_nolink(supervisor, fn -> ObjectStore.delete_bounded(ctx.config, key) end)

    blocked =
      for _ <- keys do
        assert_receive {:storage_barrier, storage, "DELETE", key}, 30_000
        {storage, key}
      end

    assert {:error, :retention_overloaded} = ObjectStore.delete_bounded(ctx.config, "delete-slots/fifth")
    killed = hd(tasks)
    monitor = Process.monitor(killed.pid)
    Process.exit(killed.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
    assert {:error, :retention_overloaded} = ObjectStore.delete_bounded(ctx.config, "delete-slots/sixth")
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    for {storage, key} <- blocked, do: send(storage, {:release_storage, key})
    for task <- tl(tasks), do: assert(:ok == Task.await(task, 5000))
  end

  test "local discovery continuations never exceed a shrinking queue allowance" do
    for n <- 1..40, do: ManifestCache.put("local-#{n}", "metrics", Manifest.new(), "etag")
    {first, cursor} = ManifestCache.scopes_page(nil, 8)
    assert length(first) == 8
    {next, _} = ManifestCache.scopes_page(cursor, 1)
    assert length(next) == 1
    assert Enum.uniq(first ++ next) == first ++ next
  end

  test "offline conversion rejects missing budgets and oversized legacy roots", ctx do
    start_supervised!({Task.Supervisor, name: RetentionTasks, max_children: 1})
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    body = String.duplicate(" ", 16_777_217) <> IO.iodata_to_binary(Manifest.encode(Manifest.new()))
    Agent.update(ctx.agent, &%{&1 | objects: Map.put(&1.objects, key, {"\"legacy-large\"", body})})
    assert {:error, :invalid_migration_budget} = Retention.convert_offline(ctx.tenant, "metrics", ctx.config, [])

    assert {:error, :response_too_large} =
             Retention.convert_offline(ctx.tenant, "metrics", ctx.config, max_legacy_bytes: 16_777_216)
  end

  # A task may reply before its supervisor removes it. Independent budget
  # scenarios must not contend for the same single-child conversion slot.
  test "offline conversion accepts a large root within explicit byte and heap budgets", ctx do
    start_supervised!({Task.Supervisor, name: RetentionTasks, max_children: 1})
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    body = String.duplicate(" ", 16_777_217) <> IO.iodata_to_binary(Manifest.encode(Manifest.new()))
    Agent.update(ctx.agent, &%{&1 | objects: Map.put(&1.objects, key, {"\"legacy-large\"", body})})

    assert {:ok, _} = Retention.convert_offline(ctx.tenant, "metrics", ctx.config, max_legacy_bytes: 20_000_000)
    assert root(ctx).version == 3
  end

  test "publication partitions bucket fanout and isolates an expired caller", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    [{pid, _}] = Registry.lookup(ManifestRegistry, {ctx.tenant, "metrics"})
    :sys.replace_state(pid, &%{&1 | flush_interval_ms: 60_000, flush_batch_max: 256})

    refs =
      for n <- 1..6 do
        ts = ctx.now - n * @hour

        segment = %Segment{
          key: S3.object_key(ctx.tenant, "metrics", ts, ts, "queued#{n}", nil),
          min_ts: ts,
          max_ts: ts,
          row_count: 1,
          byte_size: 1
        }

        ref = make_ref()
        send(pid, {:"$gen_call", {self(), ref}, {:register_segments, [segment]}})
        ref
      end

    expired = %Segment{key: "unused", min_ts: 0, max_ts: 0}
    rejected = make_ref()
    send(pid, {:"$gen_call", {self(), rejected}, {:register_segments, [expired]}})
    _ = :sys.get_state(pid)
    send(pid, :flush)
    _ = :sys.get_state(pid)
    send(pid, :flush)
    _ = :sys.get_state(pid)
    assert_receive {^rejected, {:error, :retention_expired}}, 5000
    for ref <- refs, do: assert_receive({^ref, :ok}, 5000)
    assert length(root(ctx).paging["buckets"]) == 7
  end

  test "durable discovery keeps a queue slot under sustained local activity", ctx do
    for n <- 1..80, do: ManifestCache.put("local-#{n}", "metrics", Manifest.new(), "etag")
    for n <- 1..32, do: assert(match?({:ok, _}, ObjectStore.put(ctx.config, "tenants/dormant-#{n}/manifest.json", "")))

    config =
      ctx.config
      |> Map.put(:retention_mode, "observe")
      |> Map.put(:retention_interval_ms, 3_600_000)
      |> Map.put(:retention_timeout_ms, 10_000)

    start_supervised!({RetentionSupervision, config})
    worker = Pulse.Runtime.whereis(RetentionWorker)
    queue = for n <- 1..56, do: {"queued-#{n}", "metrics"}
    :sys.replace_state(worker, &%{&1 | queue: queue})
    send(worker, :retain)
    state = :sys.get_state(worker, 60_000)
    assert length(state.queue) <= 64
    assert state.discovery != nil
    assert Enum.any?(state.queue, fn {tenant, _} -> String.starts_with?(tenant, "dormant-") end)
  end

  test "catch-up outside the normal horizon persists progress and retries failed keys", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(ctx.now)])
    now = expire(ctx)
    clean(ctx, now)
    assert {:ok, _} = Retention.cleanup(ctx.tenant, "metrics", ctx.config, now_ms: now + 100)
    old = ctx.now - 10 * @day
    key = S3.object_key(ctx.tenant, "metrics", old, old, "orphan", nil)
    assert {:ok, _} = ObjectStore.put(ctx.config, key, "orphan")
    Agent.update(ctx.agent, &%{&1 | faults: %{{"DELETE", key} => {403, :before, 1}}})
    assert {:ok, :ok} = Retention.start_catchup(ctx.tenant, "metrics", ctx.config, old)
    for _ <- 1..600, do: assert(match?({:ok, _}, Retention.sweep(ctx.tenant, "metrics", ctx.config)))
    refute Map.has_key?(objects(ctx), key)
    assert root(ctx).paging["catchup"] == nil
  end
end
