defmodule PulseWeb.IngestLoadTest do
  @moduledoc """
  Mixed-burst ingest load test through the public HTTP ingest paths.

  Excluded by default. Run with:

      PULSE_LOAD_S3_LATENCY_MS=150..300 PULSE_LOAD_SECONDS=60 \\
        mix test test/pulse_web/ingest_load_test.exs --include ingest_load

  A remote-write replay flood (many shards that retry after 429) runs alongside
  steady open-loop Loki pushes, OTLP trace exports and a second tenant's
  remote writes against the S3 adapter on
  a fake S3 server that delays every request by a uniformly drawn latency.
  The test prints throughput, status counts, accepted latency and storage
  request counts, and asserts that Loki and traces are still admitted.
  """
  use Pulse.Test.Case, async: true

  import Bitwise

  alias Pulse.Loki.PushProto.Entry
  alias Pulse.Loki.PushProto.LabelPair
  alias Pulse.Loki.PushProto.PushRequest
  alias Pulse.Loki.PushProto.Timestamp
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.OTLPTraceFixture
  alias Pulse.Test.RuntimePlug

  @moduletag :ingest_load
  @moduletag timeout: :infinity

  defp env_int(name, default), do: name |> System.get_env(Integer.to_string(default)) |> String.to_integer()

  defp latency_range do
    case String.split(System.get_env("PULSE_LOAD_S3_LATENCY_MS", "150..300"), "..") do
      [low, high] -> {String.to_integer(low), String.to_integer(high)}
      [value] -> {String.to_integer(value), String.to_integer(value)}
    end
  end

  setup do
    Runtime.share()
    stats = :ets.new(:load_stats, [:public, :duplicate_bag, write_concurrency: true])
    {low, high} = latency_range()

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

    # Trim the store's request journals and drop stored segment bodies (never
    # read back here), so VM memory reflects Pulse rather than the fake store.
    trim = fn ->
      Agent.update(store, fn state ->
        objects =
          Map.new(state.objects, fn
            {key, {etag, _body}} when binary_part(key, byte_size(key) - 8, 8) == ".parquet" -> {key, {etag, ""}}
            entry -> entry
          end)

        %{state | reads: [], requests: [], objects: objects}
      end)
    end

    # Optional upload bandwidth: large flat manifests then take longer to PUT,
    # as they do on a real provider.
    bytes_per_ms = env_int("PULSE_LOAD_S3_MB_PER_S", 0) * 1000

    delay = fn method, key, body ->
      kind = if String.ends_with?(key, "manifest.json"), do: :manifest, else: :object
      :ets.insert(stats, {:s3, method, kind, byte_size(body)})
      transfer = if bytes_per_ms > 0, do: div(byte_size(body), bytes_per_ms), else: 0
      Process.sleep(low + :rand.uniform(high - low + 1) - 1 + transfer)
    end

    s3 =
      start_supervised!(
        {Bandit,
         plug: {CompactionStore, agent: store, before_request: delay},
         ip: {127, 0, 0, 1},
         port: 0,
         thousand_island_options: [num_acceptors: 16, shutdown_timeout: 100]},
        id: :s3
      )

    {:ok, {_, s3_port}} = ThousandIsland.listener_info(s3)

    Runtime.put_env(:pulse, Storage, adapter: S3)

    Runtime.put_env(:pulse, S3, %{
      bucket: "pulse",
      region: "us-east-1",
      endpoint: "http://127.0.0.1:#{s3_port}",
      access_key_id: "load-#{System.unique_integer([:positive])}",
      secret_access_key: "load",
      allow_http: true,
      ingest_flush_interval_ms: env_int("PULSE_LOAD_FLUSH_INTERVAL_MS", 50),
      manifest_format: System.get_env("PULSE_LOAD_MANIFEST_FORMAT", "paged")
    })

    Runtime.put_env(:pulse, Pulse.IngestAdmission, max_concurrent: env_int("PULSE_LOAD_MAX_CONCURRENT", 16))
    start_supervised!(S3.ManifestSupervision)
    start_supervised!(Pulse.IngestAdmission)

    api =
      start_supervised!(
        {Bandit,
         plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()},
         ip: {127, 0, 0, 1},
         port: 0,
         thousand_island_options: [num_acceptors: 32, num_connections: 4096]},
        id: :api
      )

    {:ok, {_, api_port}} = ThousandIsland.listener_info(api)
    start_supervised!({Finch, name: LoadFinch, pools: %{default: [size: 512, count: 1]}})

    {:ok, api: "http://127.0.0.1:#{api_port}", stats: stats, trim: trim, latency: {low, high}, store: store}
  end

  # Steady Alloy-shaped traffic against flat manifests already holding tens of
  # thousands of segments, as a single node without retention accumulates.
  # PULSE_LOAD_MANIFEST_FORMAT=flat keeps them flat; paged (the default)
  # converts them on the first write. PULSE_LOAD_PHASES splits the report into
  # equal phases with latency, memory and manifest size each:
  #
  #     PULSE_LOAD_S3_LATENCY_MS=40..90 PULSE_LOAD_S3_MB_PER_S=45 PULSE_LOAD_FLUSH_INTERVAL_MS=20 \\
  #       PULSE_LOAD_LOG_SEGMENTS=50000 PULSE_LOAD_PHASES=4 \\
  #       mix test test/pulse_web/ingest_load_test.exs --only staging_load
  @tag :staging_load
  test "steady Alloy traffic over large flat manifests", ctx do
    seconds = env_int("PULSE_LOAD_SECONDS", 60)
    seed_manifests(ctx.store)
    stats = ctx.stats

    :telemetry.attach_many(
      {__MODULE__, self()},
      [[:pulse, :operation, :stop], [:pulse, :ingest, :stage]],
      fn
        [:pulse, :ingest, :stage], measurements, metadata, _ ->
          :ets.insert(stats, {:stage, metadata.signal, metadata.stage, measurements.duration})

        _event, measurements, metadata, _ ->
          :ets.insert(stats, {:op, metadata.operation, metadata.purpose, measurements.duration})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, self()}) end)
    results = :ets.new(:load_results, [:public, :duplicate_bag, write_concurrency: true])

    # Warm up: the first request per signal loads its large manifest.
    for signal <- [:loki_pb, :rw_steady, :traces] do
      warmup = :ets.new(:warmup, [:public, :duplicate_bag])
      deliver(ctx, warmup, signal, staging_body(signal, 0), 500, 4)
      attempts = for {_, :attempt, status, ms} <- :ets.tab2list(warmup), do: "#{status} in #{round(ms)} ms"
      IO.puts("warmup #{signal} (first write, includes any manifest conversion): #{Enum.join(attempts, ", ")}")
    end

    :ets.delete_all_objects(stats)
    ctx.trim.()
    :erlang.garbage_collect()
    deadline = System.monotonic_time(:millisecond) + seconds * 1000
    started = System.monotonic_time(:millisecond)
    trimmer = Task.async(fn -> trim_loop(ctx.trim, deadline) end)
    runtime = Runtime.current()
    sampler = Task.async(fn -> Runtime.with(runtime, fn -> sample_phases(ctx.store, started, deadline, []) end) end)

    # Eight alloy-logs pods at 0.5 push/s each, one remote-write shard and one trace exporter.
    pods = for pod <- 1..8, do: Task.async(fn -> pod_loop(ctx, results, deadline, pod) end)
    rw = Task.async(fn -> paced(ctx, results, deadline, :rw_steady, 667) end)
    traces = Task.async(fn -> paced(ctx, results, deadline, :traces, 2000) end)
    Task.await_many([rw, traces | pods], :infinity)
    elapsed = (System.monotonic_time(:millisecond) - started) / 1000
    Task.await(trimmer, :infinity)
    samples = Task.await(sampler, :infinity)

    IO.puts(staging_report(results, ctx, elapsed))
    IO.puts(phase_report(results, samples, started, seconds * 1000, env_int("PULSE_LOAD_PHASES", 1)))
    IO.puts(retained_report(ctx.store))
    assert :ets.select_count(results, [{{:loki_pb, :attempt, 204, :_}, [], [true]}]) > 0
  end

  defp pod_loop(ctx, results, deadline, pod) do
    # Each pod starts at its own phase and keeps a jittered two-second interval.
    Process.sleep(:rand.uniform(2000))
    paced(ctx, results, deadline, :loki_pb, 2000, pod)
  end

  defp paced(ctx, results, deadline, signal, interval, variant \\ 0) do
    if System.monotonic_time(:millisecond) < deadline do
      started = System.monotonic_time(:millisecond)
      task = Task.async(fn -> deliver(ctx, results, signal, staging_body(signal, variant), 500, 4) end)
      wait = interval - 200 + :rand.uniform(400) - (System.monotonic_time(:millisecond) - started)
      if wait > 0, do: Process.sleep(wait)
      paced(ctx, results, deadline, signal, interval, variant)
      Task.await(task, :infinity)
    else
      :ok
    end
  end

  @staging_services ~w(alloy-logs cilium-agent containerd.service ingress-nginx kubelet.service kura pomerium
    postgresql pulse tailscale tuist tuist-runner omada-controller metrics-server docker external-dns)

  defp staging_body(:loki_pb, pod) do
    now = System.system_time(:nanosecond)
    services = @staging_services |> Enum.shuffle() |> Enum.take(2 + rem(pod, 4))

    streams =
      for {service, s} <- Enum.with_index(services) do
        labels =
          ~s({cluster="tuist-staging", container="#{service}", job="ns/#{service}", namespace="ns", ) <>
            ~s(pod="#{service}-#{pod}", service_name="#{service}", stream="stdout"})

        entries =
          for i <- 1..5 do
            ts = now - (5 - i) * 1_000_000 + s

            %Entry{
              timestamp: %Timestamp{seconds: div(ts, 1_000_000_000), nanos: rem(ts, 1_000_000_000)},
              line: "#{service} level=info msg=\"handled request #{i}\" path=/api/projects duration=#{i}ms",
              structured_metadata: [%LabelPair{name: "detected_level", value: "info"}]
            }
          end

        %Pulse.Loki.PushProto.Stream{labels: labels, entries: entries}
      end

    {iodata, _} = PushRequest.encode!(%PushRequest{streams: streams})
    {:ok, compressed} = :snappyer.compress(IO.iodata_to_binary(iodata))
    compressed
  end

  defp staging_body(:rw_steady, _), do: remote_write_body(:rand.uniform(1000), 500)
  defp staging_body(:traces, _), do: trace_body(20)

  # Flat manifests shaped like staging's after a day without retention.
  defp seed_manifests(store) do
    now = System.os_time(:nanosecond)

    for {signal, count} <- [
          {"logs", env_int("PULSE_LOAD_LOG_SEGMENTS", 44_000)},
          {"metrics", env_int("PULSE_LOAD_METRIC_SEGMENTS", 25_000)},
          {"traces", env_int("PULSE_LOAD_TRACE_SEGMENTS", 8_000)}
        ] do
      segments =
        for i <- count..1//-1 do
          max_ts = now - i * 1_000_000_000
          seed_segment(signal, i, max_ts - 2_000_000_000, max_ts)
        end

      body = %S3.Manifest{version: 1, segments: segments} |> S3.Manifest.encode() |> IO.iodata_to_binary()
      key = S3.Manifest.manifest_key("default", signal)
      Agent.update(store, &put_in(&1.objects[key], {"\"seed-#{signal}\"", body}))
    end
  end

  defp seed_segment(signal, i, min_ts, max_ts) do
    key = S3.object_key("default", signal, min_ts, max_ts, Integer.to_string(i, 16), nil)
    segment = Segment.build(key, min_ts, max_ts, 15 + rem(i, 40), 9000 + rem(i, 9000))

    case signal do
      "logs" ->
        services = @staging_services |> Enum.take_random(2 + rem(i, 4)) |> Enum.sort()
        %{segment | log_services: services, log_labels: %{"error_project" => [""], "error_source" => [""]}}

      "metrics" ->
        names = for n <- Enum.take_random(1..300, 1 + rem(i, 40)), do: "metric_#{n}"
        %{segment | metric_names: Enum.sort(names), metric_labels: %{"job" => ["load"], "variant" => ["#{rem(i, 7)}"]}}

      "traces" ->
        segment
    end
  end

  # Every second: VM memory and the cached manifest state of this node.
  defp sample_phases(store, started, deadline, acc) do
    now = System.monotonic_time(:millisecond)

    if now < deadline do
      sizes = S3.ManifestCache.sizes()
      {pages, page_bytes} = S3.MetadataCache.stats()

      sample = %{
        at: now - started,
        memory: :erlang.memory(:total),
        # Bodies the fake S3 server holds (manifests and pages), not Pulse's memory.
        store: Agent.get(store, fn state -> Enum.sum(for {_, {_, body}} <- state.objects, do: byte_size(body)) end),
        referenced: for(signal <- ["logs", "metrics"], do: sizes |> Map.get(signal, %{}) |> Map.get(2, 0)),
        root_bytes: Enum.sum(for {_, size} <- sizes, do: Map.get(size, 1, 0)),
        pages: pages,
        page_bytes: page_bytes
      }

      Process.sleep(1000)
      sample_phases(store, started, deadline, [sample | acc])
    else
      Enum.reverse(acc)
    end
  end

  # Memory still referenced after every process collects its garbage.
  defp retained_report(store) do
    for pid <- Process.list(), do: :erlang.garbage_collect(pid)
    stored = Agent.get(store, fn state -> Enum.sum(for {_, {_, body}} <- state.objects, do: byte_size(body)) end)
    memory = :erlang.memory()

    top =
      for(
        pid <- Process.list(),
        info = Process.info(pid, [:memory, :binary, :registered_name, :initial_call]),
        do: info
      )
      |> Enum.map(fn info ->
        binary = info[:binary] |> Enum.uniq_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        {info[:memory] + binary, info[:registered_name], info[:initial_call]}
      end)
      |> Enum.sort(:desc)
      |> Enum.take(5)
      |> Enum.map_join(", ", fn {bytes, name, call} ->
        "#{inspect(if name == [], do: call, else: name)} #{div(bytes, 1_048_576)} MiB"
      end)

    mib = &div(&1, 1_048_576)

    "retained after full GC: total #{mib.(memory[:total])} MiB, fake-S3 bodies #{mib.(stored)} MiB, " <>
      "ets #{mib.(memory[:ets])} MiB, binary #{mib.(memory[:binary])} MiB, processes #{mib.(memory[:processes])} MiB; " <>
      "largest: #{top}"
  end

  defp phase_latency(rows, signal, in_phase) do
    ok = for {^signal, at, status, ms} <- rows, in_phase.(at), is_integer(status) and status < 300, do: ms
    "#{signal} p50 #{pct(ok, 0.5)} p90 #{pct(ok, 0.9)}"
  end

  defp phase_report(results, samples, started, total_ms, phases) do
    width = div(total_ms, phases)
    rows = :ets.select(results, [{{:"$1", :at, :"$2", :"$3", :"$4"}, [], [{{:"$1", :"$2", :"$3", :"$4"}}]}])

    lines =
      for phase <- 0..(phases - 1) do
        {low, high} = {phase * width, (phase + 1) * width}
        in_phase = fn at -> at - started >= low and at - started < high end

        latency = for signal <- [:loki_pb, :rw_steady, :traces], do: phase_latency(rows, signal, in_phase)

        window = Enum.filter(samples, &(&1.at >= low and &1.at < high))
        last = List.last(window) || %{referenced: [0, 0], root_bytes: 0, pages: 0, page_bytes: 0}
        peak = window |> Enum.map(& &1.memory) |> Enum.max(fn -> 0 end)
        own = window |> Enum.map(&(&1.memory - &1.store)) |> Enum.max(fn -> 0 end)
        [logs, metrics] = last.referenced

        "  phase #{phase + 1} (#{div(low, 1000)}-#{div(high, 1000)} s): #{Enum.join(latency, ", ")} ms; " <>
          "peak VM #{div(peak, 1_048_576)} MiB (#{div(own, 1_048_576)} MiB without fake-S3 bodies); segments logs #{logs} metrics #{metrics}; " <>
          "cached roots #{div(last.root_bytes, 1024)} KiB, page cache #{last.pages} pages #{div(last.page_bytes, 1024)} KiB"
      end

    Enum.join(["", "phases (manifest format #{System.get_env("PULSE_LOAD_MANIFEST_FORMAT", "paged")}):" | lines], "\n")
  end

  defp staging_report(results, ctx, elapsed) do
    rows = :ets.tab2list(results)
    s3 = :ets.tab2list(ctx.stats)

    lines =
      for signal <- [:loki_pb, :rw_steady, :traces] do
        ok = for {^signal, :attempt, status, ms} <- rows, is_integer(status) and status < 300, do: ms
        failed = Enum.count(rows, &match?({^signal, :attempt, status, _} when status not in 200..299, &1))
        mean = if ok != [], do: round(Enum.sum(ok) / length(ok))

        "  #{signal}: #{length(ok)} ok (#{Float.round(length(ok) / elapsed, 2)}/s) mean #{mean} ms " <>
          "p50 #{pct(ok, 0.5)} ms p90 #{pct(ok, 0.9)} ms p99 #{pct(ok, 0.99)} ms failed #{failed}"
      end

    puts = for {:s3, "PUT", kind, bytes} <- s3, do: {kind, bytes}
    manifest = for {:manifest, bytes} <- puts, do: bytes
    segments = Enum.count(puts, &(elem(&1, 0) == :object))

    stages =
      for({:stage, signal, stage, duration} <- s3, do: {{signal, stage}, duration})
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.sort()
      |> Enum.map(fn {{signal, stage}, durations} ->
        mean = System.convert_time_unit(div(Enum.sum(durations), length(durations)), :native, :microsecond)
        "    #{signal}/#{stage}: n=#{length(durations)} mean #{Float.round(mean / 1000, 1)} ms"
      end)

    operations =
      for({:op, operation, purpose, duration} <- s3, do: {{operation, purpose}, duration})
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.sort()
      |> Enum.map(fn {{operation, purpose}, durations} ->
        mean = durations |> Enum.sum() |> div(length(durations)) |> System.convert_time_unit(:native, :millisecond)
        "    #{operation}/#{purpose}: #{length(durations)} calls, mean #{mean} ms"
      end)

    {low, high} = ctx.latency

    [
      "",
      "staging-shaped load: #{Float.round(elapsed, 1)} s, S3 #{low}..#{high} ms + " <>
        "#{env_int("PULSE_LOAD_S3_MB_PER_S", 0)} MB/s, flush #{env_int("PULSE_LOAD_FLUSH_INTERVAL_MS", 50)} ms",
      lines,
      "  S3: #{segments} segment PUTs, #{length(manifest)} manifest PUTs " <>
        "(mean #{div(Enum.sum(manifest), max(length(manifest), 1))} B, max #{Enum.max(manifest, fn -> 0 end)} B)",
      "  object store operations:",
      operations,
      "  ingest stages:",
      stages
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  test "a remote-write flood does not starve steady Loki and OTLP trace ingest", ctx do
    seconds = env_int("PULSE_LOAD_SECONDS", 30)
    shards = env_int("PULSE_LOAD_RW_SHARDS", 64)
    deadline = System.monotonic_time(:millisecond) + seconds * 1000
    results = :ets.new(:load_results, [:public, :duplicate_bag, write_concurrency: true])

    rw_bodies = for i <- 1..16, do: remote_write_body(i, env_int("PULSE_LOAD_RW_SAMPLES", 2000))
    loki_body = loki_body(100)
    trace_body = trace_body(50)

    memory = Task.async(fn -> sample_memory(deadline, 0) end)
    stats = ctx.stats

    :telemetry.attach(
      {__MODULE__, self()},
      [:pulse, :operation, :stop],
      fn _event, measurements, metadata, _ ->
        :ets.insert(stats, {:op, metadata.operation, metadata.purpose, measurements.duration})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, self()}) end)
    cpu_start = :scheduler.sample_all()

    flood =
      for shard <- 1..shards do
        Task.async(fn -> flood(ctx, results, deadline, Enum.at(rw_bodies, rem(shard, 16))) end)
      end

    loki = Task.async(fn -> open_loop(ctx, results, deadline, :loki, env_int("PULSE_LOAD_LOKI_RPS", 4), loki_body) end)

    traces =
      Task.async(fn -> open_loop(ctx, results, deadline, :traces, env_int("PULSE_LOAD_TRACE_RPS", 2), trace_body) end)

    # A second remote-write tenant with steady traffic beside the flooding one.
    steady_body = Enum.at(rw_bodies, 0)

    steady =
      Task.async(fn ->
        open_loop(ctx, results, deadline, :steady_metrics, env_int("PULSE_LOAD_STEADY_RW_RPS", 2), steady_body)
      end)

    trimmer = Task.async(fn -> trim_loop(ctx.trim, deadline) end)
    started = System.monotonic_time(:millisecond)
    Task.await_many([loki, traces, steady | flood], :infinity)
    elapsed = (System.monotonic_time(:millisecond) - started) / 1000
    Task.await(trimmer, :infinity)
    peak = Task.await(memory, :infinity)
    cpu = :scheduler.utilization(cpu_start, :scheduler.sample_all())
    {:total, total, _} = List.keyfind(cpu, :total, 0)

    report = report(results, ctx, elapsed, peak, total)
    IO.puts(report.text)

    assert report.accepted.loki > 0
    assert report.accepted.traces > 0
    assert report.dropped.loki == 0, "Loki pushes dropped after retries: #{report.dropped.loki}"
    assert report.dropped.traces == 0, "trace exports dropped after retries: #{report.dropped.traces}"
    assert report.dropped.steady_metrics == 0, "steady tenant writes dropped: #{report.dropped.steady_metrics}"
  end

  # Alloy's remote-write shard of the flooding "default" tenant: send, back off after a 429, repeat.
  defp flood(ctx, results, deadline, body) do
    if System.monotonic_time(:millisecond) < deadline do
      {status, ms} = post(ctx.api <> "/api/v1/write", body, remote_write_headers())
      :ets.insert(results, {:remote_write, :attempt, status, ms})
      if status == 429, do: Process.sleep(env_int("PULSE_LOAD_RW_BACKOFF_MS", 200))
      flood(ctx, results, deadline, body)
    else
      :ok
    end
  end

  # Fixed arrival rate; each push retries a 429 with exponential backoff, as
  # loki.write and the OTLP exporter do, and counts as dropped when it gives up.
  defp open_loop(ctx, results, deadline, signal, rps, body) do
    interval = div(1000, rps)
    start = System.monotonic_time(:millisecond)

    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn n -> start + n * interval end)
    |> Stream.take_while(&(&1 < deadline))
    |> Enum.map(fn at ->
      wait = at - System.monotonic_time(:millisecond)
      if wait > 0, do: Process.sleep(wait)
      Task.async(fn -> deliver(ctx, results, signal, body, 500, 4) end)
    end)
    |> Task.await_many(:infinity)
  end

  defp deliver(_ctx, results, signal, _body, _backoff, 0), do: :ets.insert(results, {signal, :dropped})

  defp deliver(ctx, results, signal, body, backoff, tries) do
    {path, headers} = target(signal)
    {status, ms} = post(ctx.api <> path, body, headers)
    :ets.insert(results, {signal, :attempt, status, ms})
    :ets.insert(results, {signal, :at, System.monotonic_time(:millisecond), status, ms})

    if status in [429, 503] do
      Process.sleep(backoff)
      deliver(ctx, results, signal, body, backoff * 2, tries - 1)
    end
  end

  defp target(:loki_pb), do: {"/loki/api/v1/push", [{"content-type", "application/x-protobuf"}]}
  defp target(:rw_steady), do: {"/api/v1/write", remote_write_headers()}
  defp target(:loki), do: {"/loki/api/v1/push", [{"content-type", "application/json"}]}
  defp target(:traces), do: {"/v1/traces", [{"content-type", "application/json"}]}
  defp target(:steady_metrics), do: {"/api/v1/write", [{"x-scope-orgid", "steady"} | remote_write_headers()]}

  defp post(url, body, headers) do
    started = System.monotonic_time(:microsecond)

    status =
      case Req.post(url, body: body, headers: headers, retry: false, finch: [name: LoadFinch], receive_timeout: 60_000) do
        {:ok, response} -> response.status
        {:error, _} -> :transport_error
      end

    {status, (System.monotonic_time(:microsecond) - started) / 1000}
  end

  defp trim_loop(trim, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      trim.()
      Process.sleep(200)
      trim_loop(trim, deadline)
    end
  end

  defp sample_memory(deadline, peak) do
    peak = max(peak, :erlang.memory(:total))

    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(250)
      sample_memory(deadline, peak)
    else
      peak
    end
  end

  defp report(results, ctx, elapsed, peak, cpu) do
    rows = :ets.tab2list(results)
    s3 = :ets.tab2list(ctx.stats)

    per_signal =
      for signal <- [:remote_write, :steady_metrics, :loki, :traces], into: %{} do
        attempts = for {^signal, :attempt, status, ms} <- rows, do: {status, ms}
        ok = for {status, ms} <- attempts, is_integer(status) and status < 300, do: ms
        statuses = attempts |> Enum.frequencies_by(&elem(&1, 0)) |> Enum.sort()
        dropped = Enum.count(rows, &match?({^signal, :dropped}, &1))
        {signal, %{ok: length(ok), statuses: statuses, p50: pct(ok, 0.5), p90: pct(ok, 0.9), dropped: dropped}}
      end

    puts = for {:s3, "PUT", kind, bytes} <- s3, do: {kind, bytes}
    segment_puts = Enum.count(puts, &(elem(&1, 0) == :object))
    manifest_puts = Enum.count(puts, &(elem(&1, 0) == :manifest))
    manifest_bytes = puts |> Enum.filter(&(elem(&1, 0) == :manifest)) |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)
    gets = Enum.count(s3, &match?({:s3, "GET", _, _}, &1))

    operations =
      for({:op, operation, purpose, duration} <- s3, do: {{operation, purpose}, duration})
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.sort()
      |> Enum.map(fn {{operation, purpose}, durations} ->
        mean = durations |> Enum.sum() |> div(length(durations)) |> System.convert_time_unit(:native, :millisecond)
        "    #{operation}/#{purpose}: #{length(durations)} calls, mean #{mean} ms"
      end)

    lines =
      for {signal, row} <- per_signal do
        "  #{signal}: accepted #{row.ok} (#{Float.round(row.ok / elapsed, 1)}/s) " <>
          "p50 #{row.p50} ms p90 #{row.p90} ms statuses #{inspect(row.statuses)} dropped #{row.dropped}"
      end

    {low, high} = ctx.latency

    text =
      [
        "",
        "ingest load: #{Float.round(elapsed, 1)} s, S3 latency #{low}..#{high} ms, " <>
          "max_concurrent #{env_int("PULSE_LOAD_MAX_CONCURRENT", 16)}, " <>
          "flush #{env_int("PULSE_LOAD_FLUSH_INTERVAL_MS", 50)} ms",
        lines,
        "  total accepted #{Enum.sum(Enum.map(per_signal, fn {_, row} -> row.ok end)) |> Kernel./(elapsed) |> Float.round(1)} req/s",
        "  S3: #{segment_puts} segment PUTs, #{manifest_puts} manifest PUTs (max #{manifest_bytes} B), #{gets} GETs",
        "  object store operations:",
        operations,
        "  peak VM memory #{div(peak, 1024 * 1024)} MiB, scheduler utilization #{Float.round(cpu * 100, 1)}%"
      ]
      |> List.flatten()
      |> Enum.join("\n")

    %{
      text: text,
      accepted: Map.new(per_signal, fn {signal, row} -> {signal, row.ok} end),
      dropped: Map.new(per_signal, fn {signal, row} -> {signal, row.dropped} end)
    }
  end

  defp pct([], _), do: nil

  defp pct(values, q) do
    sorted = Enum.sort(values)
    sorted |> Enum.at(min(length(sorted) - 1, trunc(q * length(sorted)))) |> round()
  end

  # ---- payloads -----------------------------------------------------------

  defp remote_write_headers do
    [
      {"content-type", "application/x-protobuf"},
      {"content-encoding", "snappy"},
      {"x-prometheus-remote-write-version", "0.1.0"}
    ]
  end

  # One sample per series, like a replaying Alloy shard (max_samples_per_send 2000).
  defp remote_write_body(variant, samples) do
    now = System.system_time(:millisecond)

    series =
      for i <- 1..samples do
        labels = [
          {"__name__", "load_metric_#{rem(i, 50)}"},
          {"instance", "pod-#{rem(i, 37)}"},
          {"job", "load"},
          {"series", Integer.to_string(i)},
          {"variant", Integer.to_string(variant)}
        ]

        labels_bytes = Enum.map_join(labels, "", fn {n, v} -> field(1, field(1, n) <> field(2, v)) end)
        sample = tag(1, 1) <> <<i * 1.0::little-float-64>> <> tag(2, 0) <> varint(now - variant * 1000)
        field(1, labels_bytes <> field(2, sample))
      end

    {:ok, compressed} = :snappyer.compress(IO.iodata_to_binary(series))
    compressed
  end

  defp loki_body(lines) do
    now = System.system_time(:nanosecond)
    values = for i <- 1..lines, do: [Integer.to_string(now + i), "level=info msg=\"request #{i}\" duration=12ms"]

    Pulse.JSON.encode!(%{
      "streams" => [%{"stream" => %{"service_name" => "load", "env" => "staging"}, "values" => values}]
    })
  end

  defp trace_body(spans) do
    now = System.system_time(:nanosecond)

    spans =
      for i <- 1..spans do
        span = OTLPTraceFixture.span(now + i)
        id = i |> Integer.to_string(16) |> String.pad_leading(16, "0") |> String.downcase()
        %{span | "spanId" => id}
      end

    Pulse.JSON.encode!(OTLPTraceFixture.payload(spans))
  end

  defp varint(v) when v < 128, do: <<v>>
  defp varint(v), do: <<(v &&& 0x7F) ||| 0x80>> <> varint(v >>> 7)
  defp tag(field, wire), do: varint(field <<< 3 ||| wire)
  defp field(number, bytes), do: tag(number, 2) <> varint(byte_size(bytes)) <> bytes
end
