# Production-volume load test against a running Pulse instance.
#
# Starts an S3-compatible store with canary-measured latency
# (Pulse.Test.LatencyStore), drives Tuist-production-shaped remote write, Loki
# push and OTLP trace traffic plus dashboard queries at a running Pulse, and
# reports acknowledgment latency, Pulse memory, object requests per second by
# billing class and the projected monthly Tigris bill.
#
#     MIX_ENV=test mix run --no-start scripts/production_load.exs
#
# Point Pulse at the store first (it listens on LOAD_S3_PORT, default 9100,
# bucket `pulse`, any credentials) and start it with the configuration under
# test, for example a release:
#
#     PULSE_S3_ENDPOINT=http://127.0.0.1:9100 PULSE_S3_BUCKET=pulse PULSE_S3_REGION=auto \
#       PULSE_S3_ALLOW_HTTP=true PULSE_S3_ACCESS_KEY_ID=load PULSE_S3_SECRET_ACCESS_KEY=load \
#       PULSE_TENANT_TOKENS='{"tuist":"sha256$<sha256 of LOAD_TOKEN>"}' ... _build/prod/rel/pulse/bin/pulse start
#
# The script waits for LOAD_PULSE_URL (default http://127.0.0.1:4000) to answer
# /healthz. Rates default to Tuist production (Grafana Cloud, November 2026):
# 400,000 active series scraped every 30 s, 3,400 log lines/s, 1,000 spans/s.
# Push counts are assumptions: Class A requests scale with pushes, not bytes,
# so set LOAD_*_RPS from your collectors' real request rates.
#
# Environment (defaults in parentheses):
#   LOAD_SECONDS (600), LOAD_WARMUP_SECONDS (60), LOAD_REPORT (path for the JSON report)
#   LOAD_SERIES (400000), LOAD_SCRAPE_SECONDS (30), LOAD_METRICS_RPS (20)
#   LOAD_LOG_LINES (3400 per second), LOAD_LOG_RPS (40)
#   LOAD_SPANS (1000 per second), LOAD_TRACE_RPS (10)
#   LOAD_QUERY_INTERVAL_SECONDS (30), LOAD_QUERY_CONCURRENCY (2), LOAD_ALIGN_QUERIES (true)
#   LOAD_S3_GET_MS (140..190), LOAD_S3_PUT_MS (220..350)
#   LOAD_S3_DIR (/tmp/pulse-load-s3), LOAD_TENANT (tuist), LOAD_TOKEN (load-token)

defmodule Pulse.ProductionLoad do
  import Bitwise

  alias Pulse.Loki.PushProto.Entry
  alias Pulse.Loki.PushProto.LabelPair
  alias Pulse.Loki.PushProto.PushRequest
  alias Pulse.Loki.PushProto.Stream, as: LokiStream
  alias Pulse.Loki.PushProto.Timestamp
  alias Pulse.Test.LatencyStore

  @month_seconds 30 * 86_400
  @class_a 0.005 / 1000
  @class_b 0.0005 / 1000
  @storage_gib_month 0.02

  def env(name, default), do: System.get_env(name, default)
  def int(name, default), do: name |> env(Integer.to_string(default)) |> String.to_integer()

  def range(name, default) do
    case String.split(env(name, default), "..") do
      [low, high] -> {String.to_integer(low), String.to_integer(high)}
      [value] -> {String.to_integer(value), String.to_integer(value)}
    end
  end

  def run do
    {:ok, _} = Application.ensure_all_started([:bandit, :req, :snappyer])
    s3_dir = env("LOAD_S3_DIR", "/tmp/pulse-load-s3")
    File.rm_rf!(s3_dir)

    store =
      LatencyStore.new(dir: s3_dir, get_ms: range("LOAD_S3_GET_MS", "140..190"), put_ms: range("LOAD_S3_PUT_MS", "220..350"))

    {:ok, _} =
      Bandit.start_link(
        plug: {LatencyStore, store},
        ip: {127, 0, 0, 1},
        port: int("LOAD_S3_PORT", 9100),
        thousand_island_options: [num_acceptors: 64, num_connections: 16_384]
      )

    {:ok, _} = Finch.start_link(name: LoadFinch, pools: %{default: [size: 1024, count: 1]})
    url = env("LOAD_PULSE_URL", "http://127.0.0.1:4000")
    IO.puts("fake S3 listening on #{int("LOAD_S3_PORT", 9100)}; waiting for #{url}/healthz")
    wait_ready(url, 600)

    results = :ets.new(:results, [:public, :duplicate_bag, write_concurrency: true])
    inflight = :ets.new(:inflight, [:public, :set, write_concurrency: true])
    for signal <- [:metrics, :logs, :traces], do: :ets.insert(inflight, {signal, 0})
    ctx = %{url: url, results: results, inflight: inflight, store: store, tenant: env("LOAD_TENANT", "tuist")}
    ctx = Map.put(ctx, :headers, auth_headers(ctx.tenant))

    series = int("LOAD_SERIES", 400_000)
    scrape = int("LOAD_SCRAPE_SECONDS", 30)
    metrics_rps = int("LOAD_METRICS_RPS", 20)
    labels = series_labels(series)
    per_push = div(series, scrape * metrics_rps)

    seconds = int("LOAD_SECONDS", 600)
    warmup = int("LOAD_WARMUP_SECONDS", 60)
    started = now()
    measure_from = started + warmup * 1000
    deadline = measure_from + seconds * 1000
    ctx = Map.merge(ctx, %{measure_from: measure_from, deadline: deadline})

    IO.puts(
      "load: #{series} series every #{scrape}s in #{metrics_rps} pushes/s (#{per_push} samples each), " <>
        "#{int("LOAD_LOG_LINES", 3400)} log lines/s in #{int("LOAD_LOG_RPS", 40)} pushes/s, " <>
        "#{int("LOAD_SPANS", 1000)} spans/s in #{int("LOAD_TRACE_RPS", 10)} exports/s; " <>
        "warmup #{warmup}s, measured #{seconds}s"
    )

    tasks = [
      Task.async(fn -> open_loop(ctx, :metrics, metrics_rps, fn n -> metrics_body(labels, n, per_push) end) end),
      Task.async(fn ->
        lines = max(div(int("LOAD_LOG_LINES", 3400), int("LOAD_LOG_RPS", 40)), 1)
        open_loop(ctx, :logs, int("LOAD_LOG_RPS", 40), fn n -> logs_body(n, lines) end)
      end),
      Task.async(fn ->
        spans = max(div(int("LOAD_SPANS", 1000), int("LOAD_TRACE_RPS", 10)), 1)
        open_loop(ctx, :traces, int("LOAD_TRACE_RPS", 10), fn n -> traces_body(n, spans) end)
      end),
      Task.async(fn -> query_loop(ctx, int("LOAD_QUERY_INTERVAL_SECONDS", 30) * 1000) end),
      Task.async(fn -> sample_loop(ctx, []) end)
    ]

    wait_until(measure_from)
    s3_before = LatencyStore.stats(store)
    inventory_before = LatencyStore.inventory(store)
    superseded_before = LatencyStore.superseded(store)
    [_, _, _, _, sampler] = tasks
    Task.await_many(Enum.take(tasks, 4), :infinity)
    s3_after = LatencyStore.stats(store)
    inventory_after = LatencyStore.inventory(store)
    superseded_after = LatencyStore.superseded(store)
    samples = Task.await(sampler, :infinity)
    final_metrics = scrape_metrics(url)

    superseded = Map.new(superseded_after, fn {k, v} -> {k, (v - superseded_before[k]) / seconds} end)
    report = report(ctx, seconds, s3_before, s3_after, inventory_before, inventory_after, superseded, samples, final_metrics)
    IO.puts(report.text)

    if path = System.get_env("LOAD_REPORT"),
      do: File.write!(path, JSON.encode!(report.json))
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp wait_until(at) do
    wait = at - now()
    if wait > 0, do: Process.sleep(wait)
  end

  defp wait_ready(_url, 0), do: raise("Pulse did not become ready")

  defp wait_ready(url, tries) do
    case Req.get(url <> "/healthz", retry: false, finch: [name: LoadFinch]) do
      {:ok, %{status: 200}} -> :ok
      _ -> Process.sleep(1000) && wait_ready(url, tries - 1)
    end
  end

  defp auth_headers(tenant) do
    [{"authorization", "Bearer " <> env("LOAD_TOKEN", "load-token")}, {"x-scope-orgid", tenant}]
  end

  # ---- traffic ----------------------------------------------------------------

  # Fixed arrival rate per signal, like many collectors pushing independently.
  # Each push retries 429/503 with exponential backoff, as loki.write, remote
  # write and the OTLP exporter do.
  defp open_loop(ctx, signal, rps, body_fun) do
    interval = 1000 / rps
    start = now()

    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn n -> {n, start + round(n * interval)} end)
    |> Stream.take_while(fn {_n, at} -> at < ctx.deadline end)
    |> Enum.each(fn {n, at} ->
      wait_until(at)

      if :ets.lookup_element(ctx.inflight, signal, 2) < 4000 do
        :ets.update_counter(ctx.inflight, signal, 1)
        # Build the body here: a closure over `body_fun` would copy the series
        # label table into every push process.
        request = body_fun.(n)

        spawn(fn ->
          deliver(ctx, signal, request, 500, 5)
          :ets.update_counter(ctx.inflight, signal, -1)
        end)
      else
        :ets.insert(ctx.results, {signal, :client_dropped, now()})
      end
    end)

    drain(ctx, signal)
  end

  defp drain(ctx, signal) do
    if :ets.lookup_element(ctx.inflight, signal, 2) > 0 and now() < ctx.deadline + 60_000 do
      Process.sleep(100)
      drain(ctx, signal)
    end
  end

  defp deliver(ctx, signal, _body, _backoff, 0), do: :ets.insert(ctx.results, {signal, :dropped, now()})

  defp deliver(ctx, signal, {path, headers, body}, backoff, tries) do
    started = now()

    status =
      case Req.post(ctx.url <> path,
             body: body,
             headers: headers ++ ctx.headers,
             retry: false,
             finch: [name: LoadFinch],
             receive_timeout: 120_000
           ) do
        {:ok, response} -> response.status
        {:error, _} -> :transport_error
      end

    :ets.insert(ctx.results, {signal, :attempt, started, status, now() - started})

    if status in [429, 503, :transport_error] do
      Process.sleep(backoff)
      deliver(ctx, signal, {path, headers, body}, backoff * 2, tries - 1)
    end
  end

  # 400 metric names x 1,000 targets, with Kubernetes-style target labels.
  defp series_labels(series) do
    for i <- 0..(series - 1) do
      name = rem(i, 400)
      target = div(i, 400)

      [
        {"__name__", "tuist_metric_#{name}"},
        {"cluster", "tuist-production"},
        {"instance", "10.0.#{div(target, 250)}.#{rem(target, 250)}:9090"},
        {"job", "job-#{rem(target, 40)}"},
        {"namespace", "ns-#{rem(target, 12)}"},
        {"pod", "pod-#{target}"}
      ]
      |> Enum.map_join("", fn {n, v} -> field(1, field(1, n) <> field(2, v)) end)
    end
    |> List.to_tuple()
  end

  defp metrics_body(labels, n, per_push) do
    total = tuple_size(labels)
    ts = System.system_time(:millisecond)
    first = rem(n * per_push, total)

    series =
      for offset <- 0..(per_push - 1) do
        i = rem(first + offset, total)
        value = (n * 7 + i) * 1.0
        field(1, elem(labels, i) <> field(2, tag(1, 1) <> <<value::little-float-64>> <> tag(2, 0) <> varint(ts)))
      end

    {:ok, body} = :snappyer.compress(IO.iodata_to_binary(series))

    {"/api/v1/write", [
       {"content-type", "application/x-protobuf"},
       {"content-encoding", "snappy"},
       {"x-prometheus-remote-write-version", "0.1.0"}
     ], body}
  end

  @services ~w(tuist-server tuist-worker kura-cache kura-proxy ingress-nginx postgresql cilium-agent alloy pulse
    tuist-runner kubelet coredns)
  @levels ~w(info info info info info debug warn error)

  # About 170-byte lines (2.06 GB/h over 12.2M lines/h) across a few streams.
  defp logs_body(n, lines) do
    ts = System.system_time(:nanosecond)
    pod = rem(n, 64)

    streams =
      for s <- 0..3 do
        service = Enum.at(@services, rem(n + s * 5, length(@services)))

        labels =
          ~s({cluster="tuist-production", namespace="tuist", container="#{service}", ) <>
            ~s(pod="#{service}-#{pod}", service_name="#{service}", job="tuist/#{service}"})

        entries =
          for i <- 1..div(lines + 3, 4) do
            level = Enum.at(@levels, rem(i + n, length(@levels)))
            t = ts - (lines - i) * 1_000_000 + s

            %Entry{
              timestamp: %Timestamp{seconds: div(t, 1_000_000_000), nanos: rem(t, 1_000_000_000)},
              line:
                "level=#{level} msg=\"handled request\" request_id=#{:erlang.phash2({n, s, i}, 1_000_000_000)} " <>
                  "path=/api/projects/#{rem(i, 500)}/builds method=GET status=#{if level == "error", do: 500, else: 200} " <>
                  "duration=#{rem(i * 37, 900)}ms account=acme-#{rem(i, 97)}",
              structured_metadata: [%LabelPair{name: "detected_level", value: level}]
            }
          end

        %LokiStream{labels: labels, entries: entries}
      end

    {iodata, _} = PushRequest.encode!(%PushRequest{streams: streams})
    {:ok, body} = :snappyer.compress(IO.iodata_to_binary(iodata))
    {"/loki/api/v1/push", [{"content-type", "application/x-protobuf"}], body}
  end

  @routes ~w(/api/cache/cas /api/cache/keyvalue /v1/cache/artifact /api/projects/:id/builds /api/runs /up /metrics)

  # Traces of ten spans: one server root and nine children.
  defp traces_body(n, spans) do
    ts = System.system_time(:nanosecond)

    by_service =
      for t <- 0..(div(spans + 9, 10) - 1), s <- 0..9, reduce: %{} do
        acc ->
          service = Enum.at(@services, rem(n + t, 4))
          trace_id = hex(:erlang.phash2({n, t}, 1 <<< 32), 32)
          span_id = hex(:erlang.phash2({n, t, s}, 1 <<< 32) + 1, 16)
          parent = if s == 0, do: nil, else: hex(:erlang.phash2({n, t, 0}, 1 <<< 32) + 1, 16)
          route = Enum.at(@routes, rem(n * 3 + t, length(@routes)))
          start = ts - 50_000_000 + s * 1_000_000
          status = if rem(n + t, 50) == 0, do: 2, else: 0

          span =
            %{
              "traceId" => trace_id,
              "spanId" => span_id,
              "name" => if(s == 0, do: "GET " <> route, else: "db.query #{s}"),
              "kind" => if(s == 0, do: 2, else: 3),
              "startTimeUnixNano" => Integer.to_string(start),
              "endTimeUnixNano" => Integer.to_string(start + 1_000_000 + rem(n * 7919 + s, 40_000_000)),
              "attributes" => [
                %{"key" => "http.route", "value" => %{"stringValue" => route}},
                %{"key" => "http.request.method", "value" => %{"stringValue" => "GET"}},
                %{"key" => "http.response.status_code", "value" => %{"intValue" => if(status == 2, do: "500", else: "200")}},
                %{"key" => "db.system", "value" => %{"stringValue" => "postgresql"}}
              ],
              "status" => %{"code" => status}
            }
            |> then(fn span -> if parent, do: Map.put(span, "parentSpanId", parent), else: span end)

          Map.update(acc, service, [span], &[span | &1])
      end

    resource_spans =
      for {service, spans} <- by_service do
        %{
          "resource" => %{
            "attributes" => [
              %{"key" => "service.name", "value" => %{"stringValue" => service}},
              %{"key" => "service.namespace", "value" => %{"stringValue" => if(String.starts_with?(service, "kura"), do: "kura", else: "tuist")}},
              %{"key" => "deployment.environment", "value" => %{"stringValue" => "production"}}
            ]
          },
          "scopeSpans" => [%{"scope" => %{"name" => "opentelemetry_phoenix"}, "spans" => spans}]
        }
      end

    {"/v1/traces", [{"content-type", "application/json"}], JSON.encode!(%{"resourceSpans" => resource_spans})}
  end

  defp hex(value, width), do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")

  # ---- dashboard queries ------------------------------------------------------

  # Panels shaped like Tuist's dashboards, refreshed every interval. Range
  # panels end on a multiple of their step, as Grafana aligns them
  # (LOAD_ALIGN_QUERIES=false sends the raw time instead).
  defp queries(now_s) do
    now_s = if env("LOAD_ALIGN_QUERIES", "true") == "true", do: now_s - rem(now_s, 60), else: now_s
    hour = now_s - 3600

    [
      {:promql_rate_by_job, "/api/v1/query_range",
       %{query: "sum by (job) (rate(tuist_metric_1[5m]))", start: hour, end: now_s, step: 60}},
      {:promql_topk_instance, "/api/v1/query",
       %{query: "topk(10, sum by (instance) (rate(tuist_metric_2[5m])))", time: now_s}},
      {:promql_count, "/api/v1/query", %{query: "count(tuist_metric_3)", time: now_s}},
      {:logql_volume_by_level, "/loki/api/v1/query_range",
       %{query: ~s|sum by (detected_level) (count_over_time({namespace="tuist"}[1m]))|, start: hour * 1_000_000_000, end: now_s * 1_000_000_000, step: 60}},
      {:logql_errors, "/loki/api/v1/query_range",
       %{query: ~s|{service_name="tuist-server"} \|= "level=error"|, start: (now_s - 900) * 1_000_000_000, end: now_s * 1_000_000_000, limit: 100}},
      {:tempo_kura_search, "/api/search",
       %{q: ~s|{resource.service.namespace="kura" && span.http.route=~"/api/cache.*"}|, start: now_s - 900, end: now_s, limit: 20}}
    ]
  end

  defp query_loop(ctx, interval) do
    if now() < ctx.deadline do
      at = now()

      # Two panels at a time: the default interactive query admission is a
      # few slots per node, and this measures query cost, not admission.
      queries(System.system_time(:second))
      |> Task.async_stream(
        fn {name, path, params} ->
          started = now()

          status =
            case Req.get(ctx.url <> path, params: params, headers: ctx.headers, retry: false, finch: [name: LoadFinch], receive_timeout: 120_000) do
              {:ok, %{status: status} = response} when status >= 400 -> failure(status, response.body)
              {:ok, response} -> response.status
              {:error, _} -> :transport_error
            end

          :ets.insert(ctx.results, {{:query, name}, :attempt, started, status, now() - started})
        end,
        max_concurrency: int("LOAD_QUERY_CONCURRENCY", 2),
        timeout: :infinity
      )
      |> Stream.run()

      wait_until(at + interval)
      query_loop(ctx, interval)
    end
  end

  # A failed panel is reported with the query limit it hit, such as
  # "422 max_scan_bytes", so the report shows which budget binds.
  defp failure(status, body) do
    text = if is_binary(body), do: body, else: JSON.encode!(body)

    case Regex.run(~r/(max_[a-z_]+|metadata|memory|timeout)/, text) do
      [_, limit] -> "#{status} #{limit}"
      _ -> status
    end
  end

  # ---- sampling and report ----------------------------------------------------

  defp sample_loop(ctx, acc) do
    if now() < ctx.deadline do
      sample = scrape_metrics(ctx.url)
      Process.sleep(5000)
      sample_loop(ctx, if(now() >= ctx.measure_from, do: [sample | acc], else: acc))
    else
      Enum.reverse(acc)
    end
  end

  defp scrape_metrics(url) do
    case Req.get(url <> "/metrics", retry: false, finch: [name: LoadFinch], receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> parse_metrics(body)
      _ -> %{}
    end
  end

  defp parse_metrics(body) do
    for line <- String.split(body, "\n"), line != "", not String.starts_with?(line, "#"), into: %{} do
      case Regex.run(~r/^(\S+?)(\{.*\})? (\S+)$/, line) do
        [_, name, labels, value] -> {name <> labels, parse_number(value)}
        [_, name, value] -> {name, parse_number(value)}
        _ -> {line, nil}
      end
    end
  end

  defp parse_number(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> nil
    end
  end

  defp pct([], _q), do: nil

  defp pct(values, q) do
    sorted = Enum.sort(values)
    Enum.at(sorted, min(length(sorted) - 1, trunc(q * length(sorted))))
  end

  defp report(ctx, seconds, s3_before, s3_after, inv_before, inv_after, superseded, samples, final) do
    rows = :ets.tab2list(ctx.results)
    in_window = fn at -> at >= ctx.measure_from and at < ctx.deadline end

    signals =
      for signal <- [:metrics, :logs, :traces], into: %{} do
        attempts = for {^signal, :attempt, at, status, ms} <- rows, in_window.(at), do: {status, ms}
        ok = for {status, ms} <- attempts, is_integer(status) and status < 300, do: ms
        statuses = attempts |> Enum.frequencies_by(&elem(&1, 0)) |> Map.new(fn {k, v} -> {to_string(k), v} end)
        dropped = Enum.count(rows, &match?({^signal, kind, _} when kind in [:dropped, :client_dropped], &1))

        {signal,
         %{
           accepted_per_s: Float.round(length(ok) / seconds, 2),
           p50_ms: pct(ok, 0.5),
           p90_ms: pct(ok, 0.9),
           p99_ms: pct(ok, 0.99),
           max_ms: Enum.max(ok, fn -> nil end),
           statuses: statuses,
           dropped: dropped
         }}
      end

    queries =
      rows
      |> Enum.flat_map(fn
        {{:query, name}, :attempt, at, status, ms} -> if in_window.(at), do: [{name, status, ms}], else: []
        _ -> []
      end)
      |> Enum.group_by(&elem(&1, 0))
      |> Map.new(fn {name, list} ->
        ok = for {_, 200, ms} <- list, do: ms
        statuses = list |> Enum.frequencies_by(&elem(&1, 1)) |> Map.new(fn {k, v} -> {to_string(k), v} end)
        {name, %{p50_ms: pct(ok, 0.5), p99_ms: pct(ok, 0.99), statuses: statuses}}
      end)

    delta =
      Map.new(s3_after, fn {key, {count, bytes}} ->
        {before_count, before_bytes} = Map.get(s3_before, key, {0, 0})
        {key, {count - before_count, bytes - before_bytes}}
      end)

    rate = fn filter -> (delta |> Enum.filter(filter) |> Enum.map(fn {_, {c, _}} -> c end) |> Enum.sum()) / seconds end
    class_a = rate.(fn {{class, _, _, _}, _} -> class == "A" end)
    class_b = rate.(fn {{class, _, _, _}, _} -> class == "B" end)

    by_request =
      delta
      |> Enum.group_by(fn {{class, purpose, method, status}, _} -> "#{class} #{method} #{purpose} #{status}" end, fn {_, {c, _}} -> c end)
      |> Map.new(fn {k, counts} -> {k, Float.round(Enum.sum(counts) / seconds, 3)} end)

    stored = fn inv -> inv |> Map.values() |> Enum.map(&elem(&1, 1)) |> Enum.sum() end
    growth = (stored.(inv_after) - stored.(inv_before)) / seconds
    gib_month = growth * @month_seconds / 1_073_741_824

    # Live segment bytes added per second by signal, net of compaction.
    segment_growth =
      for signal <- ~w(logs metrics traces), into: %{} do
        key = "segment:" <> signal
        bytes = fn inv -> inv |> Map.get(key, {0, 0}) |> elem(1) end
        {signal, round((bytes.(inv_after) - bytes.(inv_before)) / seconds)}
      end

    # Deleted and overwritten bytes stay billable for a 7-day soft-delete window.
    soft_delete_gib = (superseded.deleted + superseded.overwritten) * 7 * 86_400 / 1_073_741_824

    rss = for sample <- samples, value = sample[~s|pulse_memory_bytes{kind="rss"}|], is_number(value), do: value
    beam = for sample <- samples, value = sample["pulse_vm_memory_bytes"], is_number(value), do: value
    peak = fn name -> samples |> Enum.map(&(&1[name] || 0)) |> Enum.max(fn -> 0 end) end

    accepted = Enum.sum(for {_, row} <- signals, do: row.accepted_per_s)

    cost = %{
      class_a_per_s: Float.round(class_a, 3),
      class_b_per_s: Float.round(class_b, 3),
      class_a_per_ingest_request: if(accepted > 0, do: Float.round(class_a / accepted, 3)),
      class_a_month_usd: Float.round(class_a * @month_seconds * @class_a, 2),
      class_b_month_usd: Float.round(class_b * @month_seconds * @class_b, 2),
      stored_growth_bytes_per_s: round(growth),
      segment_growth_bytes_per_s: segment_growth,
      deleted_bytes_per_s: round(superseded.deleted),
      overwritten_bytes_per_s: round(superseded.overwritten),
      soft_delete_7d_gib: Float.round(soft_delete_gib, 1),
      soft_delete_7d_month_usd: Float.round(soft_delete_gib * @storage_gib_month, 2),
      storage_added_per_month_gib: Float.round(gib_month, 1),
      storage_added_per_month_usd: Float.round(gib_month * @storage_gib_month, 2)
    }

    memory = %{
      rss_p50_mib: rss |> pct(0.5) |> mib(),
      rss_max_mib: rss |> Enum.max(fn -> nil end) |> mib(),
      beam_max_mib: beam |> Enum.max(fn -> nil end) |> mib(),
      ingest_slots_max: peak.("pulse_ingest_inflight_requests"),
      pending_bytes_max_mib: mib(peak.("pulse_ingest_admission_pending_bytes")),
      buffer_input_max_mib: mib(peak.("pulse_ingest_buffer_input_bytes"))
    }

    json = %{
      seconds: seconds,
      signals: signals,
      queries: queries,
      object_requests_per_s: by_request,
      cost: cost,
      memory: memory,
      store_inventory: Map.new(inv_after, fn {k, {n, b}} -> {k, %{objects: n, bytes: b}} end),
      pulse_object_requests_total:
        final |> Enum.filter(fn {k, _} -> String.starts_with?(k, "pulse_object_requests_total") end) |> Map.new()
    }

    text =
      [
        "",
        "== production load: #{seconds} s measured ==",
        for {signal, row} <- signals do
          "  #{signal}: #{row.accepted_per_s} acks/s p50 #{row.p50_ms} ms p90 #{row.p90_ms} ms p99 #{row.p99_ms} ms " <>
            "max #{row.max_ms} ms statuses #{inspect(row.statuses)} dropped #{row.dropped}"
        end,
        "  queries:",
        for {name, row} <- Enum.sort(queries) do
          "    #{name}: p50 #{row.p50_ms} ms p99 #{row.p99_ms} ms statuses #{inspect(row.statuses)}"
        end,
        "  object requests per second (class method purpose status):",
        for({key, value} <- Enum.sort(by_request), value > 0, do: "    #{key}: #{value}"),
        "  Class A #{cost.class_a_per_s}/s (#{cost.class_a_per_ingest_request} per ingest request), " <>
          "Class B #{cost.class_b_per_s}/s",
        "  projected monthly: Class A $#{cost.class_a_month_usd}, Class B $#{cost.class_b_month_usd}, " <>
          "storage +#{cost.storage_added_per_month_gib} GiB/month (+$#{cost.storage_added_per_month_usd}/month per month retained)",
        "  stored bytes/s #{cost.stored_growth_bytes_per_s} (live segments by signal #{inspect(cost.segment_growth_bytes_per_s)}); " <>
          "deleted #{cost.deleted_bytes_per_s} B/s, overwritten #{cost.overwritten_bytes_per_s} B/s -> " <>
          "7-day soft delete holds #{cost.soft_delete_7d_gib} GiB ($#{cost.soft_delete_7d_month_usd}/month)",
        "  memory: RSS p50 #{memory.rss_p50_mib} MiB max #{memory.rss_max_mib} MiB, BEAM max #{memory.beam_max_mib} MiB, peak ingest slots #{memory.ingest_slots_max}, pending #{memory.pending_bytes_max_mib} MiB, buffered input #{memory.buffer_input_max_mib} MiB",
        "  store inventory: #{inspect(json.store_inventory)}"
      ]
      |> List.flatten()
      |> Enum.join("\n")

    %{text: text, json: json}
  end

  defp mib(nil), do: nil
  defp mib(bytes), do: round(bytes / 1_048_576)

  defp varint(v) when v < 128, do: <<v>>
  defp varint(v), do: <<(v &&& 0x7F) ||| 0x80>> <> varint(v >>> 7)
  defp tag(field, wire), do: varint(field <<< 3 ||| wire)
  defp field(number, bytes), do: tag(number, 2) <> varint(byte_size(bytes)) <> bytes
end

Pulse.ProductionLoad.run()
