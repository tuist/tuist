defmodule Pulse.PromQL.CurrentHourReadsTest do
  @moduledoc """
  Segment and row counts of PromQL panels over an hour that is not
  finalized yet, at the shape of production remote write: every flush holds
  a slice of all series and so every metric name, which name summaries
  cannot prune. Consolidation (`MetricTiers.consolidate/3`) groups settled
  raw segments by metric so a panel reads one segment per consolidated
  batch; partitioned finalization (`:max_rows` below the hour) splits the
  hour by metric-name hash and still answers identically.

  3,000 series (40 metrics x 75 targets) are scraped every 30 s for ten
  minutes, flushed every 2 s in 15 slices of 200 consecutive series:
  300 raw segments of 200 rows.
  """
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.PromQL.Evaluator
  alias Pulse.QueryLimit
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Runtime.Task
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.CompactionOwnership
  alias Pulse.Storage.S3.CompactionSupervision
  alias Pulse.Storage.S3.CompactionTasks
  alias Pulse.Storage.S3.CompactionWorker
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.TuistMetricHistory

  @moduletag timeout: 300_000

  @second 1_000_000_000
  @minute 60 * @second
  @hour 60 * @minute
  @metrics 40
  @targets 75
  @series @metrics * @targets
  @flushes 300

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
      access_key_id: "current-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      query_prefetch: 4
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    tenant = "current-#{System.unique_integer([:positive])}"
    manifest = IO.iodata_to_binary(Manifest.encode(Manifest.new()))
    {:ok, _} = ObjectStore.put(config, Manifest.manifest_key(tenant, "metrics"), manifest)

    t0 = div(System.os_time(:nanosecond), @hour) * @hour - 2 * @hour + 5 * @minute
    per = div(@series, 15)

    flushes =
      for n <- 0..(@flushes - 1) do
        ts = t0 + n * 2 * @second

        for offset <- 0..(per - 1) do
          i = rem(n * per + offset, @series)
          target = div(i, @metrics)

          %MetricSample{
            timestamp_ns: ts,
            value: (n * 7 + i) * 1.0,
            labels: %{
              "__name__" => "m_#{rem(i, @metrics)}",
              "instance" => "10.0.0.#{target}:9090",
              "job" => "job-#{rem(target, 5)}"
            }
          }
        end
      end

    Enum.each(flushes, &(:ok = S3.append(:metrics, tenant, &1)))
    records = List.flatten(flushes)
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    :ok = Storage.append(:metrics, tenant <> "-memory", records)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    reads(agent)
    %{agent: agent, config: config, tenant: tenant, t0: t0, records: records}
  end

  defp reads(agent) do
    Agent.get_and_update(agent, fn state ->
      {Enum.count(state.reads, &String.ends_with?(&1, ".parquet")), %{state | reads: []}}
    end)
  end

  defp memory(ctx, query, opts) do
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    result = Evaluator.query(query, ctx.tenant <> "-memory", opts)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    result
  end

  # The query reads exactly `segments` objects and matches exactly `rows`
  # rows: it succeeds within those budgets and fails one below each.
  defp assert_cost(ctx, query, opts, segments, rows) do
    assert {:ok, result} = Evaluator.query(query, ctx.tenant, opts)
    assert reads(ctx.agent) == segments

    Runtime.put_env(:pulse, Evaluator, max_scan_segments: segments, max_scan_rows: rows)
    assert {:ok, ^result} = Evaluator.query(query, ctx.tenant, opts)

    Runtime.put_env(:pulse, Evaluator, max_scan_segments: segments, max_scan_rows: rows - 1)
    assert {:error, :query_scan_limit} = Evaluator.query(query, ctx.tenant, opts)
    assert %{limit: :max_scan_rows} = QueryLimit.take()

    Runtime.put_env(:pulse, Evaluator, max_scan_segments: segments - 1, max_scan_rows: rows)
    assert {:error, :query_scan_limit} = Evaluator.query(query, ctx.tenant, opts)
    assert %{limit: :max_scan_segments} = QueryLimit.take()

    Runtime.put_env(:pulse, Evaluator, [])
    reads(ctx.agent)
    result
  end

  defp tiers(ctx) do
    {:ok, manifest, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    Enum.frequencies_by(manifest.segments, &Segment.metric_tier/1)
  end

  # A dashboard over the ten minutes: `sum by (job) (rate(m_1[5m]))` at
  # 60-second steps and `count(m_3)` at the end.
  defp panels(ctx) do
    range = %{start_ts_ns: ctx.t0 + 5 * @minute, end_ts_ns: ctx.t0 + 10 * @minute, step_ns: @minute}

    [
      {~s|sum by (job) (rate(m_1[5m]))|, range, ctx.t0 + 1},
      {~s|count(m_3)|, %{end_ts_ns: ctx.t0 + 10 * @minute}, ctx.t0 + 5 * @minute + 1}
    ]
  end

  # Samples of `metric` from `from` to the end of the history.
  defp rows(ctx, metric, from),
    do: Enum.count(ctx.records, &(&1.labels["__name__"] == metric and &1.timestamp_ns >= from))

  defp assert_samples(ctx) do
    assert {:ok, actual} =
             S3.query(:metrics, ctx.tenant, start_ts: ctx.t0, end_ts: ctx.t0 + 10 * @minute, limit: 60_001)

    samples = &Enum.sort(Enum.map(&1, fn sample -> {sample.labels, sample.timestamp_ns, sample.value} end))
    assert samples.(actual) == samples.(ctx.records)
  end

  test "raw segments of the current hour: every panel reads every segment", ctx do
    for {{query, opts, from}, metric} <- Enum.zip(panels(ctx), ["m_1", "m_3"]) do
      segments = Enum.count(0..(@flushes - 1), &(ctx.t0 + &1 * 2 * @second >= from))
      result = assert_cost(ctx, query, opts, segments, rows(ctx, metric, from))
      assert {:ok, ^result} = memory(ctx, query, opts)
    end
  end

  test "consolidated segments: a panel reads its metric's segment of each batch", ctx do
    before = for {query, opts, _} <- panels(ctx), do: Evaluator.query(query, ctx.tenant, opts)
    opts = [consolidate_settle_ms: 0, consolidate_min_rows: 1, consolidate_max_rows: 30_000, target_rows: 1_500]

    # Two batches of 150 segments (30,000 rows): each metric's 750 rows of a
    # batch land in one grouped segment, two metrics per segment.
    assert {:ok, %{sources: 150, grouped: 20}} = MetricTiers.consolidate(ctx.tenant, ctx.config, opts)
    assert {:ok, %{sources: 150, grouped: 20}} = MetricTiers.consolidate(ctx.tenant, ctx.config, opts)
    assert {:ok, %{hour: nil}} = MetricTiers.consolidate(ctx.tenant, ctx.config, opts)
    assert tiers(ctx) == %{grouped: 40}
    reads(ctx.agent)

    for {{{query, opts, from}, metric}, expected} <- Enum.zip([Enum.zip(panels(ctx), ["m_1", "m_3"]), before]) do
      # The rate panel's window starts in the first batch; count(m_3)'s
      # five-minute lookback starts exactly at the second.
      segments = if from < ctx.t0 + 5 * @minute, do: 2, else: 1
      assert {:ok, _} = expected
      assert ^expected = {:ok, assert_cost(ctx, query, opts, segments, rows(ctx, metric, from))}
    end
  end

  test "recent panels recover within the byte cap while historical maintenance is stalled", ctx do
    {query, opts, _} = hd(panels(ctx))
    assert {:ok, expected} = memory(ctx, query, opts)
    {:ok, root, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    byte_cap = div(Enum.sum_by(root.segments, & &1.byte_size), 4)
    Runtime.put_env(:pulse, Evaluator, max_scan_bytes: byte_cap)
    assert {:error, :query_scan_limit} = Evaluator.query(query, ctx.tenant, opts)

    # rate's left-open window excludes the flush exactly at t0.
    assert %{limit: :max_scan_bytes, stage: :candidates, observed: bytes, metric_tiers: %{raw: {299, bytes}}} =
             detail = QueryLimit.take()

    assert QueryLimit.describe(detail) =~ "candidate tiers: raw: 299 segments / #{bytes} bytes"

    # An older eligible hour competes with recent grouping. Block its merge
    # in storage, not the worker's mailbox, just as a slow historical task
    # leaves the worker unable to run its next maintenance operation.
    for offset <- 1..2 do
      assert :ok =
               S3.append(:metrics, ctx.tenant, [
                 %MetricSample{
                   timestamp_ns: ctx.t0 - @hour + offset,
                   value: offset / 1,
                   labels: %{"__name__" => "old"}
                 }
               ])
    end

    {:ok, root, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    source = root.segments |> Enum.min_by(& &1.min_ts) |> Map.fetch!(:key)
    parent = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"GET", source} => parent}})

    config =
      Map.merge(ctx.config, %{
        compaction_enabled: true,
        compaction_interval_ms: 3_600_000,
        compaction_timeout_ms: 1_000,
        metric_finalize_timeout_ms: 1_000,
        manifest_backup_enabled: false,
        metric_consolidate_max_batches: 1,
        metric_finalize_options: [
          consolidate_settle_ms: 0,
          consolidate_min_rows: 1,
          consolidate_max_rows: 60_000,
          target_rows: 1_500
        ]
      })

    start_supervised!({CompactionSupervision, config})
    historical = Runtime.whereis(CompactionWorker)
    send(historical, :compact)
    assert_receive {:storage_barrier, storage, "GET", ^source}, 30_000
    _ = :sys.get_state(historical, 30_000)
    assert CompactionOwnership.members(config) == []
    assert [task] = Task.Supervisor.children(CompactionTasks)
    task_ref = Process.monitor(task)
    send(historical, :compact)
    _ = :sys.get_state(historical)
    assert [^task] = Task.Supervisor.children(CompactionTasks)

    grouping = Runtime.whereis(Module.concat(CompactionWorker, "metrics_grouping"))
    assert is_pid(grouping)
    assert CompactionOwnership.members(Map.put(config, :maintenance_operation, :metric_consolidate)) == [node()]
    send(grouping, :compact)
    _ = :sys.get_state(grouping, 60_000)
    reads(ctx.agent)
    assert {:ok, ^expected} = Evaluator.query(query, ctx.tenant, opts)
    assert reads(ctx.agent) == 1

    Runtime.put_env(:pulse, Evaluator, max_scan_bytes: 1)
    assert {:error, :query_scan_limit} = Evaluator.query(query, ctx.tenant, opts)
    assert %{metric_tiers: %{grouped: {1, grouped_bytes}}} = detail = QueryLimit.take()
    assert grouped_bytes > 1
    assert QueryLimit.describe(detail) =~ "candidate tiers: grouped: 1 segments / #{grouped_bytes} bytes"

    # Historical maintenance can finish against the concurrently changed
    # manifest without losing or duplicating recent samples.
    send(storage, {:release_storage, source})
    assert_receive {:DOWN, ^task_ref, :process, ^task, :normal}, 30_000
    Runtime.put_env(:pulse, Evaluator, [])
    assert {:ok, ^expected} = Evaluator.query(query, ctx.tenant, opts)
    assert_samples(ctx)
  end

  test "the historical lane leaves recent grouping's sources active", ctx do
    {query, opts, _} = hd(panels(ctx))
    assert {:ok, expected} = memory(ctx, query, opts)
    {:ok, root, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    byte_cap = div(Enum.sum_by(root.segments, & &1.byte_size), 4)
    Runtime.put_env(:pulse, Evaluator, max_scan_bytes: byte_cap)
    assert {:error, :query_scan_limit} = Evaluator.query(query, ctx.tenant, opts)
    assert %{limit: :max_scan_bytes, stage: :candidates} = QueryLimit.take()

    source = hd(root.segments).key
    parent = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"GET", source} => parent}})
    tasks = start_supervised!(Task.Supervisor)

    grouping =
      Task.Supervisor.async_nolink(tasks, fn ->
        MetricTiers.consolidate(ctx.tenant, ctx.config,
          consolidate_settle_ms: 0,
          consolidate_min_rows: 1,
          consolidate_max_rows: 60_000,
          target_rows: 1_500
        )
      end)

    assert_receive {:storage_barrier, storage, "GET", ^source}, 30_000
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    config = Map.put(ctx.config, :maintenance_operation, :metric_compact)
    merge = MetricsCompactor.compact(ctx.tenant, config)
    send(storage, {:release_storage, source})
    result = Task.await(grouping, 60_000)

    assert {:ok, %{sources: 300, rows: 60_000}} = result
    assert {:ok, %{merged: 0}} = merge
    reads(ctx.agent)
    assert {:ok, ^expected} = Evaluator.query(query, ctx.tenant, opts)
    assert reads(ctx.agent) == 1
    Runtime.put_env(:pulse, Evaluator, [])
    assert_samples(ctx)
  end

  test "recent grouping reaches event-time recent sources behind late historical outputs", ctx do
    {query, opts, _} = hd(panels(ctx))
    assert {:ok, expected} = memory(ctx, query, opts)
    {:ok, root, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    assert {:ok, raw} = MetricTiers.segments(root, ctx.t0, ctx.t0 + @hour, :samples, ctx.tenant, ctx.config)

    historical = fn range ->
      for n <- range do
        ts = ctx.t0 - @hour + n
        key = S3.object_key(ctx.tenant, "metrics", ts, ts, "historical-#{n}", nil)
        key = String.replace(key, "-rand-", "-final-")
        %{Segment.build(key, ts, ts, 1, 1000) | metric_names: ["other"]}
      end
    end

    assert {:ok, root} =
             JournalManifest.convert(
               %Manifest{version: 1, segments: historical.(1..3000) ++ raw},
               ctx.tenant,
               "metrics",
               ctx.config
             )

    # Historical finalization publishes old samples AFTER current ingestion.
    # Neither the historical cursor nor the last four published pages holds
    # the raw samples that recent grouping needs to keep queries working.
    root = Manifest.merge(root, historical.(3001..6000))
    assert {:ok, {root, payload, _}} = JournalManifest.seal(root, ctx.tenant, "metrics", ctx.config)
    assert {:ok, _} = ObjectStore.put(ctx.config, Manifest.manifest_key(ctx.tenant, "metrics"), payload)
    reads(ctx.agent)
    assert {:ok, ^expected} = Evaluator.query(query, ctx.tenant, opts)
    assert reads(ctx.agent) == 299

    Runtime.put_env(:pulse, Evaluator, max_scan_segments: 1)
    assert {:error, :query_scan_limit} = Evaluator.query(query, ctx.tenant, opts)
    assert %{limit: :max_scan_segments} = QueryLimit.take()

    assert {:ok, %{sources: 300, rows: 60_000}} =
             MetricTiers.consolidate(ctx.tenant, ctx.config,
               consolidate_settle_ms: 0,
               consolidate_min_rows: 1,
               consolidate_max_rows: 60_000,
               target_rows: 1_500
             )

    reads(ctx.agent)
    assert {:ok, ^expected} = Evaluator.query(query, ctx.tenant, opts)
    assert reads(ctx.agent) == 1
    assert root.version == 4
    assert_samples(ctx)
  end

  test "background maintenance reaches raw sources between already-grouped manifest pages", ctx do
    tenant = ctx.tenant <> "-cursor"

    # Metadata-only full outputs: the fragment packer must not read these.
    grouped =
      for n <- 1..6000 do
        ts = ctx.t0 + n * 1_000_000
        key = S3.object_key(tenant, "metrics", ts, ts, "page-#{n}", nil)
        key = String.replace(key, "-rand-", "-group-")
        %{Segment.build(key, ts, ts, 32_768, 1000) | metric_names: ["other"]}
      end

    # These two raw objects sit in the middle of twelve leaves, outside both
    # the initial historical cursor and the always-included newest leaves.
    raw =
      for n <- 1..2 do
        ts = ctx.t0 + 3_000_000_000 + n
        row = %MetricSample{timestamp_ns: ts, value: n * 1.0, labels: %{"__name__" => "up"}}
        assert {:ok, blob, min, max} = S3.encode_segment(:metrics, [row])
        key = S3.object_key(tenant, "metrics", min, max, "raw-#{n}", nil)
        assert {:ok, _} = ObjectStore.put(ctx.config, key, blob)
        %{Segment.build(key, min, max, 1, byte_size(blob)) | metric_names: ["up"]}
      end

    assert {:ok, root} =
             JournalManifest.convert(%Manifest{version: 1, segments: grouped ++ raw}, tenant, "metrics", ctx.config)

    assert {:ok, _} =
             ObjectStore.put(
               ctx.config,
               Manifest.manifest_key(tenant, "metrics"),
               IO.iodata_to_binary(Manifest.encode(root))
             )

    opts = %{start_ts_ns: ctx.t0 + 4 * @second, end_ts_ns: ctx.t0 + 5 * @second, step_ns: @second}
    assert {:ok, expected} = Evaluator.query("count(up)", tenant, opts)
    config = Map.put(ctx.config, :maintenance_operation, :metric_compact)

    for _ <- 1..4 do
      assert {:ok, %{merged: 0}} = MetricsCompactor.compact(tenant, config)
      assert {:ok, _} = MetricTiers.consolidate(tenant, config, consolidate_min_rows: 1)
    end

    Runtime.put_env(:pulse, Evaluator, max_scan_segments: 1)
    assert {:ok, ^expected} = Evaluator.query("count(up)", tenant, opts)
  end

  test "default grouping keeps a low-volume hour within the segment query budget", ctx do
    tenant = ctx.tenant <> "-small"
    from = MetricTiers.hour(System.os_time(:nanosecond)) - @hour + 10 * @minute

    append = fn n ->
      row = %MetricSample{
        timestamp_ns: from + (n - 1) * 2 * @second,
        value: rem(n, 2) * 1.0,
        labels: %{"__name__" => "up"}
      }

      assert :ok = S3.append(:metrics, tenant, [row])
    end

    for n <- 1..31, do: append.(n)
    assert {:ok, %{hour: nil}} = MetricTiers.consolidate(tenant, ctx.config)
    append.(32)
    assert {:ok, %{sources: 32, rows: 32}} = MetricTiers.consolidate(tenant, ctx.config)

    33..1100
    |> Task.async_stream(append, max_concurrency: 16, timeout: :infinity)
    |> Stream.run()

    opts = %{start_ts_ns: from, end_ts_ns: from + 2198 * @second, step_ns: 10 * @second}
    assert {:error, :query_scan_limit} = Evaluator.query("count(up)", tenant, opts)
    assert %{limit: :max_scan_segments} = QueryLimit.take()
    config = Map.put(ctx.config, :maintenance_operation, :metric_compact)

    for _ <- 1..16 do
      assert {:ok, %{merged: 0}} = MetricsCompactor.compact(tenant, config)
      assert {:ok, _} = MetricTiers.consolidate(tenant, config)
    end

    assert {:ok, %{"data" => %{"result" => [%{"values" => values}]}}} = Evaluator.query("count(up)", tenant, opts)
    assert length(values) == 220
    assert Enum.all?(values, fn [_timestamp, count] -> count == "1" end)
  end

  test "mixed-size raw segments cannot block grouping of later fitting sources", ctx do
    tenant = ctx.tenant <> "-mixed"
    from = ctx.t0

    batches =
      for {size, batch} <- Enum.with_index([20, 20] ++ List.duplicate(1, 40)) do
        for row <- 1..size do
          %MetricSample{
            timestamp_ns: from + batch * @second,
            value: (batch + row) * 1.0,
            labels: %{"__name__" => "up", "instance" => "#{batch}-#{row}"}
          }
        end
      end

    Enum.each(batches, &assert(:ok = S3.append(:metrics, tenant, &1)))
    query_opts = %{end_ts_ns: from + 42 * @second}
    Runtime.put_env(:pulse, Evaluator, max_scan_segments: 32)
    assert {:error, :query_scan_limit} = Evaluator.query("count(up)", tenant, query_opts)
    assert %{limit: :max_scan_segments} = QueryLimit.take()

    opts = [consolidate_settle_ms: 0, consolidate_min_rows: 32, consolidate_max_rows: 32, target_rows: 32]

    # Neither oldest 20-row source fills a batch alone, and together they
    # exceed its cap. Each can instead group with twelve later singleton rows.
    for _ <- 1..2 do
      assert {:ok, %{sources: 13, rows: 32, grouped: 1}} = MetricTiers.consolidate(tenant, ctx.config, opts)
    end

    reads(ctx.agent)

    assert {:ok, %{"data" => %{"result" => [%{"value" => [_, "80"]}]}}} =
             Evaluator.query("count(up)", tenant, query_opts)

    assert reads(ctx.agent) == 18
    assert {:ok, %{hour: nil}} = MetricTiers.consolidate(tenant, ctx.config, opts)

    assert {:ok, actual} = S3.query(:metrics, tenant, start_ts: from, end_ts: from + 42 * @second, limit: 81)
    samples = &Enum.sort(Enum.map(&1, fn sample -> {sample.labels, sample.timestamp_ns, sample.value} end))
    assert samples.(actual) == samples.(List.flatten(batches))
  end

  test "small grouped outputs consolidate without mixing names or repeatedly rewriting full outputs", ctx do
    tenant = ctx.tenant <> "-fragments"
    from = ctx.t0
    opts = [consolidate_settle_ms: 0, consolidate_min_rows: 32, consolidate_max_rows: 1024, target_rows: 1024]

    batch = fn count, ts, names ->
      for row <- 1..count do
        %MetricSample{
          timestamp_ns: ts + row,
          value: (rem(ts, 997) + row) * 1.0,
          labels: %{"__name__" => Enum.at(names, rem(row, length(names))), "instance" => "#{rem(row, 4)}"}
        }
      end
    end

    fragments = for n <- 1..32, do: batch.(32, from + n * @second, ["up", "noise"])

    for records <- fragments do
      assert :ok = S3.append(:metrics, tenant, records)
      assert {:ok, %{sources: 1, rows: 32, grouped: 1}} = MetricTiers.consolidate(tenant, ctx.config, opts)
    end

    # Raw grouping must still win over the existing fragment backlog. Keep a
    # full output, an exact half-full tail, a different name set and a
    # different hour as merge controls.
    controls = [
      batch.(1024, from + 100 * @second, ["up", "noise"]),
      batch.(512, from + 90 * @second, ["up", "noise"]),
      batch.(32, from, ["unrelated"]),
      batch.(32, from - @hour, ["up", "noise"])
    ]

    for records <- controls do
      assert :ok = S3.append(:metrics, tenant, records)
      assert {:ok, %{sources: 1, grouped: 1}} = MetricTiers.consolidate(tenant, ctx.config, opts)
    end

    all = List.flatten(fragments ++ controls)
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    assert :ok = Storage.append(:metrics, tenant <> "-reference", all)
    query_opts = %{start_ts_ns: from, end_ts_ns: from + 180 * @second, step_ns: 10 * @second}
    assert {:ok, expected} = Evaluator.query("sum(up)", tenant <> "-reference", query_opts)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    reads(ctx.agent)
    assert {:ok, ^expected} = Evaluator.query("sum(up)", tenant, query_opts)
    assert reads(ctx.agent) == 34

    Runtime.put_env(:pulse, Evaluator, max_scan_segments: 3)
    assert {:error, :query_scan_limit} = Evaluator.query("sum(up)", tenant, query_opts)
    assert %{limit: :max_scan_segments} = QueryLimit.take()

    assert {:ok, before, _} = Retention.load(tenant, "metrics", ctx.config)
    # Sixteen fragments only reach half the target: the source cap must not
    # be bypassed to create a qualifying batch.
    assert {:ok, %{hour: nil}} =
             MetricTiers.consolidate(tenant, ctx.config, Keyword.put(opts, :consolidate_max_sources, 16))

    assert {:ok, %{sources: 32, rows: 1024, grouped: 1}} = MetricTiers.consolidate(tenant, ctx.config, opts)
    reads(ctx.agent)
    assert {:ok, ^expected} = Evaluator.query("sum(up)", tenant, query_opts)
    assert reads(ctx.agent) == 3

    assert {:ok, after_merge, _} = Retention.load(tenant, "metrics", ctx.config)
    assert length(before.segments) == 36
    assert length(after_merge.segments) == 5
    assert Enum.sum_by(after_merge.segments, & &1.byte_size) < Enum.sum_by(before.segments, & &1.byte_size)

    for _ <- 1..3, do: assert({:ok, %{hour: nil}} = MetricTiers.consolidate(tenant, ctx.config, opts))
    assert reads(ctx.agent) == 0
    assert {:ok, ^after_merge, _} = Retention.load(tenant, "metrics", ctx.config)

    assert {:ok, actual} = S3.query(:metrics, tenant, start_ts: from - @hour, end_ts: from + 180 * @second, limit: 2625)
    samples = &Enum.sort(Enum.map(&1, fn sample -> {sample.labels, sample.timestamp_ns, sample.value} end))
    assert samples.(actual) == samples.(all)
  end

  @tag :query_bench
  @tag timeout: :infinity
  test "production volume count(up) over one hour fits the unchanged scan budget after grouping", ctx do
    alias TuistMetricHistory, as: History

    tenant = ctx.tenant <> "-production"
    payload = IO.iodata_to_binary(Manifest.encode(Manifest.new()))
    {:ok, _} = ObjectStore.put(ctx.config, Manifest.manifest_key(tenant, "metrics"), payload)
    {targets, 400_000} = History.targets(:production, [])
    from = div(ctx.t0, @hour) * @hour
    origin_ms = div(from, 1_000_000)

    # Real asymmetric families (including high-cardinality histogram/filler
    # names), 400k series/30 s, remote-write coalesced into 2 s segments.
    # Keep only up's reference rows, not 48M BEAM sample structs.
    for offset <- 0..1799 do
      records = History.batch(targets, :production, origin_ms, origin_ms + offset * 2_000)
      assert :ok = S3.append(:metrics, tenant, records)
      up = Enum.filter(records, &(&1.labels["__name__"] == "up"))
      Runtime.put_env(:pulse, Storage, adapter: Memory)
      :ok = Storage.append(:metrics, tenant <> "-reference", up)
      Runtime.put_env(:pulse, Storage, adapter: S3)
      if rem(offset + 1, 300) == 0, do: IO.puts("production history: #{offset + 1}/1800 flushes")
    end

    opts = %{start_ts_ns: from, end_ts_ns: from + @hour - 1, step_ns: 10 * @second}
    Runtime.put_env(:pulse, Evaluator, max_scan_bytes: 268_435_456)
    assert {:error, :query_scan_limit} = Evaluator.query("count(up)", tenant, opts)
    assert %{limit: limit, stage: :candidates} = QueryLimit.take()
    assert limit in [:max_scan_segments, :max_scan_bytes]
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    assert {:ok, expected} = Evaluator.query("count(up)", tenant <> "-reference", opts)
    Runtime.put_env(:pulse, Storage, adapter: S3)

    config = Map.put(ctx.config, :maintenance_operation, :metric_compact)

    for _ <- 1..60, reduce: 0 do
      grouped ->
        assert {:ok, %{merged: 0}} = MetricsCompactor.compact(tenant, config)

        case MetricTiers.consolidate(tenant, config, consolidate_settle_ms: 0) do
          {:ok, %{rows: rows}} -> grouped + rows
          {:ok, %{hour: nil}} -> grouped
        end
    end

    reads(ctx.agent)
    assert {:ok, ^expected} = Evaluator.query("count(up)", tenant, opts)
    IO.puts("production count(up), 1h/10s: #{reads(ctx.agent)} segment GETs, unchanged 256 MiB scan cap")
  end

  test "historical finalization cannot publish over sources replaced by recent grouping", ctx do
    {:ok, root, _} = Retention.load(ctx.tenant, "metrics", ctx.config)
    source = hd(root.segments).key
    parent = self()
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"GET", source} => parent}})
    tasks = start_supervised!(Task.Supervisor)

    historical =
      Task.Supervisor.async_nolink(tasks, fn ->
        MetricTiers.finalize_hour(ctx.tenant, ctx.t0, ctx.config, max_rows: 100_000)
      end)

    assert_receive {:storage_barrier, storage, "GET", ^source}, 30_000
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    opts = [consolidate_settle_ms: 0, consolidate_min_rows: 1, consolidate_max_rows: 60_000, target_rows: 1_500]
    assert {:ok, %{sources: 300, rows: 60_000}} = MetricTiers.consolidate(ctx.tenant, ctx.config, opts)
    grouped = tiers(ctx)
    send(storage, {:release_storage, source})
    assert {:error, :compaction_conflict} = Task.await(historical, 60_000)
    assert tiers(ctx) == grouped

    # The losing finalizer may discard only its own unpublished objects,
    # never the grouped objects or the still grace-protected raw sources.
    assert {:ok, _, _} = ObjectStore.get_if_none_match(ctx.config, source, nil)
    assert_samples(ctx)
  end

  test "an hour larger than max_rows finalizes in name-hash partitions", ctx do
    {query, opts, _} = hd(panels(ctx))
    assert {:ok, expected} = Evaluator.query(query, ctx.tenant, opts)
    reads(ctx.agent)

    # 60,000 rows with max_rows 20,000: four partitions of at most 15,000
    # expected rows each, every raw segment read by every partition.
    tiers = [max_rows: 20_000, target_rows: 4_500, rollup_target_rows: 3_000, settle_ms: 0]

    assert {:ok, %{partitions: 4, sources: 300} = done} =
             MetricTiers.finalize_hour(ctx.tenant, ctx.t0, ctx.config, tiers)

    assert reads(ctx.agent) == 4 * 300
    assert %{final: finals, rollup: _} = tiers(ctx)
    assert finals == done.finals

    # Each metric's 1,500 rows stay in one finalized segment.
    assert {:ok, ^expected} = Evaluator.query(query, ctx.tenant, opts)
    assert reads(ctx.agent) == 1
    assert {:ok, ^expected} = memory(ctx, query, opts)

    # Every metric's rows were finalized by exactly one partition.
    every = ~s|count by (__name__) (last_over_time({__name__=~"m_.*"}[10m]))|
    at = %{end_ts_ns: ctx.t0 + 10 * @minute}
    assert {:ok, %{"data" => %{"result" => result}}} = Evaluator.query(every, ctx.tenant, at)
    assert length(result) == @metrics
    assert Enum.all?(result, &(&1["value"] |> List.last() == "#{@targets}"))
  end

  # Agreement with the native finalizer's partitions is checked above: a
  # metric the planner assigned elsewhere would be missing from the result.
  test "name partitions are stable and spread similar names" do
    for count <- [2, 3, 7, 16], name <- ["m_0", "m_17", "tuist_metric_123", "", "ünïcode"] do
      partition = MetricTiers.name_partition(name, count)
      assert partition in 0..(count - 1)
      assert MetricTiers.name_partition(name, count) == partition
    end

    # Similar names spread over partitions instead of sharing the top bits.
    spread = for i <- 0..39, uniq: true, do: MetricTiers.name_partition("m_#{i}", 4)
    assert Enum.sort(spread) == [0, 1, 2, 3]
  end
end
