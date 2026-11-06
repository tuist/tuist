defmodule Pulse.PromQL.TieredReadsTest do
  @moduledoc """
  Segment and row counts of 1-hour, 24-hour and 7-day PromQL queries over
  finalized metric hours (`Pulse.Storage.S3.MetricTiers`), and parity of
  rollup-composed results with plain sample evaluation (the memory adapter).

  Eight days of three metrics (three series each, one sample every five
  minutes) are appended in hour-straddling batches, as remote-write shards
  do, then every hour is finalized. Each metric-hour becomes one finalized
  segment of 36 rows and one rollup object of 3 rows.
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
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Test.Case
  alias Pulse.Test.CompactionStore

  @moduletag timeout: 300_000

  @hour 3_600_000_000_000
  @minute 60_000_000_000
  @t0 1_699_999_200 * 1_000_000_000
  @hours 8 * 24
  @pods ~w(a b c)
  # One finalized segment per metric-hour (3 series x 12 samples), one rollup
  # object per metric-hour (3 series).
  @tiers [target_rows: 36, rollup_target_rows: 3, settle_ms: 0, grace_ms: 3_600_000]

  setup_all do
    # Build the history once, then give every test its own copy of the store.
    {:ok, _} = Case.setup_runtime(%{module: Module.concat(__MODULE__, Fixture)})
    records = history()
    tenant = "tiers-#{System.unique_integer([:positive])}"
    {agent, config} = start_store(%{objects: %{}, version: 0})
    manifest = IO.iodata_to_binary(Manifest.encode(Manifest.new()))
    {:ok, _} = ObjectStore.put(config, Manifest.manifest_key(tenant, "metrics"), manifest)

    # Batches from :30 to :30 straddle every hour boundary.
    records
    |> Enum.group_by(&div(&1.timestamp_ns - @t0 + 30 * @minute, @hour))
    |> Enum.sort()
    |> Enum.each(fn {_, batch} -> :ok = S3.append(:metrics, tenant, batch) end)

    for hour <- 0..(@hours - 1) do
      {:ok, %{hour: _}} = MetricTiers.finalize_hour(tenant, @t0 + hour * @hour, config, @tiers)
    end

    %{records: records, tenant: tenant, snapshot: Agent.get(agent, &Map.take(&1, [:objects, :version]))}
  end

  # A deterministic history with resets, repeats, NaNs and negative values.
  defp history do
    :rand.seed(:exsss, {7, 11, 13})
    Enum.flat_map(@pods, &pod_history/1)
  end

  defp pod_history(pod) do
    {samples, _} = Enum.map_reduce(0..(@hours * 12 - 1), {0.0, 5.0}, &step(pod, &1, &2))
    List.flatten(samples)
  end

  defp step(pod, i, {counter, gauge}) do
    ts = @t0 + i * 5 * @minute
    counter = if :rand.uniform(40) == 1, do: :rand.uniform(3) * 1.0, else: counter + :rand.uniform(5) - 1
    gauge = if :rand.uniform(4) == 1, do: gauge, else: Float.round(:rand.uniform() * 20 - 5, 2)
    gauge_value = if :rand.uniform(60) == 1, do: :nan, else: gauge

    {[
       sample("requests_total", pod, ts, counter),
       sample("queue_depth", pod, ts, gauge_value),
       sample("node_info", pod, ts, 1.0)
     ], {counter, gauge}}
  end

  defp sample(name, pod, ts, value),
    do: %MetricSample{timestamp_ns: ts, value: value, labels: %{"__name__" => name, "job" => "api", "pod" => pod}}

  defp start_store(snapshot) do
    state =
      Map.merge(
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
        },
        snapshot
      )

    agent = start_supervised!({Agent, fn -> state end})
    server = start_supervised!({Bandit, plug: {CompactionStore, agent: agent}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "tiers-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      query_prefetch: 4
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    {agent, config}
  end

  setup ctx do
    {agent, config} = start_store(ctx.snapshot)
    # The same samples, evaluated without any tiers.
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    assert :ok = Storage.append(:metrics, ctx.tenant <> "-memory", ctx.records)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    %{agent: agent, config: config}
  end

  defp reads(agent) do
    Agent.get_and_update(agent, fn state ->
      {Enum.count(state.reads, &String.ends_with?(&1, ".parquet")), %{state | reads: []}}
    end)
  end

  defp memory_result(ctx, query, opts) do
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    result = Evaluator.query(query, ctx.tenant <> "-memory", opts)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    result
  end

  # The query reads exactly `segments` objects and its selectors match exactly
  # `rows` rows (samples or rollup rows): it succeeds within those budgets and
  # fails one below each.
  defp assert_cost(ctx, query, opts, segments, rows) do
    assert {:ok, result} = Evaluator.query(query, ctx.tenant, opts)
    assert reads(ctx.agent) == segments

    Runtime.put_env(:pulse, Evaluator, max_scan_segments: segments, max_scan_rows: rows)
    assert {:ok, ^result} = Evaluator.query(query, ctx.tenant, opts)
    reads(ctx.agent)

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

  # Half past an hour, late in the history.
  defp at, do: @t0 + (@hours - 2) * @hour + 30 * @minute

  test "a 1-hour window reads one finalized segment per hour of its metric only", ctx do
    query = ~s|max_over_time(queue_depth{job="api"}[1h])|
    opts = %{end_ts_ns: at()}
    # (t-1h, t] spans two hours: 2 segments of this metric only, 12 samples
    # per pod in the window.
    result = assert_cost(ctx, query, opts, 2, 36)
    assert length(result["data"]["result"]) == 3
    assert {:ok, ^result} = memory_result(ctx, query, opts)
  end

  test "a 24-hour dashboard reads 25 finalized segments of its metric", ctx do
    start = @t0 + 3 * 24 * @hour + 10 * @minute
    opts = %{start_ts_ns: start, end_ts_ns: start + 24 * @hour, step_ns: 5 * @minute}

    for query <- [~s|sum by (pod) (rate(requests_total[5m]))|, ~s|avg(queue_depth)|] do
      # (start - 5m, start + 24h] touches 25 hours, one segment each, and holds
      # 289 samples per pod.
      result = assert_cost(ctx, query, opts, 25, 3 * 289)
      assert {:ok, ^result} = memory_result(ctx, query, opts)
    end
  end

  test "a 7-day alert window reads rollups for its interior hours", ctx do
    query = ~s|increase(requests_total[7d])|
    opts = %{end_ts_ns: at()}
    # 167 interior hours from rollup objects (one row per pod) and the two
    # half-hour edges from finalized segments (6 samples per pod each).
    result = assert_cost(ctx, query, opts, 169, 167 * 3 + 2 * 3 * 6)
    assert length(result["data"]["result"]) == 3
    assert {:ok, ^result} = memory_result(ctx, query, opts)
  end

  test "rollup-composed range functions equal sample evaluation", ctx do
    functions =
      ~w(rate increase delta count_over_time present_over_time min_over_time max_over_time first_over_time last_over_time changes resets absent_over_time)

    cases =
      for function <- functions,
          metric <- ~w(requests_total queue_depth),
          window <- ~w(3h 1d 3d 7d),
          minute <- [0, 17] do
        {"#{function}(#{metric}[#{window}])", %{end_ts_ns: at() + minute * @minute}}
      end

    # A range query whose steps all contain the same interior hours.
    cases = [
      {~s|resets(requests_total[2d])|, %{start_ts_ns: at() - 6 * @hour, end_ts_ns: at(), step_ns: @hour}}
      | cases
    ]

    for {query, opts} <- cases do
      assert {:ok, s3} = Evaluator.query(query, ctx.tenant, opts)
      assert {:ok, ^s3} = memory_result(ctx, query, opts), query
    end
  end

  test "a write into a finalized hour makes that hour read samples until refinalized", ctx do
    late_ts = at() - 3 * 24 * @hour + 7 * @minute
    late = sample("requests_total", "a", late_ts, 0.5)
    assert :ok = S3.append(:metrics, ctx.tenant, [late])
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    assert :ok = Storage.append(:metrics, ctx.tenant <> "-memory", [late])
    Runtime.put_env(:pulse, Storage, adapter: S3)
    query = ~s|resets(requests_total[7d])|
    opts = %{end_ts_ns: at()}

    assert {:ok, s3} = Evaluator.query(query, ctx.tenant, opts)
    assert {:ok, ^s3} = memory_result(ctx, query, opts)
    # The late hour reads its final segment and the new raw segment.
    assert reads(ctx.agent) == 169 + 1

    assert {:ok, %{hour: hour}} = MetricTiers.finalize(ctx.tenant, ctx.config, @tiers)
    assert hour == MetricTiers.hour(late_ts)
    # Refinalizing reads that hour's three finalized segments and the late one.
    assert reads(ctx.agent) == 4
    assert {:ok, ^s3} = Evaluator.query(query, ctx.tenant, opts)
    assert reads(ctx.agent) == 169
  end
end
