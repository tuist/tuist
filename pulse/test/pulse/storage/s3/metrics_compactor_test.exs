defmodule Pulse.Storage.S3.MetricsCompactorTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Runtime.ProcessGroup
  alias Pulse.Runtime.Registry
  alias Pulse.Runtime.Supervision, as: Supervisor
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.CompactionDiscovery
  alias Pulse.Storage.S3.CompactionOwnership
  alias Pulse.Storage.S3.CompactionSupervision
  alias Pulse.Storage.S3.CompactionTasks
  alias Pulse.Storage.S3.CompactionWorker
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestBackup
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.ManifestRegistry
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Test.CompactionPeer
  alias Pulse.Test.CompactionStore

  @moduletag timeout: 120_000

  setup tags do
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
      # Isolate native connection caches even if the OS reuses a test port.
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      # These tests count compaction's own merges, reads and deletions; hour
      # finalization and manifest backups have their own worker test.
      metric_finalize_enabled: false,
      manifest_backup_enabled: false
    }

    # Tests of the flat format's own behaviour opt out of paged manifests.
    config = if tags[:manifest_format], do: Map.put(config, :manifest_format, tags[:manifest_format]), else: config

    Runtime.put_env(:pulse, S3, config)

    start_supervised!(ManifestSupervision)
    start_supervised!(%{id: CompactionOwnership, start: {:pg, :start_link, [CompactionOwnership.scope()]}})

    start_supervised!(
      Supervisor.child_spec({Task.Supervisor, name: CompactionTasks, max_children: 4}, id: CompactionTasks)
    )

    tenant = "compact-#{System.unique_integer([:positive])}"

    {:ok, _} =
      ObjectStore.put(
        config,
        Manifest.manifest_key(tenant, "metrics"),
        Manifest.encode(Manifest.new()) |> IO.iodata_to_binary()
      )

    %{agent: agent, config: config, tenant: tenant}
  end

  defp sample(ts, value, host \\ "a") do
    %MetricSample{timestamp_ns: ts, value: value, labels: %{"__name__" => "requests", "host" => host}}
  end

  defp load(ctx) do
    {:ok, _, body} = ObjectStore.get_if_none_match(ctx.config, Manifest.manifest_key(ctx.tenant, "metrics"), nil)
    {:ok, manifest} = Manifest.decode(body)
    manifest
  end

  defp reads(agent) do
    Agent.get_and_update(agent, fn state ->
      {Enum.count(state.reads, &String.ends_with?(&1, ".parquet")), %{state | reads: []}}
    end)
  end

  test "first registration publishes one complete manifest and exposes no uncommitted cache", ctx do
    key = Manifest.manifest_key(ctx.tenant, "logs")
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", key} => owner}})
    supervisor = start_supervised!(Task.Supervisor)

    append =
      Task.Supervisor.async_nolink(supervisor, fn ->
        S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: 1, service: "api"}])
      end)

    assert_receive {:storage_barrier, writer, "PUT", ^key}, 30_000
    assert ManifestCache.get(ctx.tenant, "logs") == nil
    {_, body} = Agent.get(ctx.agent, &Map.fetch!(&1.objects, key))
    assert {:ok, %Manifest{segments: [segment]}} = Manifest.decode(body)
    assert segment.row_count == 1
    assert segment.byte_size > 0
    assert segment.log_services == ["api"]
    assert Agent.get(ctx.agent, &Enum.count(&1.requests, fn request -> request == {"PUT", key} end)) == 1
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    send(writer, {:release_storage, key})
    assert Task.await(append, 10_000) == :ok
    assert %{etag: etag} = ManifestCache.get(ctx.tenant, "logs")
    assert is_binary(etag)
  end

  test "read-only legacy migration still durably creates a missing manifest", ctx do
    records = [%Log{timestamp_ns: 1, service: "legacy"}]
    {:ok, payload, mn, mx} = S3.encode_segment(:logs, records)
    key = S3.object_key(ctx.tenant, "logs", mn, mx, "legacy", nil)
    assert {:ok, _} = ObjectStore.put(ctx.config, key, payload)
    assert {:ok, ^records} = S3.query(:logs, ctx.tenant, [])
    manifest_key = Manifest.manifest_key(ctx.tenant, "logs")
    assert {:ok, _, body} = ObjectStore.get_if_none_match(ctx.config, manifest_key, nil)
    assert {:ok, %Manifest{segments: [%Segment{key: ^key}]}} = Manifest.decode(body)
    assert Agent.get(ctx.agent, &Enum.count(&1.requests, fn request -> request == {"PUT", manifest_key} end)) == 1
  end

  test "log service pruning survives cache reload and unknown legacy summaries still scan", ctx do
    assert :ok = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: 1, service: "wanted"}])
    assert :ok = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: 2, service: "other"}])
    {:ok, entry} = ManifestOwner.ensure_loaded(ctx.tenant, "logs", ctx.config)
    other = Enum.find(entry.manifest.segments, &(&1.log_services == ["other"]))
    assert {:ok, _} = ObjectStore.put(ctx.config, other.key, "corrupt")
    ManifestCache.drop(ctx.tenant, "logs")
    assert {:ok, [%Log{service: "wanted"}]} = S3.query(:logs, ctx.tenant, matchers: [{"service_name", :eq, "wanted"}])
    assert {:error, _} = S3.query(:logs, ctx.tenant, [])

    legacy = %{
      entry.manifest
      | segments: Enum.map(entry.manifest.segments, &%{&1 | log_services: nil, log_labels: nil})
    }

    assert {:ok, _} =
             ObjectStore.put(
               ctx.config,
               Manifest.manifest_key(ctx.tenant, "logs"),
               legacy |> Manifest.encode() |> IO.iodata_to_binary()
             )

    ManifestCache.drop(ctx.tenant, "logs")
    assert {:error, _} = S3.query(:logs, ctx.tenant, service: "wanted")
  end

  test "exact arbitrary metric labels prune corrupt unrelated segments after cache reload", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(1, 1.0, "a")])
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(2, 2.0, "b")])
    other = Enum.find(load(ctx).segments, &(&1.metric_labels == %{"host" => ["b"]}))
    assert {:ok, _} = ObjectStore.put(ctx.config, other.key, "corrupt")
    ManifestCache.drop(ctx.tenant, "metrics")
    assert {:ok, [%MetricSample{value: 1.0}]} = S3.query(:metrics, ctx.tenant, matchers: [{"host", :eq, "a"}])
    assert {:error, _} = S3.query(:metrics, ctx.tenant, [])
  end

  test "keyed metric retries keep legacy bytes and fresh compaction outputs can add postings", ctx do
    records = [sample(1, 1.0, "a"), sample(2, 2.0, "b")]
    # Frozen source-equivalent pre-index v2 bytes, not a historical release
    # artifact. Dependency/encoder changes must not silently change keyed PUTs.
    legacy = File.read!(Path.expand("../../../fixtures/metrics/keyed_metric_v2.parquet", __DIR__))
    assert {:ok, ^legacy, _, _, 2} = NIF.encode_metric_segment_parquet_v2(records)
    assert :binary.match(legacy, "pulse.metric.postings.v1") == :nomatch
    assert :ok = S3.append(:metrics, ctx.tenant, records, idempotency_key: "unchanged")
    assert [source] = load(ctx).segments
    assert source.byte_size == byte_size(legacy)
    assert {_, ^legacy} = Agent.get(ctx.agent, &Map.fetch!(&1.objects, source.key))

    ManifestCache.drop(ctx.tenant, "metrics")
    assert :ok = S3.append(:metrics, ctx.tenant, records, idempotency_key: "unchanged")
    assert [^source] = load(ctx).segments
    assert {_, ^legacy} = Agent.get(ctx.agent, &Map.fetch!(&1.objects, source.key))
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(3, 3.0, "a")])
    queries = [[], [{"host", :eq, "a"}], [{"host", :eq, "a"}, {"host", :eq, "b"}]]
    before = for matchers <- queries, do: S3.query(:metrics, ctx.tenant, matchers: matchers)
    assert Enum.at(before, 2) == {:ok, []}
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    assert [replacement] = load(ctx).segments
    assert replacement.key != source.key
    assert {_, indexed} = Agent.get(ctx.agent, &Map.fetch!(&1.objects, replacement.key))
    assert replacement.byte_size == byte_size(indexed)
    assert :binary.match(indexed, "pulse.metric.postings.v1") != :nomatch
    ManifestCache.drop(ctx.tenant, "metrics")
    assert Enum.map(queries, &S3.query(:metrics, ctx.tenant, matchers: &1)) == before
  end

  test "compaction rebuilds complete metric label sets without excluding samples", ctx do
    for ts <- 1..4,
        do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1, "a"), sample(ts, ts / 1, "b")]))

    matchers = [{"host", :eq, "a"}]
    before = S3.query(:metrics, ctx.tenant, matchers: matchers)
    assert {:ok, %{merged: 4}} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    ManifestCache.drop(ctx.tenant, "metrics")
    assert S3.query(:metrics, ctx.tenant, matchers: matchers) == before
    assert [%Segment{metric_labels: %{"host" => ["a", "b"]}}] = load(ctx).segments
  end

  test "an absent value is rejected while finite samples survive compaction and evaluation", ctx do
    Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)

    assert {:error, {:encode_failed, _}} =
             S3.append(:metrics, ctx.tenant, [sample(1, 1.0), sample(2, nil)])

    assert {:ok, []} = S3.query(:metrics, ctx.tenant, [])
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(1_000_000_000, 1.0)])
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(2_000_000_000, 2.0)])
    assert {:ok, before} = S3.query(:metrics, ctx.tenant, [])
    assert Enum.map(before, & &1.value) |> Enum.sort() == [1.0, 2.0]
    assert {:ok, evaluated_before} = Evaluator.query("requests", ctx.tenant, %{end_ts_ns: 2_000_000_000})
    assert Enum.map(evaluated_before["data"]["result"], & &1["value"]) == [[2.0, "2"]]

    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    assert {:ok, after_compaction} = S3.query(:metrics, ctx.tenant, [])
    assert Enum.sort_by(after_compaction, & &1.timestamp_ns) == Enum.sort_by(before, & &1.timestamp_ns)
    assert {:ok, evaluated_after} = Evaluator.query("requests", ctx.tenant, %{end_ts_ns: 2_000_000_000})
    assert evaluated_after == evaluated_before
  end

  test "compaction preserves staleness and IEEE values and leaves query results unchanged", ctx do
    Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(0, 1.0), sample(10_000_000_000, :stale)])

    assert :ok =
             S3.append(:metrics, ctx.tenant, [
               sample(20_000_000_000, 2.0),
               sample(30_000_000_000, :nan),
               sample(40_000_000_000, :infinity),
               sample(50_000_000_000, :negative_infinity)
             ])

    times = [0, 10, 20, 30, 40, 50]
    before = for time <- times, do: Evaluator.query("requests", ctx.tenant, %{end_ts_ns: time * 1_000_000_000})
    assert Enum.all?(before, &match?({:ok, _}, &1))
    assert {:ok, stored} = S3.query(:metrics, ctx.tenant, [])
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config)

    after_compaction =
      for time <- times, do: Evaluator.query("requests", ctx.tenant, %{end_ts_ns: time * 1_000_000_000})

    assert after_compaction == before
    assert {:ok, after_rows} = S3.query(:metrics, ctx.tenant, [])
    assert Enum.sort_by(after_rows, & &1.timestamp_ns) == Enum.sort_by(stored, & &1.timestamp_ns)
  end

  test "a legacy stale marker suppresses instant results instead of corrupting the query", ctx do
    Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)

    records = [
      %MetricSample{timestamp_ns: 1, value: 1.0, labels: %{"__name__" => "safe"}},
      %MetricSample{timestamp_ns: 2, value: 2.0, labels: %{"__name__" => "unsafe"}}
    ]

    assert :ok = S3.append(:metrics, ctx.tenant, records)
    key = hd(load(ctx).segments).key
    fixture = File.read!(Path.expand("../../../fixtures/metrics/non_finite.parquet", __DIR__))
    assert {:ok, _} = ObjectStore.put(ctx.config, key, fixture)

    assert {:ok, stored} = S3.query(:metrics, ctx.tenant, [])
    assert Enum.any?(stored, &(&1.value == :stale))
    assert {:ok, result} = Evaluator.query("unsafe", ctx.tenant, %{end_ts_ns: 2})
    assert result["data"]["result"] == []
    assert {:ok, [finite]} = S3.query(:metrics, ctx.tenant, matchers: [{"__name__", :eq, "safe"}])
    assert finite.value == 1.0
  end

  test "identical filtered results with 16 times fewer object reads, durable grace and ingest retry", ctx do
    for ts <- 1..16 do
      assert :ok =
               S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1), sample(ts, -ts / 1, "b")], idempotency_key: "#{ts}")
    end

    queries = [[], [start_ts: 4, end_ts: 12], [limit: 7], [matchers: [{"host", :eq, "a"}]]]
    before = Enum.map(queries, &S3.query(:metrics, ctx.tenant, &1))
    assert Enum.all?(before, &match?({:ok, _}, &1))
    reads(ctx.agent)
    assert {:ok, _} = S3.query(:metrics, ctx.tenant, [])
    assert reads(ctx.agent) == 16
    snapshot = load(ctx)
    assert {:ok, %{merged: 16}} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    assert {:ok, 0} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert Enum.map(queries, &S3.query(:metrics, ctx.tenant, &1)) == before
    reads(ctx.agent)
    assert {:ok, _} = S3.query(:metrics, ctx.tenant, [])
    assert reads(ctx.agent) == 1
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(1, 1.0), sample(1, -1.0, "b")], idempotency_key: "1")
    assert S3.query(:metrics, ctx.tenant, []) == hd(before)
    # Expire the durable deadlines, simulating a later worker after restart.
    manifest = load(ctx)

    expired = %{
      manifest
      | retired: Map.new(manifest.retired, fn {key, retirement} -> {key, %{retirement | delete_after: 0}} end)
    }

    assert {:ok, _} =
             ObjectStore.put(
               ctx.config,
               Manifest.manifest_key(ctx.tenant, "metrics"),
               Manifest.encode(expired) |> IO.iodata_to_binary()
             )

    assert {:ok, 16} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert {:ok, 0} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    ManifestCache.put(ctx.tenant, "metrics", snapshot, "stale")
    # Deliberately serve a fresh-looking obsolete snapshot; missing files restart the scan.
    Runtime.put_env(:pulse, S3, Map.put(ctx.config, :refresh_stale_ms, 60_000))
    assert S3.query(:metrics, ctx.tenant, []) == hd(before)
  end

  @tag timeout: 5_000
  test "queue metrics can be scraped while manifest publication is blocked in native I/O", ctx do
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    parent = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", key} => parent}})

    pid =
      start_supervised!(
        # `Task` is Pulse.Runtime.Task here; supervise a standard task running a
        # closure that carries this test's runtime explicitly.
        {Elixir.Task,
         Runtime.capture(fn ->
           send(parent, {:append_finished, S3.append(:metrics, ctx.tenant, [sample(1, 1.0)])})
         end)}
      )

    ref = Process.monitor(pid)
    assert_receive {:storage_barrier, storage, "PUT", ^key}, 30_000
    calls_before = Agent.get(ctx.agent, &length(&1.requests))
    rendered = Pulse.Metrics.render()
    assert rendered =~ "pulse_manifest_pending_segments 1\n"
    assert rendered =~ "pulse_manifest_waiting_requests 1\n"
    assert Agent.get(ctx.agent, &length(&1.requests)) == calls_before
    send(storage, {:release_storage, key})
    assert_receive {:append_finished, :ok}, 1_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert Pulse.Metrics.render() =~ "pulse_manifest_pending_segments 0\n"
    assert Pulse.Metrics.render() =~ "pulse_manifest_waiting_requests 0\n"
  end

  @tag timeout: 60_000
  test "worker deadlines are observable before the stalled native operation finishes", ctx do
    for ts <- 1..2, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    source = hd(load(ctx).segments).key
    parent = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"GET", source} => parent}})
    key = {"pulse_compaction_timeouts_total", [{"operation", "merge"}]}

    before_count =
      case :ets.lookup(Pulse.Runtime.table(Pulse.Metrics), key) do
        [{_, count}] -> count
        [] -> 0
      end

    config = ctx.config |> Map.put(:compaction_timeout_ms, 200) |> Map.put(:compaction_interval_ms, 3_600_000)
    worker = start_supervised!({CompactionWorker, config})
    send(worker, :compact)
    assert_receive {:storage_barrier, storage, "GET", ^source}, 30_000
    _ = :sys.get_state(worker, 60_000)
    assert [{^key, count}] = :ets.lookup(Pulse.Runtime.table(Pulse.Metrics), key)
    assert count == before_count + 1
    assert [task] = Task.Supervisor.children(CompactionTasks)
    ref = Process.monitor(task)
    rendered = Pulse.Metrics.render()
    assert rendered =~ ~s(pulse_compaction_timeouts_total{operation="merge"})
    assert Agent.get(ctx.agent, &Map.has_key?(&1.barriers, {"GET", source}))
    send(storage, {:release_storage, source})
    assert_receive {:DOWN, ^ref, :process, ^task, :normal}, 1_000
    assert [{^key, count}] = :ets.lookup(Pulse.Runtime.table(Pulse.Metrics), key)
    assert count == before_count + 1
  end

  test "self-monitoring counts completed merges and cleanup without storing monitoring records", ctx do
    count = fn operation ->
      case :ets.lookup(
             Pulse.Runtime.table(Pulse.Metrics),
             {"pulse_compaction_segments_total", [{"operation", operation}]}
           ) do
        [{_, value}] -> value
        [] -> 0
      end
    end

    before_merge = count.("compact")
    before_cleanup = count.("cleanup")
    for ts <- 1..2, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert count.("compact") == before_merge + 2
    assert {:ok, 2} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert count.("cleanup") == before_cleanup + 2
    assert {:ok, %{merged: 0}} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    assert {:ok, 0} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert count.("compact") == before_merge + 2
    assert count.("cleanup") == before_cleanup + 2
    assert {:ok, samples} = S3.query(:metrics, ctx.tenant, [])
    assert length(samples) == 2
    [{_pid, info}] = Registry.lookup(ManifestRegistry, {ctx.tenant, "metrics"})
    assert %{pending: 0, waiters: 0, queued: 0, committing_since: nil} = info
  end

  @tag manifest_format: "flat"
  test "compacted name summaries preserve selective query budgets and retirement metadata", ctx do
    for ts <- 1..4, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    matchers = [{"__name__", :eq, "requests"}]
    before = S3.query(:metrics, ctx.tenant, matchers: matchers)
    assert {:error, :query_scan_limit} = S3.query(:metrics, ctx.tenant, matchers: matchers, max_scan_segments: 1)
    assert {:ok, %{merged: 4}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    other = %MetricSample{timestamp_ns: 5, value: 1.0, labels: %{"__name__" => "temperature"}}
    assert :ok = S3.append(:metrics, ctx.tenant, [other])
    manifest = load(ctx)
    assert manifest.version == 2
    assert map_size(manifest.retired) == 4
    assert Enum.any?(manifest.segments, &(&1.metric_names == ["requests"]))
    reads(ctx.agent)
    assert S3.query(:metrics, ctx.tenant, matchers: matchers, max_scan_segments: 1, max_scan_rows: 4) == before
    assert reads(ctx.agent) == 1
    assert {:ok, 4} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    cleaned = load(ctx)
    assert cleaned.cleanup_cursor != nil
    assert Enum.all?(cleaned.retired, fn {_, retirement} -> retirement.deleted? end)
    assert Enum.any?(cleaned.segments, &(&1.metric_names == ["requests"]))
  end

  test "a stale snapshot retry prunes unrelated metric names before checking scan budgets", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    snapshot = load(ctx)
    expected = S3.query(:metrics, ctx.tenant, [])
    assert {:ok, %{merged: 3}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, 3} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)

    for ts <- 4..7 do
      other = %MetricSample{timestamp_ns: ts, value: 1.0, labels: %{"__name__" => "temperature"}}
      assert :ok = S3.append(:metrics, ctx.tenant, [other])
    end

    ManifestCache.put(ctx.tenant, "metrics", snapshot, "obsolete")
    Runtime.put_env(:pulse, S3, Map.put(ctx.config, :refresh_stale_ms, 60_000))
    reads(ctx.agent)
    assert S3.query(:metrics, ctx.tenant, matchers: [{"__name__", :eq, "requests"}], max_scan_segments: 3) == expected
    assert reads(ctx.agent) == 2
  end

  test "an in-flight compaction retry retains the rows already consumed from its scan budget", ctx do
    for ts <- 1..4, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    first_key = hd(load(ctx).segments).key
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"GET", first_key} => owner}})
    supervisor = start_supervised!(Task.Supervisor)
    query = Task.Supervisor.async_nolink(supervisor, fn -> S3.query(:metrics, ctx.tenant, max_scan_rows: 4) end)
    assert_receive {:storage_barrier, reader, "GET", ^first_key}, 30_000
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    assert {:ok, %{merged: 4}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, 4} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    send(reader, {:release_storage, first_key})
    assert Task.await(query, 10_000) == {:error, :query_scan_limit}
    assert {:ok, records} = S3.query(:metrics, ctx.tenant, max_scan_rows: 4)
    assert length(records) == 4
  end

  test "public metric evaluation preserves counter resets and grouped range results after compaction", ctx do
    Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)

    for scrape <- 1..30 do
      ts = scrape * 15_000_000_000
      counter = if scrape < 10, do: scrape * 5.0, else: (scrape - 10) * 5.0
      assert :ok = S3.append(:metrics, ctx.tenant, [sample(ts, counter), sample(ts, counter * 2, "b")])
    end

    queries = ["sum(rate(requests[60s]))", "max by(host) (requests)", "avg_over_time(requests[60s])"]
    opts = %{start_ts_ns: 60_000_000_000, end_ts_ns: 450_000_000_000, step_ns: 15_000_000_000}
    evaluate = fn query -> Evaluator.query(query, ctx.tenant, opts) end
    before = Enum.map(queries, evaluate)
    assert Enum.all?(before, &match?({:ok, %{"data" => %{"result" => [_ | _]}}}, &1))
    reads(ctx.agent)
    assert evaluate.(hd(queries)) == hd(before)
    assert reads(ctx.agent) == 30
    assert {:ok, %{merged: 30}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, 30} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    reads(ctx.agent)
    assert Enum.map(queries, evaluate) == before
    assert reads(ctx.agent) == 3
  end

  test "concurrent append survives a conditional-write conflict", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    {:ok, payload, mn, mx} = S3.encode_segment(:metrics, [sample(4, 2.0)])
    key = S3.object_key(ctx.tenant, "metrics", mn, mx, "extra", nil)
    assert {:ok, _} = ObjectStore.put(ctx.config, key, payload)
    extra = Segment.build(key, mn, mx, 1, byte_size(payload))
    manifest_key = Manifest.manifest_key(ctx.tenant, "metrics")

    Agent.update(ctx.agent, fn state ->
      %{
        state
        | hook: fn state ->
            {_, body} = Map.fetch!(state.objects, manifest_key)
            {:ok, current} = Manifest.decode(body)
            updated = Manifest.merge(current, [extra]) |> Manifest.encode() |> IO.iodata_to_binary()
            %{state | objects: Map.put(state.objects, manifest_key, {"\"concurrent\"", updated})}
          end
      }
    end)

    assert {:ok, %{merged: 3}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, records} = S3.query(:metrics, ctx.tenant, [])
    assert Enum.map(records, & &1.timestamp_ns) == [4, 3, 2, 1]
    assert {:ok, 3} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
  end

  test "overlapping compaction cannot publish twice", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    manifest_key = Manifest.manifest_key(ctx.tenant, "metrics")

    Agent.update(ctx.agent, fn state ->
      %{
        state
        | hook: fn state ->
            {_, body} = Map.fetch!(state.objects, manifest_key)
            {:ok, current} = Manifest.decode(body)
            [first | _] = current.segments
            replacement = %{first | key: first.key <> "-winner"}
            {:ok, updated} = Manifest.replace(current, Enum.map(current.segments, & &1.key), replacement, 0)
            body = Manifest.encode(updated) |> IO.iodata_to_binary()
            %{state | objects: Map.put(state.objects, manifest_key, {"\"winner\"", body})}
          end
      }
    end)

    assert {:error, :compaction_conflict} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    assert length(load(ctx).segments) == 1
  end

  test "duplicates and conflicting same-time samples retain deterministic limited results", ctx do
    for value <- [2.0, 1.0, 2.0, 3.0] do
      assert :ok = S3.append(:metrics, ctx.tenant, [sample(1, value)])
    end

    before = S3.query(:metrics, ctx.tenant, [])
    limited = S3.query(:metrics, ctx.tenant, limit: 2)
    assert {:ok, %{merged: 4}} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    assert S3.query(:metrics, ctx.tenant, []) == before
    assert S3.query(:metrics, ctx.tenant, limit: 2) == limited
  end

  test "background worker discovers tenants and compacts and cleans up", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    worker = start_supervised!({CompactionWorker, Map.put(ctx.config, :compaction_options, grace_ms: 0)})
    send(worker, :compact)
    _ = :sys.get_state(worker, 60_000)
    assert length(load(ctx).segments) == 1
    assert {:ok, records} = S3.query(:metrics, ctx.tenant, [])
    assert length(records) == 3

    assert Agent.get(ctx.agent, fn state ->
             Enum.count(state.objects, fn {key, _} -> String.ends_with?(key, ".parquet") end)
           end) == 1
  end

  test "background worker finalizes settled hours, backs up the manifest and holds cleanup for it", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts * 1.0)]))
    before = S3.query(:metrics, ctx.tenant, [])

    config =
      ctx.config
      |> Map.merge(%{metric_finalize_enabled: true, manifest_backup_enabled: true})
      |> Map.put(:compaction_options, grace_ms: 0)
      |> Map.put(:metric_finalize_options, grace_ms: 0)

    worker = start_supervised!({CompactionWorker, config})
    send(worker, :compact)
    _ = :sys.get_state(worker, 60_000)

    tiers = load(ctx).segments |> Enum.map(&Segment.metric_tier/1) |> Enum.sort()
    assert tiers == [:final, :rollup]
    assert S3.query(:metrics, ctx.tenant, []) == before
    assert {:ok, [backup]} = ObjectStore.list(ctx.config, ManifestBackup.prefix(ctx.tenant, "metrics"))
    assert {:ok, body} = ObjectStore.get(ctx.config, backup)
    assert {:ok, %Manifest{segments: backed_up}} = Manifest.decode(body)
    assert backed_up |> Enum.map(&Segment.metric_tier/1) |> Enum.sort() == [:final, :rollup]

    # The backup records every retirement, so cleanup could delete them all:
    # only the finalized segment and its rollup remain.
    parquet =
      Agent.get(ctx.agent, fn state -> Enum.filter(Map.keys(state.objects), &String.ends_with?(&1, ".parquet")) end)

    assert parquet |> Enum.map(&Segment.key_tier/1) |> Enum.sort() == [:final, :rollup]
  end

  test "missing input fails before publication and cleanup never removes active segments", ctx do
    for ts <- 1..2, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    before = load(ctx)
    [first | _] = before.segments
    assert :ok = ObjectStore.delete(ctx.config, first.key)
    assert {:error, :not_found} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert load(ctx) == before
    assert {:ok, 0} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert {:error, :not_found} = S3.query(:metrics, ctx.tenant, [])
  end

  test "recompaction preserves all samples and cleanup keeps the current replacement", ctx do
    for ts <- 1..4, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    assert {:ok, %{merged: 4, replacement: first}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    for ts <- 5..8, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    before = S3.query(:metrics, ctx.tenant, [])
    assert {:ok, %{merged: 5, replacement: second}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, 9} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert {:error, :not_found} = ObjectStore.get(ctx.config, first)
    assert {:ok, _} = ObjectStore.get(ctx.config, second)
    assert S3.query(:metrics, ctx.tenant, []) == before
  end

  test "realistic scrape batches across midnight preserve selective and limited queries", ctx do
    # Twelve series, fifteen-second scrapes, out-of-order delivery and an hour/day
    # boundary. No aggregation or resampling is allowed during compaction.
    start = DateTime.to_unix(~U[2026-09-30 23:56:00Z], :nanosecond)

    batches =
      for scrape <- 0..31 do
        for host <- 1..6, name <- ["http_requests_total", "process_cpu_seconds_total"] do
          %MetricSample{
            timestamp_ns: start + scrape * 15_000_000_000,
            value: scrape * 10.0 + host / 10,
            labels: %{
              "__name__" => name,
              "instance" => "app-#{host}:9090",
              "job" => "checkout",
              "region" => if(host <= 3, do: "eu-west", else: "us-east")
            }
          }
        end
      end

    for {batch, index} <- Enum.with_index(Enum.reverse(batches)) do
      assert :ok = S3.append(:metrics, ctx.tenant, batch, idempotency_key: "scrape-#{index}")
    end

    queries = [
      [],
      [limit: 25],
      [start_ts: start + 180_000_000_000, end_ts: start + 300_000_000_000],
      [matchers: [{"__name__", :eq, "http_requests_total"}, {"region", :eq, "eu-west"}]],
      [matchers: [{"instance", :re, "app-[12]:9090"}], limit: 13],
      [matchers: [{"job", :eq, "absent"}]]
    ]

    before = Enum.map(queries, &S3.query(:metrics, ctx.tenant, &1))
    assert {:ok, all} = hd(before)
    assert length(all) == 384
    reads(ctx.agent)
    assert {:ok, _} = S3.query(:metrics, ctx.tenant, [])
    assert reads(ctx.agent) == 32
    assert {:ok, %{merged: 16}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, %{merged: 16}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, %{merged: 0}} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    assert Enum.map(queries, &S3.query(:metrics, ctx.tenant, &1)) == before
    reads(ctx.agent)
    assert {:ok, _} = S3.query(:metrics, ctx.tenant, [])
    assert reads(ctx.agent) == 2
    assert {:ok, 32} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    # Actually restart the local writer/cache supervision tree, then retry an
    # acknowledged scrape. Durable retirement metadata must prevent duplicates.
    stop_supervised!(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert :ok = S3.append(:metrics, ctx.tenant, List.last(batches), idempotency_key: "scrape-0")
    assert Enum.map(queries, &S3.query(:metrics, ctx.tenant, &1)) == before
  end

  test "failed replacement upload keeps the original query generation intact", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    before = S3.query(:metrics, ctx.tenant, [])
    manifest = load(ctx)
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", :replacement} => {403, :before, 1}}})
    assert {:error, _} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert load(ctx) == manifest
    assert S3.query(:metrics, ctx.tenant, []) == before
    assert {:ok, 0} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
  end

  test "cleanup resumes after a deletion failure without affecting active results", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    before = S3.query(:metrics, ctx.tenant, [])
    source = hd(load(ctx).segments).key
    assert {:ok, %{merged: 3}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    Agent.update(ctx.agent, &%{&1 | faults: %{{"DELETE", source} => {403, :before, 1}}})
    assert {:error, _} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert S3.query(:metrics, ctx.tenant, []) == before
    assert {:ok, 1} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert S3.query(:metrics, ctx.tenant, []) == before
  end

  test "lost publication response keeps the acknowledged samples visible", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    before = S3.query(:metrics, ctx.tenant, [])
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {500, :after, 1}}})
    # The native client retries with the original condition after a successful
    # write whose response was lost. The data must remain valid either way.
    assert {:ok, %{merged: 3, replacement: replacement}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert Enum.map(load(ctx).segments, & &1.key) == [replacement]

    assert Agent.get(ctx.agent, fn state ->
             Enum.count(state.objects, fn {key, _} -> String.contains?(key, "-compact-") end)
           end) == 1

    assert S3.query(:metrics, ctx.tenant, []) == before
    assert {:ok, 3} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert S3.query(:metrics, ctx.tenant, []) == before
  end

  test "background maintenance isolates tenants and leaves log segments unchanged", ctx do
    other = ctx.tenant <> "-other"

    for tenant <- [ctx.tenant, other] do
      {:ok, _} =
        ObjectStore.put(
          ctx.config,
          Manifest.manifest_key(tenant, "metrics"),
          Manifest.encode(Manifest.new()) |> IO.iodata_to_binary()
        )

      for ts <- 1..3,
          do: assert(:ok = S3.append(:metrics, tenant, [sample(ts, if(tenant == other, do: 2.0, else: 1.0))]))
    end

    assert :ok = S3.append(:logs, ctx.tenant, [%Log{timestamp_ns: 1, body: "checkout completed", service: "checkout"}])
    before = for tenant <- [ctx.tenant, other], do: S3.query(:metrics, tenant, [])
    logs = S3.query(:logs, ctx.tenant, [])
    worker = start_supervised!({CompactionWorker, Map.put(ctx.config, :compaction_options, grace_ms: 0)})
    send(worker, :compact)
    _ = :sys.get_state(worker, 60_000)
    assert for(tenant <- [ctx.tenant, other], do: S3.query(:metrics, tenant, [])) == before
    assert S3.query(:logs, ctx.tenant, []) == logs
    assert length(load(ctx).segments) == 1
    assert length(load(%{ctx | tenant: other}).segments) == 1
  end

  test "two real compactors race without leaving the losing replacement behind", ctx do
    for ts <- 1..4, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    before = S3.query(:metrics, ctx.tenant, [])
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", :replacement} => owner}})
    supervisor = start_supervised!(Task.Supervisor)

    tasks =
      for _ <- 1..2,
          do: Task.Supervisor.async_nolink(supervisor, fn -> MetricsCompactor.compact(ctx.tenant, ctx.config) end)

    assert_receive {:storage_barrier, first, "PUT", first_key}, 30_000
    assert_receive {:storage_barrier, second, "PUT", second_key}, 30_000
    assert first_key != second_key
    send(first, {:release_storage, first_key})
    send(second, {:release_storage, second_key})
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, %{merged: 4}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :compaction_conflict})) == 1
    assert S3.query(:metrics, ctx.tenant, []) == before

    assert Agent.get(ctx.agent, fn state ->
             Enum.count(state.objects, fn {key, _} -> String.contains?(key, "-compact-") end)
           end) == 1
  end

  test "bounded cleanup rotates past permanent failures and never repeats completed deletions", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    failed = load(ctx).segments |> Enum.map(& &1.key) |> Enum.min()
    assert {:ok, %{merged: 3}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    Agent.update(ctx.agent, &%{&1 | faults: %{{"DELETE", failed} => {403, :before, 100}}})

    assert {:error, {:cleanup_failed, [{^failed, _}]}} =
             MetricsCompactor.cleanup(ctx.tenant, ctx.config, max_deletions: 1)

    assert {:ok, 1} = MetricsCompactor.cleanup(ctx.tenant, ctx.config, max_deletions: 1)
    assert {:ok, 1} = MetricsCompactor.cleanup(ctx.tenant, ctx.config, max_deletions: 1)

    assert {:error, {:cleanup_failed, [{^failed, _}]}} =
             MetricsCompactor.cleanup(ctx.tenant, ctx.config, max_deletions: 1)

    assert Agent.get(ctx.agent, &length(&1.deletes)) == 2
    manifest = load(ctx)
    assert Enum.count(manifest.retired, fn {_, retirement} -> retirement.deleted? end) == 2
    assert {:ok, records} = S3.query(:metrics, ctx.tenant, [])
    assert length(records) == 3
  end

  test "an ingest retry overlapping cleanup publication schedules its re-upload for deletion", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)], idempotency_key: "#{ts}"))
    source = hd(load(ctx).segments)
    {:ok, blob} = ObjectStore.get(ctx.config, source.key)
    before = S3.query(:metrics, ctx.tenant, [])
    assert {:ok, %{merged: 3}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    manifest_key = Manifest.manifest_key(ctx.tenant, "metrics")

    Agent.update(ctx.agent, fn state ->
      %{
        state
        | hook: fn state ->
            {_, body} = Map.fetch!(state.objects, manifest_key)
            {:ok, current} = Manifest.decode(body)
            updated = Manifest.merge(current, [source]) |> Manifest.encode() |> IO.iodata_to_binary()

            objects =
              state.objects
              |> Map.put(source.key, {"\"retry\"", blob})
              |> Map.put(manifest_key, {"\"retry-manifest\"", updated})

            %{state | objects: objects}
          end
      }
    end)

    assert {:ok, 3} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    refute load(ctx).retired[source.key].deleted?
    assert {:ok, ^blob} = ObjectStore.get(ctx.config, source.key)
    assert {:ok, 1} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert {:error, :not_found} = ObjectStore.get(ctx.config, source.key)
    assert {:ok, 0} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert S3.query(:metrics, ctx.tenant, []) == before
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(3, 1.0)], idempotency_key: "3")
    assert S3.query(:metrics, ctx.tenant, []) == before
    assert {:ok, 1} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert {:error, :not_found} = ObjectStore.get(ctx.config, source.key)
  end

  test "background maintenance isolates a poison tenant discovered from durable manifests", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    poison = ctx.tenant <> "-poison"
    prefix = "tenants/#{poison}/v4/signal=metrics/date=2026-10-01/hour=00/"

    sources =
      for i <- 1..2 do
        key = prefix <> "bad-#{i}.parquet"
        {:ok, _} = ObjectStore.put(ctx.config, key, "corrupt")
        Segment.build(key, i, i, 1, 7)
      end

    manifest = Manifest.merge(Manifest.new(), sources)

    {:ok, etag} =
      ObjectStore.put(
        ctx.config,
        Manifest.manifest_key(poison, "metrics"),
        Manifest.encode(manifest) |> IO.iodata_to_binary()
      )

    ManifestCache.put(poison, "metrics", manifest, etag)
    lists = Agent.get(ctx.agent, & &1.lists)
    worker = start_supervised!({CompactionWorker, ctx.config})
    send(worker, :compact)
    _ = :sys.get_state(worker, 60_000)
    assert length(load(ctx).segments) == 1
    assert load(%{ctx | tenant: poison}).segments == manifest.segments
    assert Agent.get(ctx.agent, & &1.lists) == lists + 1
  end

  test "a missing compacted manifest fails closed instead of rebuilding an incomplete snapshot", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    assert {:ok, %{merged: 3}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, 3} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert :ok = ObjectStore.delete(ctx.config, Manifest.manifest_key(ctx.tenant, "metrics"))
    stop_supervised!(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert {:error, :compacted_manifest_missing} = S3.query(:metrics, ctx.tenant, [])
    assert {:error, :compacted_manifest_missing} = S3.append(:metrics, ctx.tenant, [sample(4, 1.0)])
  end

  test "background compaction requires explicit activation after writer upgrades" do
    assert CompactionWorker.children(%{}) == []
    assert CompactionWorker.children(%{compaction_enabled: false}) == []
    config = %{compaction_enabled: true}
    assert CompactionWorker.children(config) == [{CompactionSupervision, config}]
    assert {:ok, %Manifest{version: 1, retired: %{}}} = Manifest.decode(~s({"v":1,"s":[]}))
    assert {:error, :unsupported_manifest_version} = Manifest.decode(~s({"v":99,"s":[]}))
    assert {:error, :invalid_manifest} = Manifest.decode(~s({"v":2,"s":[]}))
  end

  test "cleanup during a running query restarts the whole scan without duplicate samples", ctx do
    for ts <- 1..4, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    before = S3.query(:metrics, ctx.tenant, [])
    first_key = hd(load(ctx).segments).key
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"GET", first_key} => owner}})
    supervisor = start_supervised!(Task.Supervisor)
    query = Task.Supervisor.async_nolink(supervisor, fn -> S3.query(:metrics, ctx.tenant, []) end)
    assert_receive {:storage_barrier, reader, "GET", ^first_key}, 30_000
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    assert {:ok, %{merged: 4}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, 4} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    send(reader, {:release_storage, first_key})
    assert Task.await(query, 10_000) == before
  end

  test "a delayed query retry cannot overwrite a cache entry containing a later acknowledged append", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    before = S3.query(:metrics, ctx.tenant, [])
    snapshot = load(ctx)
    assert {:ok, %{merged: 3}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, 3} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    ManifestCache.put(ctx.tenant, "metrics", snapshot, "obsolete")
    Runtime.put_env(:pulse, S3, Map.put(ctx.config, :refresh_stale_ms, 60_000))
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    owner = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"GET", key} => owner}})
    supervisor = start_supervised!(Task.Supervisor)
    query = Task.Supervisor.async_nolink(supervisor, fn -> S3.query(:metrics, ctx.tenant, []) end)
    assert_receive {:storage_barrier, reader, "GET", ^key}, 30_000
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(4, 1.0)])
    current = ManifestCache.get(ctx.tenant, "metrics")
    send(reader, {:release_storage, key})
    assert Task.await(query, 10_000) == before
    assert ManifestCache.get(ctx.tenant, "metrics") == current
    assert {:ok, records} = S3.query(:metrics, ctx.tenant, [])
    assert Enum.map(records, & &1.timestamp_ns) == [4, 3, 2, 1]
  end

  test "repeated bounded merges converge without exceeding row or segment budgets", ctx do
    for batch <- 0..11 do
      records = for row <- 1..3, do: sample(batch * 3 + row, row / 1)
      assert :ok = S3.append(:metrics, ctx.tenant, records)
    end

    before = S3.query(:metrics, ctx.tenant, [])

    for _ <- 1..4 do
      assert {:ok, %{merged: 3, replacement: key}} =
               MetricsCompactor.compact(ctx.tenant, ctx.config, max_segments: 3, max_rows: 9)

      assert Enum.find(load(ctx).segments, &(&1.key == key)).row_count == 9
    end

    assert {:ok, %{merged: 0}} = MetricsCompactor.compact(ctx.tenant, ctx.config, max_segments: 3, max_rows: 9)
    assert length(load(ctx).segments) == 4
    assert S3.query(:metrics, ctx.tenant, []) == before
  end

  test "selection tries another candidate when an otherwise valid segment fills the byte budget alone" do
    manifest = %Manifest{
      segments: [
        Segment.build("hour/a", 1, 1, 1, 100),
        Segment.build("hour/b", 2, 2, 2, 45),
        Segment.build("hour/c", 3, 3, 2, 45)
      ]
    }

    selected = MetricsCompactor.select(manifest, max_input_bytes: 100, max_rows: 4)
    assert Enum.map(selected, & &1.key) == ["hour/b", "hour/c"]
  end

  test "background operation exceptions are isolated and maintenance recovers after configuration is repaired", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    worker = start_supervised!({CompactionWorker, Map.delete(ctx.config, :bucket)})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        send(worker, :compact)
        _ = :sys.get_state(worker, 60_000)
      end)

    assert log =~ "discovery raised tenant="
    :sys.replace_state(worker, fn _ -> ctx.config end)
    ProcessGroup.join(CompactionOwnership.scope(), CompactionOwnership.group(ctx.config), worker)
    send(worker, :compact)
    _ = :sys.get_state(worker, 60_000)
    assert length(load(ctx).segments) == 1
  end

  test "a cache miss reloads external publications instead of freshly stamping the owner's old snapshot", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(1, 1.0)])
    {:ok, payload, mn, mx} = S3.encode_segment(:metrics, [sample(2, 2.0)])
    key = S3.object_key(ctx.tenant, "metrics", mn, mx, "external", nil)
    assert {:ok, _} = ObjectStore.put(ctx.config, key, payload)
    manifest_key = Manifest.manifest_key(ctx.tenant, "metrics")
    {:ok, etag, body} = ObjectStore.get_if_none_match(ctx.config, manifest_key, nil)
    {:ok, current} = Manifest.decode(body)
    updated = Manifest.merge(current, [Segment.build(key, mn, mx, 1, byte_size(payload))])

    assert {:ok, _} =
             ObjectStore.put_if_match(ctx.config, manifest_key, Manifest.encode(updated) |> IO.iodata_to_binary(), etag)

    ManifestCache.drop(ctx.tenant, "metrics")
    assert {:ok, records} = S3.query(:metrics, ctx.tenant, [])
    assert Enum.map(records, & &1.timestamp_ns) == [2, 1]
  end

  test "an unconfigured object-storage adapter still fails with a clear configuration error" do
    Runtime.delete_env(:pulse, S3)
    assert_raise RuntimeError, ~r/is not configured/, fn -> S3.query(:metrics, "unconfigured", []) end
  end

  test "exhausted conditional conflicts reclaim a replacement proven never published", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    before = S3.query(:metrics, ctx.tenant, [])
    manifest = load(ctx)
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {412, :before, 5}}})
    assert {:error, :cas_retries_exhausted} = MetricsCompactor.compact(ctx.tenant, ctx.config)
    assert load(ctx) == manifest
    assert S3.query(:metrics, ctx.tenant, []) == before

    assert Agent.get(ctx.agent, fn state ->
             Enum.count(state.objects, fn {key, _} -> String.contains?(key, "-compact-") end)
           end) == 0
  end

  test "a repeatedly failing cleanup key does not rewrite unchanged completion state", ctx do
    for ts <- 1..2, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    retired = load(ctx).retired |> Map.keys() |> Enum.sort()
    Agent.update(ctx.agent, &%{&1 | faults: Map.new(retired, fn key -> {{"DELETE", key}, {403, :before, 100}} end)})
    assert {:error, {:cleanup_failed, _}} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    key = Manifest.manifest_key(ctx.tenant, "metrics")
    {:ok, etag, body} = ObjectStore.get_if_none_match(ctx.config, key, nil)
    assert {:error, {:cleanup_failed, _}} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert {:ok, ^etag, ^body} = ObjectStore.get_if_none_match(ctx.config, key, nil)
  end

  @tag manifest_format: "flat"
  test "an owner loaded before compaction preserves the new metadata when background compaction is disabled", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    assert load(ctx).version == 1
    assert CompactionWorker.children(ctx.config) == []
    assert {:ok, %{merged: 3}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, 3} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    retired = load(ctx)
    assert :ok = S3.append(:metrics, ctx.tenant, [sample(4, 1.0)])
    updated = load(ctx)
    assert updated.version == 2
    assert updated.retired == retired.retired
    assert updated.cleanup_cursor == retired.cleanup_cursor
    assert {:ok, records} = S3.query(:metrics, ctx.tenant, [])
    assert Enum.map(records, & &1.timestamp_ns) == [4, 3, 2, 1]
  end

  test "selection respects bytes, rows, segment count and hour boundaries" do
    segments = for i <- 1..6, do: Segment.build("hour/a#{i}", i, i, 10, 100)

    manifest = %Manifest{
      segments: segments ++ [Segment.build("other/b", 0, 0, 1, 100), Segment.build("hour/unknown", 0, 0, 1)]
    }

    assert length(MetricsCompactor.select(manifest, max_segments: 2)) == 2
    assert length(MetricsCompactor.select(manifest, max_input_bytes: 300)) == 3
    assert length(MetricsCompactor.select(manifest, max_rows: 20)) == 2
    assert MetricsCompactor.select(manifest, max_input_bytes: 100) == []
    assert MetricsCompactor.select(manifest, small_segment_bytes: 99) == []
  end

  test "rendezvous agreement, signal separation, and minimal reassignment on joins and departures" do
    members = [:a@host, :b@host, :c@host]
    assert CompactionOwnership.owner("tenant", "metrics", []) == nil

    owners =
      for tenant <- 1..500 do
        key = "tenant-#{tenant}"
        owner = CompactionOwnership.owner(key, "metrics", members)
        assert owner == CompactionOwnership.owner(key, "metrics", Enum.reverse(members, members))
        {key, owner}
      end

    assert Enum.uniq(Enum.map(owners, &elem(&1, 1))) |> Enum.sort() == Enum.sort(members)

    for {tenant, original} <- owners do
      joined = CompactionOwnership.owner(tenant, "metrics", [:d@host | members])
      assert joined in [original, :d@host]
      departed = CompactionOwnership.owner(tenant, "metrics", members -- [:b@host])
      if original != :b@host, do: assert(departed == original)
    end

    assert Enum.any?(owners, fn {tenant, metrics} ->
             CompactionOwnership.owner(tenant, "logs", members) != metrics
           end)
  end

  test "connected workers discover another instance's tenants and avoid duplicate source reads and uploads", ctx do
    for ts <- 1..4, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    before = S3.query(:metrics, ctx.tenant, [])
    {first, first_node} = compaction_peer(ctx.config)
    {second, second_node} = compaction_peer(ctx.config)
    connect_peers(first, second, first_node, second_node, ctx.config)

    # Both remote caches are empty: ingest and the first query happened here.
    for peer <- [first, second] do
      assert CompactionPeer.call(peer, ManifestCache, :tenants, ["metrics"]) == []
    end

    reads(ctx.agent)
    test_process = self()
    Agent.update(ctx.agent, &%{&1 | requests: [], barriers: %{{"PUT", :replacement} => test_process}})
    owner = CompactionOwnership.owner(ctx.tenant, "metrics", [first_node, second_node])
    {owner_peer, non_owner} = if owner == first_node, do: {first, second}, else: {second, first}
    supervisor = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        CompactionPeer.call(owner_peer, CompactionPeer, :pass, [], 20_000)
      end)

    assert_receive {:storage_barrier, request, "PUT", replacement}, 30_000
    # The sources are still active while the owner waits for its upload response.
    assert CompactionPeer.call(non_owner, CompactionPeer, :pass, []) == :ok
    assert reads(ctx.agent) == 4
    assert replacement_uploads(ctx.agent) == 1
    send(request, {:release_storage, replacement})
    assert Task.await(task, 20_000) == :ok
    assert replacement_uploads(ctx.agent) == 1
    assert length(load(ctx).segments) == 1
    assert S3.query(:metrics, ctx.tenant, []) == before
  end

  test "owner node departure transfers cleanup and idle tenant work without a cache handoff", ctx do
    for ts <- 1..4, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    before = S3.query(:metrics, ctx.tenant, [])
    {first, first_node} = compaction_peer(ctx.config)
    {second, second_node} = compaction_peer(ctx.config)
    connect_peers(first, second, first_node, second_node, ctx.config)
    owner = CompactionOwnership.owner(ctx.tenant, "metrics", [first_node, second_node])

    {owner_peer, survivor, survivor_node} =
      if owner == first_node, do: {first, second, second_node}, else: {second, first, first_node}

    assert CompactionPeer.call(owner_peer, CompactionPeer, :pass, []) == :ok
    assert load(ctx).retired |> Map.keys() |> length() == 4
    assert Agent.get(ctx.agent, & &1.deletes) == []
    stop_supervised!(Process.get({CompactionPeer, owner_peer}))
    assert CompactionPeer.call(survivor, CompactionPeer, :await_members, [ctx.config, [survivor_node]]) == :ok

    # Expire durable deadlines without warming the survivor's cache.
    manifest = load(ctx)
    retired = Map.new(manifest.retired, fn {key, retirement} -> {key, %{retirement | delete_after: 0}} end)

    assert {:ok, _} =
             ObjectStore.put(
               ctx.config,
               Manifest.manifest_key(ctx.tenant, "metrics"),
               Manifest.encode(%{manifest | retired: retired}) |> IO.iodata_to_binary()
             )

    assert CompactionPeer.call(survivor, ManifestCache, :tenants, ["metrics"]) == []
    assert CompactionPeer.call(survivor, CompactionPeer, :pass, []) == :ok
    assert length(Agent.get(ctx.agent, & &1.deletes)) == 4
    assert Enum.all?(load(ctx).retired, fn {_, retirement} -> retirement.deleted? end)
    assert S3.query(:metrics, ctx.tenant, []) == before
  end

  test "inconsistent membership permits overlapping workers but only one safe publication", ctx do
    for ts <- 1..4, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    before = S3.query(:metrics, ctx.tenant, [])
    {first, first_node} = compaction_peer(ctx.config)
    {second, second_node} = compaction_peer(ctx.config)
    # Deliberately leave the nodes disconnected, as in a partition.
    assert CompactionPeer.call(first, CompactionOwnership, :members, [ctx.config]) == [first_node]
    assert CompactionPeer.call(second, CompactionOwnership, :members, [ctx.config]) == [second_node]
    test_process = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", :replacement} => test_process}})
    supervisor = start_supervised!(Task.Supervisor)

    tasks =
      for peer <- [first, second],
          do:
            Task.Supervisor.async_nolink(supervisor, fn ->
              CompactionPeer.call(peer, CompactionPeer, :pass, [], 20_000)
            end)

    assert_receive {:storage_barrier, one, "PUT", one_key}, 30_000
    assert_receive {:storage_barrier, two, "PUT", two_key}, 30_000
    send(one, {:release_storage, one_key})
    send(two, {:release_storage, two_key})
    assert Enum.map(tasks, &Task.await(&1, 20_000)) == [:ok, :ok]
    assert length(load(ctx).segments) == 1
    assert map_size(load(ctx).retired) == 4
    assert replacement_uploads(ctx.agent) == 2

    assert Agent.get(ctx.agent, fn state ->
             Enum.count(state.objects, fn {key, _} -> String.contains?(key, "-compact-") end)
           end) == 1

    assert S3.query(:metrics, ctx.tenant, []) == before
    connect_peers(first, second, first_node, second_node, ctx.config)
    for peer <- [first, second], do: CompactionPeer.call(peer, CompactionPeer, :pass, [])
    assert replacement_uploads(ctx.agent) == 2
  end

  test "failed worker loses eligibility even while its node remains connected", ctx do
    {first, first_node} = compaction_peer(ctx.config)
    {second, second_node} = compaction_peer(ctx.config)
    connect_peers(first, second, first_node, second_node, ctx.config)
    assert CompactionPeer.call(first, Supervisor, :terminate_child, [CompactionSupervision, CompactionWorker]) == :ok
    assert CompactionPeer.call(second, CompactionPeer, :await_members, [ctx.config, [second_node]]) == :ok
    assert CompactionPeer.call(second, Node, :list, []) == [first_node]

    assert CompactionPeer.call(first, Supervisor, :restart_child, [CompactionSupervision, CompactionWorker]) |> elem(0) ==
             :ok

    assert CompactionPeer.call(second, CompactionPeer, :await_members, [ctx.config, [first_node, second_node]]) == :ok
  end

  test "tenant prefix discovery survives a lost cache and missing metric manifests never adopt orphan segments", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    assert {:ok, _} = ObjectStore.put(ctx.config, "tenants/orphan/v4/signal=metrics/orphan.parquet", "unused")
    assert {:ok, _} = ObjectStore.put(ctx.config, Manifest.manifest_key("logs-only", "logs"), "unused")
    ManifestCache.reset()
    assert CompactionDiscovery.tenants(ctx.config) == {:ok, Enum.sort([ctx.tenant, "logs-only", "orphan"])}
    worker = start_supervised!({CompactionWorker, ctx.config})
    send(worker, :compact)
    _ = :sys.get_state(worker, 60_000)
    assert length(load(ctx).segments) == 1
  end

  test "owner failure after upload lets a survivor publish from the unchanged sources", ctx do
    for ts <- 1..4, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    before = S3.query(:metrics, ctx.tenant, [])
    {first, first_node} = compaction_peer(ctx.config)
    {second, second_node} = compaction_peer(ctx.config)
    connect_peers(first, second, first_node, second_node, ctx.config)
    owner = CompactionOwnership.owner(ctx.tenant, "metrics", [first_node, second_node])

    {owner_peer, survivor, survivor_node} =
      if owner == first_node, do: {first, second, second_node}, else: {second, first, first_node}

    test_process = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", :replacement} => test_process}})
    supervisor = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        try do
          CompactionPeer.call(owner_peer, CompactionPeer, :pass, [], 20_000)
        catch
          :exit, _ -> :owner_failed
        end
      end)

    assert_receive {:storage_barrier, request, "PUT", abandoned_key}, 30_000
    stop_supervised!(Process.get({CompactionPeer, owner_peer}))
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    send(request, {:release_storage, abandoned_key})
    assert Task.await(task, 20_000) == :owner_failed
    assert CompactionPeer.call(survivor, CompactionPeer, :await_members, [ctx.config, [survivor_node]]) == :ok
    assert length(load(ctx).segments) == 4
    assert CompactionPeer.call(survivor, CompactionPeer, :pass, []) == :ok
    assert length(load(ctx).segments) == 1
    refute Enum.any?(load(ctx).segments, &(&1.key == abandoned_key))
    assert S3.query(:metrics, ctx.tenant, []) == before
  end

  test "membership scope restart restores the worker registration", ctx do
    stop_supervised!(CompactionOwnership)
    stop_supervised!(CompactionTasks)
    supervisor = start_supervised!({CompactionSupervision, ctx.config})
    old_worker = Pulse.Runtime.whereis(CompactionWorker)
    ref = Process.monitor(old_worker)
    # The monitor signal must reach the worker before its supervisor shuts it down.
    _ = :sys.get_state(old_worker)
    Process.exit(Pulse.Runtime.whereis(CompactionOwnership.scope()), :kill)
    assert_receive {:DOWN, ^ref, :process, ^old_worker, :shutdown}
    _ = :sys.get_state(supervisor)
    assert Pulse.Runtime.whereis(CompactionWorker) != old_worker
    assert CompactionOwnership.members(ctx.config) == [node()]
  end

  test "a stalled metrics operation does not delay log maintenance", ctx do
    for ts <- 1..2, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    log = &%Log{timestamp_ns: &1, service: "api", body: "line"}
    for ts <- 1..2, do: assert(:ok = S3.append(:logs, ctx.tenant, [log.(ts)]))
    source = hd(load(ctx).segments).key
    parent = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"GET", source} => parent}})
    stop_supervised!(CompactionOwnership)
    stop_supervised!(CompactionTasks)
    config = Map.merge(ctx.config, %{log_compaction_enabled: true, compaction_interval_ms: 3_600_000})
    start_supervised!({CompactionSupervision, config})

    send(Pulse.Runtime.whereis(CompactionWorker), :compact)
    assert_receive {:storage_barrier, storage, "GET", ^source}, 30_000
    logs_worker = Pulse.Runtime.whereis(Module.concat(CompactionWorker, "logs"))
    send(logs_worker, :compact)
    _ = :sys.get_state(logs_worker, 30_000)
    {:ok, _, body} = ObjectStore.get_if_none_match(ctx.config, Manifest.manifest_key(ctx.tenant, "logs"), nil)
    assert {:ok, %{segments: [_]}} = Manifest.decode(body)

    send(storage, {:release_storage, source})
    _ = :sys.get_state(Pulse.Runtime.whereis(CompactionWorker), 30_000)
    assert [_] = load(ctx).segments
  end

  test "store identities isolate eligibility and discovery failures retry without touching sources", ctx do
    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, 1.0)]))
    worker = start_supervised!({CompactionWorker, ctx.config})
    assert CompactionOwnership.members(Map.put(ctx.config, :bucket, "other")) == []
    Agent.update(ctx.agent, &%{&1 | faults: %{{"GET", "/pulse"} => {403, :before, 1}}, requests: []})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        send(worker, :compact)
        _ = :sys.get_state(worker, 60_000)
      end)

    assert log =~ "discovery failed"
    assert replacement_uploads(ctx.agent) == 0
    assert length(load(ctx).segments) == 3
    send(worker, :compact)
    _ = :sys.get_state(worker, 60_000)
    assert length(load(ctx).segments) == 1
  end

  test "a joining eligible node takes its new tenants without a cache transfer", ctx do
    {first, first_node} = compaction_peer(ctx.config)
    {second, second_node} = compaction_peer(ctx.config)

    tenant =
      Enum.find_value(1..100, fn number ->
        tenant = "joining-#{number}"
        if CompactionOwnership.owner(tenant, "metrics", [first_node, second_node]) == second_node, do: tenant
      end)

    assert is_binary(tenant)

    assert {:ok, _} =
             ObjectStore.put(
               ctx.config,
               Manifest.manifest_key(tenant, "metrics"),
               Manifest.encode(Manifest.new()) |> IO.iodata_to_binary()
             )

    for ts <- 1..3, do: assert(:ok = S3.append(:metrics, tenant, [sample(ts, ts / 1)]))
    assert CompactionPeer.call(first, CompactionPeer, :pass, []) == :ok
    assert length(load(%{ctx | tenant: tenant}).segments) == 1
    for ts <- 4..6, do: assert(:ok = S3.append(:metrics, tenant, [sample(ts, ts / 1)]))
    before = S3.query(:metrics, tenant, [])
    connect_peers(first, second, first_node, second_node, ctx.config)
    assert CompactionPeer.call(second, ManifestCache, :tenants, ["metrics"]) == []
    reads(ctx.agent)
    uploads = replacement_uploads(ctx.agent)
    assert CompactionPeer.call(first, CompactionPeer, :pass, []) == :ok
    assert reads(ctx.agent) == 0
    assert replacement_uploads(ctx.agent) == uploads
    assert CompactionPeer.call(second, CompactionPeer, :pass, []) == :ok
    assert reads(ctx.agent) == 4
    assert replacement_uploads(ctx.agent) == uploads + 1
    assert S3.query(:metrics, tenant, []) == before
  end

  test "connected nodes with compaction disabled are not eligible", ctx do
    {enabled, enabled_node} = compaction_peer(ctx.config)
    {disabled, disabled_node} = compaction_peer(Map.put(ctx.config, :compaction_enabled, false))
    assert CompactionPeer.call(enabled, Node, :connect, [disabled_node]) == true
    assert CompactionPeer.call(disabled, Node, :list, []) == [enabled_node]
    assert CompactionPeer.call(disabled, Process, :whereis, [CompactionWorker]) == nil
    assert CompactionPeer.call(enabled, CompactionOwnership, :members, [ctx.config]) == [enabled_node]
  end

  test "delimiter discovery follows pages without returning the segment backlog", ctx do
    for i <- 1..6 do
      assert {:ok, _} = ObjectStore.put(ctx.config, Manifest.manifest_key("tenant-#{i}", "metrics"), "manifest")
    end

    for i <- 1..100 do
      assert {:ok, _} =
               ObjectStore.put(ctx.config, "tenants/#{ctx.tenant}/v4/signal=metrics/segment-#{i}.parquet", "segment")
    end

    lists = Agent.get(ctx.agent, & &1.lists)
    assert {:ok, tenants} = CompactionDiscovery.tenants(ctx.config)
    assert tenants == Enum.sort([ctx.tenant | Enum.map(1..6, &"tenant-#{&1}")])
    assert Agent.get(ctx.agent, & &1.lists) == lists + 4
  end

  test "a stalled owner withdraws eligibility and lets another worker finish safely", ctx do
    for ts <- 1..4, do: assert(:ok = S3.append(:metrics, ctx.tenant, [sample(ts, ts / 1)]))
    before = S3.query(:metrics, ctx.tenant, [])
    {first, first_node} = compaction_peer(ctx.config)
    {second, second_node} = compaction_peer(ctx.config)
    connect_peers(first, second, first_node, second_node, ctx.config)
    owner = CompactionOwnership.owner(ctx.tenant, "metrics", [first_node, second_node])

    {owner_peer, survivor, survivor_node} =
      if owner == first_node, do: {first, second, second_node}, else: {second, first, first_node}

    assert CompactionPeer.call(owner_peer, CompactionPeer, :timeout, [1_000]) == :ok
    source = hd(load(ctx).segments).key
    test_process = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"GET", source} => test_process}})
    supervisor = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        CompactionPeer.call(owner_peer, CompactionPeer, :pass, [], 10_000)
      end)

    assert_receive {:storage_barrier, request, "GET", ^source}, 30_000
    assert Task.await(task, 10_000) == :ok
    assert CompactionPeer.call(survivor, CompactionPeer, :await_members, [ctx.config, [survivor_node]]) == :ok
    # The old native call has not returned: another pass must neither rejoin
    # nor admit another task while that call remains in flight.
    assert CompactionPeer.call(owner_peer, CompactionPeer, :pass, []) == :ok
    assert CompactionPeer.call(survivor, CompactionOwnership, :members, [ctx.config]) == [survivor_node]
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    assert CompactionPeer.call(survivor, CompactionPeer, :pass, []) == :ok
    assert replacement_uploads(ctx.agent) == 1
    send(request, {:release_storage, source})
    assert length(load(ctx).segments) == 1
    assert map_size(load(ctx).retired) == 4
    assert S3.query(:metrics, ctx.tenant, []) == before
    assert CompactionPeer.call(owner_peer, CompactionPeer, :await_tasks, []) == :ok
    Agent.update(ctx.agent, &%{&1 | requests: []})
    assert CompactionPeer.call(owner_peer, CompactionPeer, :pass, []) == :ok
    manifest_key = Manifest.manifest_key(ctx.tenant, "metrics")
    # The worker rejoins but defers the slow tenant during its retry backoff.
    refute Agent.get(ctx.agent, &Enum.member?(&1.requests, {"GET", manifest_key}))
    connect_peers(first, second, first_node, second_node, ctx.config)
  end

  test "a worker starting while earlier supervised work remains does not advertise eligibility", ctx do
    {:ok, task} =
      Task.Supervisor.start_child(CompactionTasks, fn ->
        receive do
          :finish -> :ok
        end
      end)

    ref = Process.monitor(task)
    worker = start_supervised!({CompactionWorker, ctx.config})
    assert CompactionOwnership.members(ctx.config) == []
    send(task, :finish)
    assert_receive {:DOWN, ^ref, :process, ^task, :normal}
    _ = :sys.get_state(Pulse.Runtime.name(CompactionTasks))
    send(worker, :compact)
    _ = :sys.get_state(worker, 60_000)
    assert CompactionOwnership.members(ctx.config) == [node()]
  end

  defp compaction_peer(config) do
    config = config |> Map.put_new(:compaction_enabled, true) |> Map.put(:compaction_interval_ms, 3_600_000)
    id = {CompactionPeer, make_ref()}
    peer = start_supervised!(%{id: id, start: {CompactionPeer, :start_link, [{self(), config}]}, restart: :temporary})
    assert_receive {:compaction_peer, ^peer, member}, 10_000
    # Return an address usable by stop_supervised! as well as peer calls.
    Process.put({CompactionPeer, peer}, id)
    {peer, member}
  end

  defp connect_peers(first, second, first_node, second_node, config) do
    assert CompactionPeer.call(first, Node, :connect, [second_node]) == true

    for peer <- [first, second] do
      assert CompactionPeer.call(peer, CompactionPeer, :await_members, [config, [first_node, second_node]]) == :ok
    end
  end

  defp replacement_uploads(agent) do
    Agent.get(agent, fn state ->
      Enum.count(state.requests, fn {method, key} -> method == "PUT" and String.contains?(key, "-compact-") end)
    end)
  end
end
