defmodule Pulse.PromQL.QueryScaleBenchTest do
  @moduledoc """
  Dashboard- and alert-shaped PromQL over a many-segment metric history, before
  and after metrics compaction, against the S3 adapter on an in-process fake S3
  that delays every segment GET.

  Excluded by default. The defaults model a single canary node: 6 hours of
  history, 55 metric segments a minute (remote-write shards of a 15 s scrape of
  3,000 series), 18 ms per segment GET and four segments of prefetch:

      mix test test/pulse/promql/query_scale_bench_test.exs --include query_bench

  Tune with PULSE_BENCH_HOURS, PULSE_BENCH_SEGMENTS_PER_MINUTE,
  PULSE_BENCH_SERIES, PULSE_BENCH_S3_LATENCY_MS and PULSE_BENCH_PREFETCH. The
  test prints segment GETs, bytes, wall time and outcome per query, and
  asserts that after compaction, with the documented budgets, every query
  succeeds and reads far fewer segments than the uncompacted history holds.

  A second test writes PULSE_BENCH_LONG_DAYS (7) days already shaped like
  compacted history (ten segments an hour) and runs 24-hour dashboards and
  1-day to 7-day alert windows with the long-window budgets.
  """
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.PromQL.Evaluator
  alias Pulse.QueryLimit
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.PagedManifest
  alias Pulse.Test.CompactionStore

  @moduletag :query_bench
  @moduletag timeout: :infinity

  @scrape_ns 15_000_000_000
  @t0 1_800_000_000 * 1_000_000_000

  # The budgets docs/configuration.md recommends with compaction enabled.
  @recommended [
    max_samples: 1_000_000,
    max_result_points: 1_000_000,
    max_materialized_samples: 1_000_000,
    max_work: 50_000_000,
    max_scan_segments: 4096,
    max_scan_rows: 50_000_000,
    max_scan_bytes: 1_073_741_824,
    max_heap_words: div(512 * 1_048_576, 8)
  ]

  # Long alert windows read every row of the window: 7 days of 3,000 series
  # at a 15 s scrape is 121M rows.
  @long_window [
    max_samples: 1_000_000,
    max_result_points: 1_000_000,
    max_materialized_samples: 1_000_000,
    max_work: 50_000_000,
    max_scan_segments: 4096,
    max_scan_rows: 200_000_000,
    max_scan_bytes: 4_294_967_296,
    max_heap_words: div(512 * 1_048_576, 8)
  ]

  # Budgets docs/configuration.md recommends once hours are finalized, for a
  # node of about 1.5 GiB: rows scanned are not retained, samples are.
  @finalized [
    max_samples: 500_000,
    max_result_points: 500_000,
    max_materialized_samples: 500_000,
    max_work: 50_000_000,
    max_scan_segments: 2048,
    max_scan_rows: 20_000_000,
    max_scan_bytes: 1_073_741_824,
    max_heap_words: div(256 * 1_048_576, 8)
  ]

  # The documented profile for week-long subqueries over raw samples, run with
  # PULSE_QUERY_MAX_CONCURRENT=1 on the same node size.
  @week_subquery [max_samples: 1_000_000, max_heap_words: div(384 * 1_048_576, 8)]

  defp env_int(name, default), do: name |> System.get_env(Integer.to_string(default)) |> String.to_integer()

  setup do
    latency = :atomics.new(1, [])
    hours = env_int("PULSE_BENCH_HOURS", 6)

    store =
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

    delay = fn method, key, _body ->
      if method == "GET" and String.ends_with?(key, ".parquet"), do: Process.sleep(:atomics.get(latency, 1))
    end

    server =
      start_supervised!(
        {Bandit,
         plug: {CompactionStore, agent: store, before_request: delay},
         ip: {127, 0, 0, 1},
         port: 0,
         thousand_island_options: [num_acceptors: 16]}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "bench-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      query_prefetch: env_int("PULSE_BENCH_PREFETCH", 4)
    }

    Runtime.put_env(:pulse, S3, config)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    start_supervised!(ManifestSupervision)
    tenant = "bench-#{System.unique_integer([:positive])}"

    {:ok, _} =
      ObjectStore.put(
        config,
        Manifest.manifest_key(tenant, "metrics"),
        IO.iodata_to_binary(Manifest.encode(Manifest.new()))
      )

    %{store: store, config: config, tenant: tenant, latency: latency, hours: hours}
  end

  # Series shaped like the panels that failed on canary, plus filler metrics.
  defp series(count) do
    named = up() ++ oban() ++ kura() ++ cnpg() ++ http()

    filler =
      for i <- 1..max(0, count - length(named)), do: %{"__name__" => "filler_#{div(i, 10)}", "instance" => "f#{i}"}

    named ++ filler
  end

  defp up, do: for(i <- 1..60, do: %{"__name__" => "up", "job" => "j#{rem(i, 6)}", "instance" => "i#{i}"})

  defp oban do
    for state <- ~w(available executing scheduled),
        queue <- ~w(default mailers builds cache events sync),
        do: %{"__name__" => "oban_queue_length", "env" => "canary", "state" => state, "queue" => queue}
  end

  defp kura do
    requests =
      for c <- ~w(c1 c2),
          i <- 1..5,
          p <- 1..4,
          do: %{"__name__" => "kura_http_requests_total", "cluster" => c, "instance" => "k#{i}", "pod" => "p#{p}"}

    requests ++
      for c <- ~w(c1 c2), i <- 1..5, do: %{"__name__" => "kura_node_info", "cluster" => c, "instance" => "k#{i}"}
  end

  defp cnpg do
    backends =
      for p <- 1..3,
          s <- ~w(active idle waiting other),
          do: %{"__name__" => "cnpg_backends_total", "namespace" => "tuist-canary", "pod" => "db#{p}", "state" => s}

    settings =
      for p <- 1..3, n <- 1..100 do
        name = if n == 1, do: "max_connections", else: "setting_#{n}"
        %{"__name__" => "cnpg_pg_settings_setting", "namespace" => "tuist-canary", "pod" => "db#{p}", "name" => name}
      end

    backends ++ settings
  end

  defp http do
    for r <- 1..20,
        s <- ~w(200 201 400 404 500),
        p <- 1..4,
        do: %{"__name__" => "http_server_requests_total", "route" => "r#{r}", "status" => s, "pod" => "p#{p}"}
  end

  defp build_history(ctx) do
    per_minute = env_int("PULSE_BENCH_SEGMENTS_PER_MINUTE", 55)
    shards = max(1, div(per_minute, 4))
    labels = series(env_int("PULSE_BENCH_SERIES", 3000))
    groups = labels |> Enum.with_index() |> Enum.group_by(fn {l, _} -> :erlang.phash2(l, shards) end)
    ticks = div(ctx.hours * 3_600_000_000_000, @scrape_ns)
    started = System.monotonic_time(:millisecond)

    for tick <- 0..(ticks - 1), {_shard, members} <- groups do
      ts = @t0 + tick * @scrape_ns

      records =
        for {l, index} <- members,
            do: %MetricSample{timestamp_ns: ts, value: (tick + 1) * (rem(index, 7) + 1) * 1.0, labels: l}

      :ok = S3.append(:metrics, ctx.tenant, records)
      if rem(tick, 240) == 0, do: trim(ctx.store)
    end

    trim(ctx.store)
    elapsed = System.monotonic_time(:millisecond) - started
    IO.puts("history: #{ticks * map_size(groups)} segments, #{length(labels)} series, built in #{elapsed} ms")
    @t0 + (ticks - 1) * @scrape_ns
  end

  defp trim(store), do: Agent.update(store, &%{&1 | reads: [], requests: []})

  defp compact(ctx) do
    started = System.monotonic_time(:millisecond)
    merges = compact_until_idle(ctx, 0, 0)
    elapsed = System.monotonic_time(:millisecond) - started
    IO.puts("compaction: #{merges} merges in #{elapsed} ms")
  end

  # Candidates rotate through history four leaves at a time; stop after a
  # full sweep's worth of passes merges nothing.
  defp compact_until_idle(_ctx, merges, idle) when idle >= 64, do: merges

  defp compact_until_idle(ctx, merges, idle) do
    case MetricsCompactor.compact(ctx.tenant, ctx.config) do
      {:ok, %{merged: merged}} when merged > 0 -> compact_until_idle(ctx, merges + 1, 0)
      {:ok, _} -> compact_until_idle(ctx, merges, idle + 1)
      error -> flunk("compaction failed: #{inspect(error)}")
    end
  end

  defp queries(finish) do
    range = fn hours, step_s ->
      %{start_ts_ns: finish - hours * 3_600_000_000_000, end_ts_ns: finish, step_ns: step_s * 1_000_000_000}
    end

    instant = %{end_ts_ns: finish}

    [
      {"oban 1h", ~s|sum by (queue) (oban_queue_length{env="canary", state="available"})|, range.(1, 15)},
      {"oban 6h", ~s|sum by (queue) (oban_queue_length{env="canary", state="available"})|, range.(6, 30)},
      {"kura and-on 6h",
       ~s|sum by (pod) (rate(kura_http_requests_total{cluster="c1"}[1m]) and on (cluster, instance) max by (cluster, instance) (kura_node_info{cluster="c1"}))|,
       range.(6, 30)},
      {"cnpg ratio 6h",
       ~s|100 * max(sum by (namespace, pod) (cnpg_backends_total{namespace=~"tuist-canary"}) / on (namespace, pod) clamp_min(max by (namespace, pod) (cnpg_pg_settings_setting{namespace=~"tuist-canary", name="max_connections"}), 1))|,
       range.(6, 30)},
      {"400 series rate 6h", ~s|sum by (status) (rate(http_server_requests_total[5m]))|, range.(6, 30)},
      {"alert increase(up[1h])", ~s|sum(increase(up[1h]))|, instant},
      {"alert [6h:5m] subquery", ~s|max(max_over_time(sum by (queue) (oban_queue_length)[6h:5m]))|, instant}
    ]
  end

  defp long_queries(finish) do
    instant = %{end_ts_ns: finish}
    day = %{start_ts_ns: finish - 86_400_000_000_000, end_ts_ns: finish, step_ns: 120_000_000_000}

    [
      {"oban 24h", ~s|sum by (queue) (oban_queue_length{env="canary", state="available"})|, day},
      {"kura and-on 24h",
       ~s|sum by (pod) (rate(kura_http_requests_total{cluster="c1"}[5m]) and on (cluster, instance) max by (cluster, instance) (kura_node_info{cluster="c1"}))|,
       day},
      {"alert increase(up[1d])", ~s|sum(increase(up[1d]))|, instant},
      {"alert [3d:30m] subquery", ~s|max(max_over_time(sum by (queue) (oban_queue_length)[3d:30m]))|, instant},
      {"alert [7d:5m] subquery", ~s|max(max_over_time(sum by (queue) (oban_queue_length)[7d:5m]))|, instant},
      {"alert offset 168h", ~s|sum(increase(up[1h])) - sum(increase(up[1h] offset 168h))|, instant},
      {"alert increase(up[7d])", ~s|sum(increase(up[7d]))|, instant},
      {"alert max_over_time(oban[3d])", ~s|max(max_over_time(oban_queue_length[3d]))|, instant},
      {"alert changes(up[7d])", ~s|sum(changes(up[7d]))|, instant}
    ]
  end

  defp run_queries(ctx, finish, phase, latency_ms, queries \\ nil) do
    :atomics.put(ctx.latency, 1, latency_ms)

    for {name, query, opts} <- queries || queries(finish) do
      trim(ctx.store)
      started = System.monotonic_time(:millisecond)
      result = Evaluator.query(query, ctx.tenant, opts)
      elapsed = System.monotonic_time(:millisecond) - started
      outcome = outcome(result)
      {gets, bytes} = reads(ctx.store)

      IO.puts(
        String.pad_trailing("#{phase} | #{name}", 52) <>
          " | GETs #{String.pad_leading(Integer.to_string(gets), 6)} | " <>
          "#{String.pad_leading(Float.to_string(Float.round(bytes / 1_048_576, 1)), 7)} MiB | " <>
          "#{String.pad_leading(Integer.to_string(elapsed), 6)} ms | #{outcome}"
      )

      {name, result, gets}
    end
  end

  defp outcome({:ok, %{"data" => %{"result" => result}}}), do: "ok, #{length(result)} series"
  defp outcome({:error, reason}), do: QueryLimit.describe(QueryLimit.take()) || inspect(reason)

  defp reads(store) do
    Agent.get(store, fn state ->
      keys = Enum.filter(state.reads, &String.ends_with?(&1, ".parquet"))
      {length(keys), Enum.sum_by(keys, &object_size(state.objects, &1))}
    end)
  end

  defp object_size(objects, key) do
    case Map.get(objects, key) do
      {_etag, body} -> byte_size(body)
      nil -> 0
    end
  end

  defp segment_count(ctx) do
    {:ok, entry} = ManifestOwner.ensure_loaded(ctx.tenant, "metrics", ctx.config)

    {:ok, segments} =
      PagedManifest.with_budget(ctx.config, fn ->
        JournalManifest.query(entry.manifest, ctx.tenant, "metrics", [], ctx.config)
      end)
      |> elem(1)

    length(segments)
  end

  test "dashboard and alert ranges over a canary-shaped history, before and after compaction", ctx do
    finish = build_history(ctx)
    latency = env_int("PULSE_BENCH_S3_LATENCY_MS", 18)
    before = segment_count(ctx)
    IO.puts("active segments before compaction: #{before}")

    run_queries(ctx, finish, "uncompacted, default budgets", latency)
    Runtime.put_env(:pulse, Evaluator, @recommended)
    run_queries(ctx, finish, "uncompacted, recommended budgets", latency)
    Runtime.delete_env(:pulse, Evaluator)

    :atomics.put(ctx.latency, 1, 0)
    compact(ctx)
    compacted = segment_count(ctx)
    IO.puts("active segments after compaction: #{compacted} (#{Float.round(compacted / ctx.hours, 1)} per hour)")

    run_queries(ctx, finish, "compacted, default budgets", latency)
    Runtime.put_env(:pulse, Evaluator, @recommended)
    results = run_queries(ctx, finish, "compacted, recommended budgets", latency)

    for {name, result, gets} <- results do
      assert {:ok, _} = result, "#{name} failed: #{inspect(result)}"
      assert gets <= compacted
    end

    assert compacted * 20 < before
  end

  test "24-hour dashboards and 1-day to 7-day alert windows over compacted-shaped history", ctx do
    days = env_int("PULSE_BENCH_LONG_DAYS", 7)
    labels = series(env_int("PULSE_BENCH_SERIES", 3000))
    # Ten segments an hour of every series, what compaction leaves behind,
    # plus an hour so that offset 168h still has data.
    ticks = div((days * 24 + 1) * 3_600_000_000_000, @scrape_ns)
    started = System.monotonic_time(:millisecond)

    for chunk <- Enum.chunk_every(0..(ticks - 1), 24) do
      records =
        for tick <- chunk,
            {l, index} <- Enum.with_index(labels),
            do: %MetricSample{
              timestamp_ns: @t0 + tick * @scrape_ns,
              value: (tick + 1) * (rem(index, 7) + 1) * 1.0,
              labels: l
            }

      :ok = S3.append(:metrics, ctx.tenant, records)
      trim(ctx.store)
    end

    finish = @t0 + (ticks - 1) * @scrape_ns
    segments = segment_count(ctx)
    elapsed = System.monotonic_time(:millisecond) - started

    IO.puts(
      "compacted-shaped history: #{days} days, #{segments} segments, #{length(labels)} series, built in #{elapsed} ms"
    )

    latency = env_int("PULSE_BENCH_S3_LATENCY_MS", 18)
    run_queries(ctx, finish, "compacted, default budgets", latency, long_queries(finish))
    Runtime.put_env(:pulse, Evaluator, @recommended)
    run_queries(ctx, finish, "compacted, recommended budgets", latency, long_queries(finish))
    Runtime.put_env(:pulse, Evaluator, @long_window)
    Runtime.put_env(:pulse, Pulse.QueryRunner, timeout_ms: env_int("PULSE_BENCH_LONG_TIMEOUT_MS", 30_000))
    results = run_queries(ctx, finish, "compacted, long-window budgets", latency, long_queries(finish))

    # Week-long range functions select every sample of the week: without
    # rollups they exceed the sample budget, which is what finalization fixes.
    for {name, result, _gets} <- results,
        not String.ends_with?(name, ["up[7d])", "oban[3d])"]),
        do: assert({:ok, _} = result, "#{name} failed: #{inspect(result)}")

    # Finalize every settled hour into metric-grouped segments and rollups.
    :atomics.put(ctx.latency, 1, 0)
    Runtime.put_env(:pulse, Evaluator, [])
    started = System.monotonic_time(:millisecond)

    for hour <- 0..(days * 24) do
      assert {:ok, _} = MetricTiers.finalize_hour(ctx.tenant, @t0 + hour * 3_600_000_000_000, ctx.config, [])
      trim(ctx.store)
    end

    elapsed = System.monotonic_time(:millisecond) - started
    IO.puts("finalized #{days * 24 + 1} hours in #{elapsed} ms: #{segment_count(ctx)} sample segments")

    run_queries(ctx, finish, "finalized, default budgets", latency, long_queries(finish))
    Runtime.put_env(:pulse, Evaluator, @finalized)
    finalized = run_queries(ctx, finish, "finalized, 1.5 GiB budgets", latency, long_queries(finish))

    # A week of 5-minute subquery steps reads raw samples (rollups cannot serve
    # it) and needs the larger sample profile docs/configuration.md describes.
    {subquery, rest} = Enum.split_with(finalized, fn {name, _, _} -> name == "alert [7d:5m] subquery" end)
    assert [{_, {:error, :query_sample_limit}, _}] = subquery
    Runtime.put_env(:pulse, Evaluator, Keyword.merge(@finalized, @week_subquery))
    weekly = Enum.filter(long_queries(finish), fn {name, _, _} -> name == "alert [7d:5m] subquery" end)
    finalized = rest ++ run_queries(ctx, finish, "finalized, week-subquery budgets", latency, weekly)
    raw = Map.new(results, fn {name, _, _} = row -> {name, row} end)

    for {name, tiered, gets} <- finalized do
      {^name, raw, raw_gets} = raw[name]
      assert {:ok, _} = tiered, "#{name} failed: #{inspect(tiered)}"
      assert gets < raw_gets
      if match?({:ok, _}, raw), do: assert(tiered == raw, name)
    end
  end
end
