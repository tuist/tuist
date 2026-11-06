defmodule Pulse.PromQL.TuistHistoryBenchTest do
  @moduledoc """
  Tuist's canary dashboard panels and alert rules over a remote-write
  history shaped like canary or production (`Pulse.Test.TuistMetricHistory`),
  stored in `Pulse.Test.LatencyStore` with Tigris latency (140-190 ms per
  GET, 220-350 ms per PUT), with metrics compaction off or on.

  Excluded by default. Build a history once, then query it as often as needed:

      PULSE_BENCH_VOLUME=canary PULSE_BENCH_COMPACTION=off PULSE_BENCH_DIR=/var/tmp/bench/canary-off \\
        mix test test/pulse/promql/tuist_history_bench_test.exs --include query_bench

  The first run builds the history into `PULSE_BENCH_DIR` and saves it; later
  runs reuse it (`PULSE_BENCH_PHASE=build|query|all`, default all).

  The history is one segment per 2 s batch for `PULSE_BENCH_HOURS` (26)
  hours ending at #{"2026-11-02T10:40:00Z"}. With compaction on, the real
  maintenance worker (`CompactionWorker`, chart defaults: merges, current-hour
  grouping, hour finalization, backups, cleanup) runs every simulated minute
  against a simulated clock, so every hour goes through what a node does to
  it as it arrives, and the store counts the requests maintenance makes.
  `PULSE_BENCH_COARSE_HOURS` older hours are written in 15 s segments
  first (for production, whose full-cadence history does not fit one disk),
  and with compaction on the metrics of 1-day to 7-day alert windows get 15
  days of older history so those windows read finalized hours.

  Queries run as the MCP `query_promql` tool runs them, with canary's default
  budgets and with the recommended production values, and the results go to
  `PULSE_BENCH_DIR/results-<profile>.json`.
  """
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.Parser
  alias Pulse.QueryLimit
  alias Pulse.QueryRunner
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.CompactionOwnership
  alias Pulse.Storage.S3.CompactionWorker
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.GrafanaCorpus
  alias Pulse.Test.LatencyStore
  alias Pulse.Test.TuistMetricHistory, as: History

  @moduletag :query_bench
  @moduletag timeout: :infinity

  @tenant "tuist"
  @end_ms DateTime.to_unix(~U[2026-11-02 10:40:00Z], :millisecond)
  # Scrape numbers count from here, so values depend only on the time.
  @origin_ms @end_ms - 40 * 86_400_000
  @hour_ms 3_600_000
  @minute_ms 60_000

  # The panels probed on canary over MCP (1.34.1, 2026-11-05).
  @panels [
    {"count rollout_active", "count(tuist_kura_rollout_active)"},
    {"Kura rollout current wave",
     ~s|max(tuist_kura_rollout_wave{env="canary"} and on () (max(tuist_kura_rollout_active{env="canary"}) == 1))|},
    {"Kura rollout active", ~s|max by (image_tag, mode) (tuist_kura_rollout_active{env="canary"} == 1)|},
    {"FD wait timeouts",
     ~s|sum by (pod) (rate(kura_file_descriptor_wait_seconds_count{result="timeout", cluster=~"tuist-canary"}[5m]))|},
    {"Processor waiting for DB",
     ~s|sum by (workload, repo) (tuist_repo_pool_checkout_queue_length{cluster="tuist-canary",workload=~".*",repo=~".*"})|},
    {"Processor pool starvation",
     ~s|100 * sum by (workload, repo) (rate(tuist_repo_pool_checkout_queue_starved_samples{cluster="tuist-canary"}[4m])) / sum by (workload, repo) (rate(tuist_repo_pool_checkout_queue_total_samples{cluster="tuist-canary"}[4m]))|},
    {"Processor query attempts",
     ~s|sum by (workload, repo, result) (rate(tuist_repo_query_count{cluster="tuist-canary",workload=~".*",repo=~".*"}[4m]))|},
    {"Runners running builds",
     ~s|sum(max by (fleet) (tuist_runners_claims_count{lifecycle_state="running", env="canary"}))|},
    {"Finch outgoing rate",
     ~s|sum by (request_host, request_method) (rate(tuist_http_request_count{instance=~".*", request_host=~".*", request_method=~".*", response_status=~".*"}[4m]))|},
    {"Finch error rate",
     ~s|100 * sum by (request_host) (rate(tuist_http_request_count{response_status!~"2.."}[4m])) / sum by (request_host) (rate(tuist_http_request_count[4m]))|},
    {"Phoenix p99",
     ~s|histogram_quantile(0.99, sum by (le) (rate(tuist_prom_ex_phoenix_http_request_duration_milliseconds_bucket{instance=~".*", host=~".*", method=~".*", status=~".*", path=~".*"}[4m])))|},
    {"Phoenix top routes p99",
     ~s|topk(25, histogram_quantile(0.99, sum by (method, path, le) (rate(tuist_prom_ex_phoenix_http_request_duration_milliseconds_bucket{instance=~".*", host=~".*", method=~".*", status=~".*", path=~".*"}[4m]))))|},
    {"Oban job execution time",
     ~s|sum(irate(tuist_oban_job_processing_duration_milliseconds_bucket{job="tuist", env="canary", name="Oban"}[5m])) by (le)|},
    {"Kura scrape status (up)", ~s|up{job="kura", cluster=~"tuist-canary", instance=~".*", pod=~"kura-(.*)-.*"}|},
    {"Cache CPU % (node_*)",
     ~s|100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{instance=~".*", mode="idle"}[4m])))|}
  ]

  @ranges [{"1h", 3600}, {"6h", 21_600}, {"24h", 86_400}]

  # Canary's defaults (1536Mi node: derived 128 MiB query heap) and the
  # recommended production values.
  @profiles %{
    "defaults" => %{evaluator: [], runner: [timeout_ms: 10_000, max_heap_words: div(128 * 1_048_576, 8)]},
    "recommended" => %{
      evaluator: [max_samples: 300_000, max_scan_bytes: 268_435_456],
      runner: [timeout_ms: 15_000, max_heap_words: div(160 * 1_048_576, 8)]
    },
    # What a query needs, with PULSE_BENCH_HEAP=1.
    "unbounded" => %{
      evaluator: [
        max_samples: 100_000_000,
        max_work: 100_000_000_000,
        max_result_points: 100_000_000,
        max_materialized_samples: 100_000_000,
        max_scan_segments: 1_000_000,
        max_scan_rows: 1_000_000_000,
        max_scan_bytes: 1_099_511_627_776
      ],
      runner: [timeout_ms: 300_000, max_heap_words: div(4096 * 1_048_576, 8)]
    }
  }

  defp env(name, default), do: System.get_env(name, default)
  defp env_int(name, default), do: name |> env(Integer.to_string(default)) |> String.to_integer()

  setup do
    volume = %{"canary" => :canary, "production" => :production} |> Map.fetch!(env("PULSE_BENCH_VOLUME", "canary"))
    mode = env("PULSE_BENCH_COMPACTION", "off")
    dir = env("PULSE_BENCH_DIR", Path.join(System.tmp_dir!(), "pulse-bench-#{volume}-#{mode}"))
    restore? = LatencyStore.saved?(dir)
    store = LatencyStore.new(dir: dir, restore: restore?, get_ms: {0, 0}, put_ms: {0, 0}, list_ms: {0, 0})

    server =
      start_supervised!(
        {Bandit,
         plug: {LatencyStore, store},
         ip: {127, 0, 0, 1},
         port: 0,
         thousand_island_options: [num_acceptors: 64, num_connections: 16_384]}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "auto",
      access_key_id: "bench",
      secret_access_key: "bench",
      allow_http: true,
      # The production default (PULSE_QUERY_PREFETCH), or PULSE_BENCH_PREFETCH.
      query_prefetch: env_int("PULSE_BENCH_PREFETCH", 4)
    }

    Runtime.put_env(:pulse, S3, config)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    start_supervised!(ManifestSupervision)

    %{volume: volume, mode: mode, dir: dir, store: store, config: config, restored?: restore?}
  end

  test "Tuist panels and alerts over a canary- or production-shaped history", ctx do
    phase = env("PULSE_BENCH_PHASE", "all")
    requests = corpus_requests()

    if phase in ["build", "all"] and not ctx.restored? do
      build(ctx, requests)
      LatencyStore.save(ctx.store)
    end

    if phase in ["query", "all"] do
      for profile <- String.split(env("PULSE_BENCH_PROFILES", "defaults,recommended"), ",") do
        run_queries(ctx, profile, requests)
      end
    end
  end

  # -- history ------------------------------------------------------------------

  defp corpus_requests do
    for request <- GrafanaCorpus.requests() do
      Map.update!(request, "interpolated", &History.canary_expr/1)
    end
  end

  defp build(ctx, requests) do
    hours = env_int("PULSE_BENCH_HOURS", 26)
    coarse_hours = env_int("PULSE_BENCH_COARSE_HOURS", 0)
    {targets, count} = History.targets(ctx.volume, requests)
    IO.puts("#{ctx.volume}: #{count} series in #{length(targets)} scrape targets")

    {:ok, _} =
      ObjectStore.put(
        ctx.config,
        Manifest.manifest_key(@tenant, "metrics"),
        IO.iodata_to_binary(Manifest.encode(Manifest.new()))
      )

    full_from = @end_ms - hours * @hour_ms
    coarse_from = full_from - coarse_hours * @hour_ms
    sim = sim(ctx)

    sim =
      if ctx.mode == "on" do
        old = long_window_targets(targets, requests)
        IO.puts("older history for long alert windows: #{Enum.sum_by(old, &length(elem(&1, 1)))} series")
        old_from = coarse_from - env_int("PULSE_BENCH_OLD_DAYS", 14) * 86_400_000
        sim = write_span(%{sim | mode: "old"}, old, old_from, coarse_from, 300_000)
        finalize_backlog(%{sim | mode: "on"}, coarse_from)
      else
        sim
      end

    # PULSE_BENCH_COARSE_SUBSET=1 writes only the metrics panels and alerts
    # query in coarse hours (production: about a third of the series).
    coarse = if env("PULSE_BENCH_COARSE_SUBSET", "") == "", do: targets, else: queried_targets(targets, requests)
    sim = write_span(sim, coarse, coarse_from, full_from, 15_000)
    sim = write_span(sim, targets, full_from, @end_ms, History.batch_ms())
    report_build(ctx, sim, full_from)
  end

  # Writes batches of `step_ms` over [from, to); with compaction on, a
  # maintenance pass follows every simulated minute.
  defp write_span(sim, targets, from, to, step_ms) do
    started = System.monotonic_time(:millisecond)

    sim =
      Stream.iterate(from, &(&1 + step_ms))
      |> Stream.take_while(&(&1 < to))
      |> Enum.reduce(sim, fn at, sim ->
        records = span_samples(targets, sim.volume, at, step_ms)
        sim = account(sim, :ingest, at, fn -> :ok = S3.append(:metrics, @tenant, records) end)

        sim =
          if sim.mode == "on" and div(at + step_ms, @minute_ms) > div(at, @minute_ms),
            do: pass(sim, at + step_ms),
            else: sim

        if rem(at + step_ms - from, @hour_ms) < step_ms do
          elapsed = System.monotonic_time(:millisecond) - started
          IO.puts("wrote up to #{DateTime.from_unix!(at + step_ms, :millisecond)} (#{div(elapsed, 1000)} s)")
        end

        sim
      end)

    sim
  end

  defp span_samples(targets, volume, at, step_ms) do
    for from <- at..(at + step_ms - 1)//History.batch_ms(),
        sample <- History.batch(targets, volume, @origin_ms, from),
        do: sample
  end

  # The series of metrics that 1-day to 7-day alert windows select.
  defp long_window_targets(targets, requests) do
    names =
      for %{"alerts" => [_ | _], "language" => "promql", "interpolated" => expr} <- requests,
          Regex.match?(~r/\[\d+d|offset \d+[dh]|\[\d+d:/, expr),
          {:ok, ast} = Parser.parse(expr),
          name <- metric_names(ast),
          into: MapSet.new(),
          do: name

    filter_targets(targets, names)
  end

  # The series of metrics any panel or corpus query selects.
  defp queried_targets(targets, requests) do
    exprs = Enum.map(@panels, &elem(&1, 1)) ++ for(%{"language" => "promql", "interpolated" => e} <- requests, do: e)

    names =
      for expr <- exprs, {:ok, ast} <- [Parser.parse(expr)], name <- metric_names(ast), into: MapSet.new(), do: name

    filter_targets(targets, names)
  end

  defp filter_targets(targets, names) do
    for {phase, series} <- targets,
        series = Enum.filter(series, fn {labels, _, _} -> MapSet.member?(names, labels["__name__"]) end),
        series != [],
        do: {phase, series}
  end

  defp metric_names({"__name__", :eq, name}) when is_binary(name), do: [name]
  defp metric_names(term) when is_tuple(term), do: term |> Tuple.to_list() |> metric_names()
  defp metric_names(term) when is_list(term), do: Enum.flat_map(term, &metric_names/1)
  defp metric_names(_), do: []

  defp sim(ctx) do
    tasks = start_supervised!({Task.Supervisor, name: :"bench_maintenance_#{System.unique_integer([:positive])}"})
    start_supervised!(%{id: CompactionOwnership, start: {:pg, :start_link, [CompactionOwnership.scope()]}})

    %{
      volume: ctx.volume,
      mode: ctx.mode,
      store: ctx.store,
      config: ctx.config,
      tasks: tasks,
      started_real: System.system_time(:millisecond),
      started_sim: nil,
      hours: %{},
      worker: nil
    }
  end

  # One CompactionWorker pass with the chart's defaults, its clocks shifted
  # to simulated time `now_ms`: settle windows, retirement grace and the
  # backup interval keep their simulated lengths.
  defp pass(sim, now_ms) do
    real = System.system_time(:millisecond)
    sim = %{sim | started_sim: sim.started_sim || now_ms}
    offset = real - now_ms
    # Real milliseconds per simulated millisecond so far.
    warp = max((real - sim.started_real) / max(now_ms - sim.started_sim, 1), 0.001)
    grace = max(round(3_600_000 * warp), 1)

    worker =
      Map.merge(sim.worker || Map.merge(sim.config, %{compaction_enabled: true, metric_finalize_enabled: true}), %{
        compaction_tasks: sim.tasks,
        compaction_options: [settle_ms: offset, grace_ms: grace],
        metric_finalize_options: [settle_ms: 600_000 + offset, consolidate_settle_ms: 15_000 + offset, grace_ms: grace],
        manifest_backup_interval_ms: max(round(900_000 * warp), 1)
      })

    {sim, worker} =
      account_value(sim, :maintenance, now_ms - 1, fn ->
        {:noreply, worker} = CompactionWorker.handle_info(:compact, worker)
        worker
      end)

    receive do
      :compact -> :ok
    after
      0 -> :ok
    end

    %{sim | worker: worker}
  end

  # Finalize the older history at once, until a pass writes nothing (not measured).
  defp finalize_backlog(sim, now_ms) do
    puts = fn -> Enum.sum(for {{_, _, "PUT", _}, {n, _}} <- LatencyStore.stats(sim.store), do: n) end
    before = puts.()
    sim = pass(sim, now_ms)

    if puts.() > before,
      do: finalize_backlog(sim, now_ms),
      else: %{sim | hours: %{}, started_sim: nil, started_real: System.system_time(:millisecond)}
  end

  defp account(sim, kind, at, fun), do: sim |> account_value(kind, at, fn -> fun.() end) |> elem(0)

  # Requests by billing class and wall time, per simulated hour and kind.
  defp account_value(sim, kind, at, fun) do
    before = LatencyStore.stats(sim.store)
    started = System.monotonic_time(:millisecond)
    value = fun.()
    elapsed = System.monotonic_time(:millisecond) - started
    after_ = LatencyStore.stats(sim.store)
    hour = div(at, @hour_ms) * @hour_ms

    delta =
      Enum.reduce(after_, %{"ms" => elapsed}, fn {{class, _purpose, _method, _status} = key, {count, _}}, acc ->
        {previous, _} = Map.get(before, key, {0, 0})
        Map.update(acc, class, count - previous, &(&1 + count - previous))
      end)

    hours =
      Map.update(sim.hours, {hour, kind}, delta, fn current -> Map.merge(current, delta, fn _, a, b -> a + b end) end)

    {%{sim | hours: hours}, value}
  end

  defp report_build(ctx, sim, full_from) do
    rows =
      for {{hour, kind}, delta} <- Enum.sort(sim.hours) do
        %{
          hour: DateTime.to_iso8601(DateTime.from_unix!(hour, :millisecond)),
          kind: kind,
          full_cadence: hour >= full_from
        }
        |> Map.merge(Map.new(delta, fn {k, v} -> {String.to_atom(k), v} end))
      end

    for row <- rows,
        do: IO.puts("#{row.hour} #{row.kind}: A #{row[:A] || 0} B #{row[:B] || 0} free #{row[:free] || 0} #{row.ms} ms")

    File.write!(
      Path.join(ctx.dir, "build.json"),
      Pulse.JSON.encode!(%{volume: ctx.volume, mode: ctx.mode, hours: rows})
    )
  end

  # -- queries --------------------------------------------------------------------

  defp run_queries(ctx, profile, requests) do
    %{evaluator: evaluator, runner: runner} = Map.fetch!(@profiles, profile)

    # PULSE_BENCH_HEAP_MB and PULSE_BENCH_SAMPLES override the profile's
    # query heap ceiling and sample budget.
    runner =
      case env("PULSE_BENCH_HEAP_MB", "") do
        "" -> runner
        mb -> Keyword.put(runner, :max_heap_words, div(String.to_integer(mb) * 1_048_576, 8))
      end

    evaluator =
      case env("PULSE_BENCH_SAMPLES", "") do
        "" -> evaluator
        samples -> Keyword.put(evaluator, :max_samples, String.to_integer(samples))
      end

    Runtime.put_env(:pulse, Evaluator, evaluator)
    Runtime.put_env(:pulse, QueryRunner, Keyword.merge([queue_ms: 0], runner))
    LatencyStore.set_latency(ctx.store, get_ms: {140, 190}, put_ms: {220, 350})
    end_ns = @end_ms * 1_000_000

    # Canary's pod has its manifest cached; load it before measuring.
    Evaluator.query("count(up)", @tenant, %{end_ts_ns: end_ns})

    only = Regex.compile!(env("PULSE_BENCH_ONLY", ""))

    # PULSE_BENCH_EXPRS ("a;;b") runs other expressions as panels instead.
    queries =
      case env("PULSE_BENCH_EXPRS", "") do
        "" -> @panels
        exprs -> exprs |> String.split(";;") |> Enum.with_index(&{"expr #{&2}", &1})
      end

    panels =
      for {range_name, range_s} <- @ranges,
          {name, query} <- queries,
          Regex.match?(only, "panel #{range_name} #{name}") do
        step_ms = max(15_000, range_s * 2)
        opts = %{start_ts_ns: end_ns - range_s * 1_000_000_000, end_ts_ns: end_ns, step_ns: step_ms * 1_000_000}
        measure(ctx, "panel #{range_name} #{name}", query, opts)
      end

    alerts =
      for %{"alerts" => [_ | _], "language" => "promql", "id" => id, "interpolated" => _} = request <- requests,
          Regex.match?(only, "alert #{id}") do
        # Alerts run their stored expression; Grafana interpolates only dashboards.
        measure(ctx, "alert #{id}", History.canary_expr(request["expr"]), %{end_ts_ns: end_ns})
      end

    rows = panels ++ alerts
    path = Path.join(ctx.dir, "results-#{profile}#{env("PULSE_BENCH_TAG", "")}.json")
    File.write!(path, Pulse.JSON.encode!(rows))
    ok = Enum.filter(alerts, &(&1.status == "ok"))
    times = ok |> Enum.map(& &1.ms) |> Enum.sort()

    IO.puts(
      "#{ctx.volume} compaction #{ctx.mode} #{profile}: alerts #{length(ok)}/#{length(alerts)} ok, " <>
        "p50 #{pct(times, 0.5)} ms p90 #{pct(times, 0.9)} ms; results in #{path}"
    )
  end

  defp pct([], _), do: nil
  defp pct(sorted, q), do: Enum.at(sorted, min(length(sorted) - 1, trunc(q * length(sorted))))

  defp measure(ctx, name, query, opts) do
    # PULSE_BENCH_HEAP=1 reports the largest query worker heap (above 16 MiB).
    heap? = env("PULSE_BENCH_HEAP", "") != ""
    if heap?, do: :erlang.system_monitor(self(), [{:large_heap, div(16 * 1_048_576, 8)}])
    before = LatencyStore.stats(ctx.store)
    started = System.monotonic_time(:millisecond)
    result = Evaluator.query(query, @tenant, opts)
    elapsed = System.monotonic_time(:millisecond) - started
    if heap?, do: :erlang.system_monitor(:undefined)
    heap = if heap?, do: peak_heap(0), else: 0
    limit = QueryLimit.take()
    {gets, bytes} = segment_reads(before, LatencyStore.stats(ctx.store))

    {status, detail, digest} =
      case result do
        {:ok, %{"data" => %{"result" => series}} = body} ->
          {"ok", "#{length(series)} series",
           :crypto.hash(:sha256, :erlang.term_to_binary(body["data"])) |> Base.encode16()}

        {:error, reason} ->
          {"error", QueryLimit.describe(limit) || inspect(reason), nil}
      end

    IO.puts(
      String.pad_trailing(name, 52) <>
        " #{String.pad_leading(Integer.to_string(elapsed), 6)} ms #{String.pad_leading(Integer.to_string(gets), 5)} GETs " <>
        "#{String.pad_leading(Float.to_string(Float.round(bytes / 1_048_576, 1)), 7)} MiB  #{status} #{detail}" <>
        if(heap?, do: " (heap #{div(heap, 1_048_576)} MiB)", else: "")
    )

    %{
      name: name,
      query: query,
      ms: elapsed,
      gets: gets,
      bytes: bytes,
      status: status,
      detail: detail,
      digest: digest,
      heap: heap
    }
  end

  defp peak_heap(peak) do
    receive do
      {:monitor, _pid, :large_heap, info} ->
        peak_heap(max(peak, (info[:heap_size] + info[:old_heap_size]) * 8))
    after
      0 -> peak
    end
  end

  defp segment_reads(before, after_) do
    for {{_class, "segment" <> _, "GET", _status} = key, {count, bytes}} <- after_, reduce: {0, 0} do
      {gets, total} ->
        {previous_count, previous_bytes} = Map.get(before, key, {0, 0})
        {gets + count - previous_count, total + bytes - previous_bytes}
    end
  end
end
