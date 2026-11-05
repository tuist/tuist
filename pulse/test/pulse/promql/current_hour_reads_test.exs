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
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore

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
