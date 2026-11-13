defmodule Pulse.Storage.S3.LogRollupsTest do
  @moduledoc """
  Per-minute log rollups (`Pulse.Storage.S3.LogRollups`): LogQL volume
  panels read rollups instead of lines, answer exactly what reading lines
  answers (the memory adapter), and fall back to lines for minutes a rollup
  no longer describes.

  Three hours of logs from six streams arrive in 30-second batches, about
  13,000 lines in all. A one-hour 60-second-step volume panel reads its
  hour's rollups: a handful of objects and a few hundred rows instead of
  every segment and line.
  """
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Parser
  alias Pulse.ObjectStore
  alias Pulse.QueryLimit
  alias Pulse.QueryRunner
  alias Pulse.Record.Log
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.LogRollups
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore

  @moduletag timeout: 300_000

  @minute 60_000_000_000
  @hour 60 * @minute
  @services ~w(tuist-server kura-cache)
  @levels ~w(info info warn error)

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
      access_key_id: "rollups-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      query_prefetch: 4
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    tenant = "rollups-#{System.unique_integer([:positive])}"

    {:ok, _} =
      ObjectStore.put(
        config,
        Manifest.manifest_key(tenant, "logs"),
        IO.iodata_to_binary(Manifest.encode(Manifest.new()))
      )

    # Three settled hours ending at the current hour's start.
    t0 = div(System.os_time(:nanosecond), @hour) * @hour - 3 * @hour
    records = history(t0)

    records
    |> Enum.chunk_by(&div(&1.timestamp_ns - t0, 30_000_000_000))
    |> Enum.each(&(:ok = S3.append(:logs, tenant, &1)))

    Runtime.put_env(:pulse, Storage, adapter: Memory)
    :ok = Storage.append(:logs, tenant <> "-memory", records)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    query_limits()
    reads(agent)
    %{agent: agent, config: config, tenant: tenant, t0: t0, records: records}
  end

  # One line every 0.8 s per stream on average, timestamps off the minute
  # grid, some empty bodies; the third hour's first minute has a stream
  # whose lines carry trace IDs.
  defp history(t0) do
    for step <- 0..(3 * 3600 * 10 - 1)//8, s <- 0..5 do
      ts = t0 + step * 100_000_000 + s * 7_000_001 + 1
      service = Enum.at(@services, rem(s, 2))
      level = Enum.at(@levels, rem(step + s, 4))
      body = if rem(step, 97) == 0, do: "", else: "level=#{level} msg=\"handled\" n=#{rem(step * 31 + s, 1000)}"

      %Log{
        timestamp_ns: ts,
        service: service,
        body: body,
        trace_id:
          if(s == 5 and (ts - t0) in (2 * @hour)..(2 * @hour + @minute), do: "4bf92f3577b34da6a3ce929d0e0e4736"),
        resource: %{"namespace" => "tuist", "pod" => "#{service}-#{rem(s, 3)}"},
        attributes: %{"detected_level" => level}
      }
    end
  end

  # Query limits for a test, with a deadline that allows for a loaded suite.
  defp query_limits(limits \\ []),
    do: Runtime.put_env(:pulse, QueryRunner, Keyword.put_new(limits, :timeout_ms, 120_000))

  defp reads(agent) do
    Agent.get_and_update(agent, fn state ->
      {Enum.count(state.reads, &String.ends_with?(&1, ".parquet")), %{state | reads: []}}
    end)
  end

  defp roll_all(ctx) do
    case LogRollups.roll(ctx.tenant, ctx.config, settle_ms: 0, lookback_ms: 4 * 3_600_000) do
      {:ok, %{from: nil}} -> :ok
      {:ok, %{from: _}} -> roll_all(ctx)
    end
  end

  defp run(tenant, query, opts) do
    {:ok, ast} = Parser.parse(query)
    Evaluator.evaluate_metric(ast, tenant, opts)
  end

  # The memory adapter holds every record on the query worker's heap.
  defp memory(ctx, query, opts) do
    limits = Runtime.get_env(:pulse, QueryRunner, [])
    query_limits(max_heap_words: div(2 * 1024 * 1024 * 1024, 8))
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    result = run(ctx.tenant <> "-memory", query, opts)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, QueryRunner, limits)
    result
  end

  defp rollups(ctx) do
    {:ok, manifest, _} = Retention.load(ctx.tenant, "logs", ctx.config)
    Enum.filter(manifest.segments, &String.contains?(&1.key, "-rollup-"))
  end

  test "a one-hour volume panel reads its hour's rollups, not its lines", ctx do
    query = ~s|sum by (detected_level) (count_over_time({namespace="tuist"}[1m]))|
    opts = %{start_ts_ns: ctx.t0 + @hour, end_ts_ns: ctx.t0 + 2 * @hour, step_ns: @minute}

    lines =
      Enum.count(ctx.records, &(&1.timestamp_ns > ctx.t0 + @hour - @minute and &1.timestamp_ns <= ctx.t0 + 2 * @hour))

    # Before any rollup the panel reads every line of the hour.
    query_limits(max_scan_rows: lines - 1)
    assert {:error, :query_scan_limit} = run(ctx.tenant, query, opts)
    assert %{limit: :max_scan_rows} = QueryLimit.take()
    query_limits()

    :ok = roll_all(ctx)
    # One merged rollup per settled hour.
    assert length(rollups(ctx)) == 3
    reads(ctx.agent)

    assert {:ok, result} = run(ctx.tenant, query, opts)
    assert {:ok, ^result} = memory(ctx, query, opts)
    # The window's 61 minutes come from two hourly rollups; the rows read are
    # one per stream and minute: 6 streams by 61 minutes.
    assert reads(ctx.agent) == 2
    query_limits(max_scan_rows: 6 * 61, max_scan_segments: 2)
    assert {:ok, ^result} = run(ctx.tenant, query, opts)
    query_limits(max_scan_rows: 6 * 61 - 1)
    assert {:error, :query_scan_limit} = run(ctx.tenant, query, opts)
    assert %{limit: :max_scan_rows} = QueryLimit.take()
    query_limits()
    assert lines > 4000

    # The sum groups while counting: the range and the sum each hold its three
    # levels' 61 steps (points are charged per node), not one series per
    # stream and level (18 by 61).
    assert {:matrix, [_, _, _]} = result
    Runtime.put_env(:pulse, Pulse.PromQL.Evaluator, max_result_points: 2 * 3 * 61)
    assert {:ok, ^result} = run(ctx.tenant, query, opts)
    # `* 1` keeps the sum from grouping early: every stream's series counts.
    per_stream = String.replace(query, "[1m]))", "[1m]) * 1)")
    assert {:error, :query_result_limit} = run(ctx.tenant, per_stream, opts)
  end

  test "rollup answers equal line answers for every eligible shape", ctx do
    queries = [
      ~s|sum by (detected_level) (count_over_time({namespace="tuist"}[1m]))|,
      ~s|sum by (service_name) (rate({namespace="tuist"}[5m]))|,
      ~s|sum (bytes_over_time({service_name="kura-cache"}[10m]))|,
      ~s|sum by (pod) (bytes_rate({namespace="tuist", pod=~"tuist.*"}[2m] offset 3m))|,
      ~s|count_over_time({namespace="tuist", detected_level="error"}[1m])|,
      # Unaligned and filtered shapes read lines.
      ~s|sum (count_over_time({namespace="tuist"}[90s]))|,
      ~s|sum (count_over_time({namespace="tuist"} \|= "warn" [1m]))|
    ]

    ranges = [
      %{start_ts_ns: ctx.t0 + 30 * @minute, end_ts_ns: ctx.t0 + 150 * @minute, step_ns: @minute},
      %{start_ts_ns: ctx.t0 + 115 * @minute, end_ts_ns: ctx.t0 + 125 * @minute, step_ns: 5 * @minute},
      %{end_ts_ns: ctx.t0 + 61 * @minute}
    ]

    cases = for query <- queries, opts <- ranges, do: {query, opts}
    # Before any rollup exists every answer comes from lines.
    lines = Map.new(cases, fn {query, opts} -> {{query, opts}, run(ctx.tenant, query, opts)} end)
    :ok = roll_all(ctx)

    for {query, opts} <- cases do
      assert {:ok, _} = expected = Map.fetch!(lines, {query, opts})
      assert run(ctx.tenant, query, opts) == expected, query

      # Sums of counts group while counting; `* 1` sums per-stream series.
      if String.starts_with?(query, "sum") and not String.contains?(query, "rate") do
        per_stream = String.replace(query, ~r/\]\)\)$/, "]) * 1)")
        assert run(ctx.tenant, per_stream, opts) == expected, per_stream
      end
    end

    # The memory adapter answers independently of Parquet, segments and rollups.
    opts = hd(ranges)
    for query <- queries, do: assert(memory(ctx, query, opts) == Map.fetch!(lines, {query, opts}), query)
  end

  test "segments written before 1.33 make only their own minutes read lines", ctx do
    # A segment from an older release has no per-minute line counts (`lm`).
    legacy = %Log{
      timestamp_ns: ctx.t0 + 70 * @minute + 5,
      service: "tuist-server",
      body: "legacy",
      resource: %{"namespace" => "tuist"},
      attributes: %{"detected_level" => "info"}
    }

    :ok = S3.append(:logs, ctx.tenant, [legacy])
    {:ok, manifest, _} = Retention.load(ctx.tenant, "logs", ctx.config)
    assert [key] = for(s <- manifest.segments, s.min_ts == legacy.timestamp_ns, do: s.key)
    segments = Enum.map(manifest.segments, &if(&1.key == key, do: %{&1 | log_minutes: nil}, else: &1))
    manifest = %{manifest | segments: segments}

    {:ok, _} =
      ObjectStore.put(
        ctx.config,
        Manifest.manifest_key(ctx.tenant, "logs"),
        IO.iodata_to_binary(Manifest.encode(manifest))
      )

    Runtime.put_env(:pulse, Storage, adapter: Memory)
    :ok = Storage.append(:logs, ctx.tenant <> "-memory", [legacy])
    Runtime.put_env(:pulse, Storage, adapter: S3)

    # Its hour still gets a rollup for every other minute.
    :ok = roll_all(ctx)
    assert length(rollups(ctx)) == 3

    query = ~s|sum by (detected_level) (count_over_time({namespace="tuist"}[1m]))|
    opts = %{start_ts_ns: ctx.t0 + @hour, end_ts_ns: ctx.t0 + 2 * @hour, step_ns: @minute}
    reads(ctx.agent)
    assert {:ok, s3} = run(ctx.tenant, query, opts)
    assert {:ok, ^s3} = memory(ctx, query, opts)
    # Two hourly rollups, the legacy segment and the batches of its minute,
    # not the hour's 120 batches.
    assert reads(ctx.agent) in 3..8
  end

  test "a late write makes its minute read lines until it is rolled up again", ctx do
    :ok = roll_all(ctx)
    late_ts = ctx.t0 + 70 * @minute + 5

    late = %Log{
      timestamp_ns: late_ts,
      service: "tuist-server",
      body: "late",
      resource: %{"namespace" => "tuist"},
      attributes: %{"detected_level" => "info"}
    }

    :ok = S3.append(:logs, ctx.tenant, [late])
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    :ok = Storage.append(:logs, ctx.tenant <> "-memory", [late])
    Runtime.put_env(:pulse, Storage, adapter: S3)

    query = ~s|sum by (detected_level) (count_over_time({namespace="tuist"}[1m]))|
    opts = %{start_ts_ns: ctx.t0 + 60 * @minute, end_ts_ns: ctx.t0 + 80 * @minute, step_ns: @minute}
    reads(ctx.agent)
    assert {:ok, s3} = run(ctx.tenant, query, opts)
    assert {:ok, ^s3} = memory(ctx, query, opts)
    # The two hours' rollups, plus the segments holding the late minute.
    assert reads(ctx.agent) > 2

    :ok = roll_all(ctx)
    assert length(rollups(ctx)) == 3
    reads(ctx.agent)
    assert {:ok, ^s3} = run(ctx.tenant, query, opts)
    assert reads(ctx.agent) == 2
  end
end
