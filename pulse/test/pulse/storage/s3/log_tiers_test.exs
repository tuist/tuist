defmodule Pulse.Storage.S3.LogTiersTest do
  @moduledoc """
  Stream-grouped log segments (`Pulse.Storage.S3.LogTiers`) and log scans
  charged by selected rows.

  Two settled hours of three kinds of stream arrive in mixed 30-second
  batches, as ingest and log compaction leave them: a RUM service writing
  logfmt web vitals, a busy JSON server and service-less docker streams.
  Parsed-field alert shapes must answer within a row budget sized by their
  own service's lines, not every stored line, and once each hour is
  finalized a service selector reads only its service's segments.
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
  alias Pulse.Storage.S3.LogTiers
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.Retention
  alias Pulse.Test.CompactionStore

  @moduletag timeout: 300_000

  @minute 60_000_000_000
  @hour 60 * @minute

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
      access_key_id: "tiers-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      query_prefetch: 4
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    tenant = "tiers-#{System.unique_integer([:positive])}"

    {:ok, _} =
      ObjectStore.put(
        config,
        Manifest.manifest_key(tenant, "logs"),
        IO.iodata_to_binary(Manifest.encode(Manifest.new()))
      )

    # Two settled hours ending at the current hour's start.
    t0 = div(System.os_time(:nanosecond), @hour) * @hour - 2 * @hour
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

  # Every 2 s: one RUM line, five server lines and two docker lines.
  defp history(t0) do
    for step <- 0..(2 * 1800 - 1), kind <- [:rum, :server, :server, :server, :server, :server, :docker, :docker] do
      record(kind, t0 + step * 2_000_000_000 + :erlang.phash2({step, kind}, 1_000_000_000) + 1, step)
    end
  end

  defp record(:rum, ts, i) do
    env = if rem(i, 10) < 7, do: "prod", else: "staging"
    lcp = if rem(i, 11) == 0, do: "", else: "#{800 + rem(i * 37, 12_000)}"

    body =
      "level=info kind=measurement type=web-vitals app_environment=#{env} session_id=s#{rem(i, 400)} lcp=#{lcp}"

    %Log{timestamp_ns: ts, service: "tuist-web", resource: %{"namespace" => "tuist"}, body: body}
  end

  defp record(:server, ts, i) do
    body = ~s({"level":"info","msg":"Sent 200 in #{rem(i, 300)}ms","kind":"measurement"})

    %Log{
      timestamp_ns: ts,
      service: "tuist",
      resource: %{"namespace" => "tuist", "pod" => "server-#{rem(i, 3)}"},
      body: body
    }
  end

  defp record(:docker, ts, i) do
    body = "event=cache_usage account_handle=a#{rem(i, 6)} count=#{rem(i, 20)}"
    %Log{timestamp_ns: ts, resource: %{"app" => "docker", "instance" => "kura-#{rem(i, 2)}"}, body: body}
  end

  defp query_limits(limits \\ []),
    do: Runtime.put_env(:pulse, QueryRunner, Keyword.put_new(limits, :timeout_ms, 120_000))

  defp reads(agent) do
    Agent.get_and_update(agent, fn state ->
      {Enum.count(state.reads, &String.ends_with?(&1, ".parquet")), %{state | reads: []}}
    end)
  end

  defp metric(tenant, query, opts) do
    {:ok, ast} = Parser.parse(query)
    Evaluator.evaluate_metric(ast, tenant, opts)
  end

  defp logs(tenant, query, opts) do
    {:ok, ast} = Parser.parse(query)
    Evaluator.evaluate_log(ast, tenant, opts)
  end

  # The memory adapter holds every record on the query worker's heap.
  defp memory(ctx, fun) do
    limits = Runtime.get_env(:pulse, QueryRunner, [])
    query_limits(max_heap_words: div(2 * 1024 * 1024 * 1024, 8))
    Runtime.put_env(:pulse, Storage, adapter: Memory)
    result = fun.(ctx.tenant <> "-memory")
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, QueryRunner, limits)
    result
  end

  defp segments(ctx) do
    {:ok, manifest, _} = Retention.load(ctx.tenant, "logs", ctx.config)
    manifest.segments
  end

  defp finalize(ctx, opts \\ []) do
    for h <- 0..1 do
      assert {:ok, %{outputs: outputs}} = LogTiers.finalize_hour(ctx.tenant, ctx.t0 + h * @hour, ctx.config, opts)
      outputs
    end
  end

  defp rum_rows(ctx), do: Enum.count(ctx.records, &(&1.service == "tuist-web"))

  @alerts [
    ~s/sum by (app_environment) (count_over_time({service_name="tuist-web"} | logfmt | kind="measurement" | type="web-vitals" | app_environment="prod" | lcp!="" [2h]))/,
    ~s/quantile_over_time(0.75, {service_name="tuist-web"} | logfmt | kind="measurement" | app_environment="prod" | lcp!="" | __error__="" | unwrap lcp [2h])/,
    ~s/count by (app_environment) (sum by (app_environment, session_id) (count_over_time({service_name="tuist-web"} | logfmt | kind="measurement" | lcp > 10000 [2h])))/,
    ~s/count by (account_handle) (count_over_time({app="docker",instance=~".+"} |= "event=cache_usage" | logfmt [2h]))/
  ]

  test "parsed-field alerts are charged their own service's lines, not every stored line", ctx do
    opts = %{end_ts_ns: ctx.t0 + 2 * @hour}
    stored = length(ctx.records)
    assert rum_rows(ctx) * 4 < stored

    # The budget fits every line the selectors select but not the stored
    # lines of the segments they must read: 1.34.1 charged those.
    query_limits(max_scan_rows: div(stored, 3))

    for query <- @alerts do
      assert {:ok, result} = metric(ctx.tenant, query, opts), query
      assert {:ok, ^result} = memory(ctx, &metric(&1, query, opts)), query
      assert match?({:vector, [_ | _]}, result), query
    end

    # A parsed-field volume panel groups while counting: the range and the
    # sum each hold two environments' 121 steps, not one series per parsed
    # label set (every line's lcp and session differ).
    query =
      ~s/sum by (app_environment) (count_over_time({service_name="tuist-web"} | logfmt | kind="measurement" [1m]))/

    range = %{start_ts_ns: ctx.t0, end_ts_ns: ctx.t0 + 2 * @hour, step_ns: @minute}
    Runtime.put_env(:pulse, Pulse.PromQL.Evaluator, max_result_points: 2 * 2 * 121)
    assert {:ok, {:matrix, [_, _]} = result} = metric(ctx.tenant, query, range)
    Runtime.put_env(:pulse, Pulse.PromQL.Evaluator, [])
    assert {:ok, ^result} = memory(ctx, &metric(&1, query, range))

    # Selected lines still count: a budget below them fails.
    query_limits(max_scan_rows: rum_rows(ctx) - 1)
    assert {:error, :query_scan_limit} = metric(ctx.tenant, hd(@alerts), opts)
    assert %{limit: :max_scan_rows} = QueryLimit.take()
  end

  test "finalized hours let a service selector read only its own segments", ctx do
    raw = length(segments(ctx))
    log_opts = %{start_ts_ns: ctx.t0, end_ts_ns: ctx.t0 + 2 * @hour, limit: 5000}
    before = for query <- @alerts, do: metric(ctx.tenant, query, %{end_ts_ns: ctx.t0 + 2 * @hour})
    assert reads(ctx.agent) >= raw

    # Each stream group gets a segment of its own per hour.
    assert [outputs, outputs] = finalize(ctx, pack_bytes: 1)
    final = segments(ctx)
    assert length(final) == 2 * outputs
    assert Enum.all?(final, &String.contains?(&1.key, "-final-"))
    assert Enum.sum_by(final, & &1.row_count) == length(ctx.records)
    reads(ctx.agent)

    # Nothing changed but the reads: one segment per hour for the RUM
    # service, two (one per docker instance) for the docker streams.
    for {query, result, expected_reads} <- Enum.zip([@alerts, before, [2, 2, 2, 4]]) do
      assert {:ok, _} = result
      assert result == metric(ctx.tenant, query, %{end_ts_ns: ctx.t0 + 2 * @hour}), query
      assert {reads(ctx.agent), query} == {expected_reads, query}
    end

    selector = ~s({service_name="tuist-web"} | logfmt | app_environment="staging")
    assert {:ok, streams} = logs(ctx.tenant, selector, log_opts)
    assert reads(ctx.agent) == 2
    assert {:ok, expected} = memory(ctx, &logs(&1, selector, log_opts))
    assert Enum.sort(streams) == Enum.sort(expected)
  end

  test "packed groups stay prunable and rollups stay exact after finalization", ctx do
    # Small groups share one pack per hour, which has lines without a
    # service: its label summary still lets other services skip it.
    assert [1, 1] = finalize(ctx)
    reads(ctx.agent)

    assert {:ok, {:vector, []}} =
             metric(ctx.tenant, ~s/sum(count_over_time({service_name="kura"}[2h]))/, %{end_ts_ns: ctx.t0 + 2 * @hour})

    assert reads(ctx.agent) == 0

    query = ~s|sum by (namespace) (count_over_time({namespace=~".+"}[1m]))|
    opts = %{start_ts_ns: ctx.t0, end_ts_ns: ctx.t0 + 2 * @hour, step_ns: @minute}
    :ok = roll_all(ctx)
    reads(ctx.agent)
    assert {:ok, result} = metric(ctx.tenant, query, opts)
    assert {:ok, ^result} = memory(ctx, &metric(&1, query, opts))
  end

  defp roll_all(ctx) do
    case LogRollups.roll(ctx.tenant, ctx.config, settle_ms: 0, lookback_ms: 4 * 3_600_000) do
      {:ok, %{from: nil}} -> :ok
      {:ok, %{from: _}} -> roll_all(ctx)
    end
  end
end
