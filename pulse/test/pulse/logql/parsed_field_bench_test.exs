defmodule Pulse.LogQL.ParsedFieldBenchTest do
  # Tuist's parsed-field LogQL alerts and cache-usage panels over a
  # canary-shaped (scale 1) or production-shaped (scale 53) log history at
  # Tigris-like GET latency:
  #
  #     mix test --include query_bench test/pulse/logql/parsed_field_bench_test.exs
  #
  # LOGQL_BENCH_SCALE (1), LOGQL_BENCH_HOURS (24), LOGQL_BENCH_REPORT (JSON path).
  # Each settled hour is stored as log compaction leaves it: mixed segments
  # of every stream, up to 100,000 rows each, merged by the log compactor
  # from 25,000-row appends. Queries run before and after
  # log hour finalization groups each settled hour by stream.
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.QueryRunner
  alias Pulse.Record.Log
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.LogCompactor
  alias Pulse.Storage.S3.LogTiers
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.GrafanaCorpus
  alias Pulse.Test.LatencyStore
  alias Pulse.Test.RuntimePlug

  @moduletag :query_bench
  @moduletag timeout: :infinity
  @hour 3_600_000_000_000

  # Lines per second at canary (about 52/s in all, as measured on Tuist's
  # canary); production carries about 53 times as many bytes.
  @streams [
    {1.4, :rum},
    {0.6, :web_event},
    {9.0, :docker},
    {3.0, :cache_usage},
    {20.0, :server},
    {8.0, :kura},
    {5.0, :agent},
    {5.0, :nginx}
  ]

  @alerts ~w(l0009 l0010 l0011 l0023 l0024 l0028 l0029 l0031 l0035 l0038 l0039
             l0022 l0026 l0027 l0032 l0033 l0034 l0036 l0037 l0040)
  @panels ~w(l0007 l0008)

  @tag :tmp_dir
  test "parsed-field alerts and panels at Tigris latency", %{tmp_dir: dir} do
    scale = "LOGQL_BENCH_SCALE" |> System.get_env("1") |> String.to_integer()
    hours = "LOGQL_BENCH_HOURS" |> System.get_env("24") |> String.to_integer()

    store = LatencyStore.new(dir: dir, get_ms: {140, 190}, put_ms: {0, 0}, list_ms: {0, 0}, delete_ms: {0, 0})
    object_server = start_supervised!({Bandit, plug: {LatencyStore, store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, object_port}} = ThousandIsland.listener_info(object_server)
    tenant = "tuist-logbench-#{System.unique_integer([:positive])}"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, "bench"), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => digest})
    Runtime.put_env(:pulse, Storage, adapter: S3)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{object_port}",
      region: "us-east-1",
      access_key_id: tenant,
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      query_prefetch: 4
    }

    Runtime.put_env(:pulse, S3, config)
    # Production query defaults, with room to time queries past 10 s.
    Runtime.put_env(:pulse, QueryRunner, timeout_ms: 120_000, max_heap_mb: 128)
    start_supervised!(ManifestSupervision)
    Runtime.share()

    server =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0},
        id: :logbench_api
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    ctx = %{url: "http://127.0.0.1:#{port}", tenant: tenant, store: store, config: config}
    now = div(System.os_time(:nanosecond), @hour) * @hour
    first = now - hours * @hour

    {micros, rows} = :timer.tc(fn -> load(ctx, first, hours, scale) end)
    IO.puts("\nscale #{scale}: #{rows} rows over #{hours} h written in #{div(micros, 1_000_000)} s")

    before = run_queries(ctx, now)
    finalized = finalize(ctx, first, hours)
    after_rows = if finalized, do: run_queries(ctx, now), else: []
    report = %{scale: scale, hours: hours, rows: rows, before: before, after: after_rows, finalized: finalized}
    IO.puts(format(before, "before") <> "\n" <> format(after_rows, "after"))
    if path = System.get_env("LOGQL_BENCH_REPORT"), do: File.write!(path, Pulse.JSON.encode!(report))
  end

  # Hour finalization, when this build has it.
  defp finalize(ctx, first, hours) do
    if Code.ensure_loaded?(LogTiers) and function_exported?(LogTiers, :finalize_hour, 4) do
      started = System.monotonic_time(:millisecond)
      before = LatencyStore.stats(ctx.store)

      results =
        for h <- 0..(hours - 1),
            do: {:ok, _} = LogTiers.finalize_hour(ctx.tenant, first + h * @hour, ctx.config, [])

      ms = System.monotonic_time(:millisecond) - started
      requests = delta(before, LatencyStore.stats(ctx.store))
      outputs = Enum.sum_by(results, fn {:ok, r} -> Map.get(r, :outputs, 0) end)
      IO.puts("finalized #{hours} h in #{ms} ms: #{outputs} outputs, requests #{inspect(requests)}")
      %{ms: ms, outputs: outputs, requests: requests}
    end
  end

  defp load(ctx, first, hours, scale) do
    rows = Enum.sum_by(0..(hours - 1), &load_hour(ctx, first + &1 * @hour, scale))
    compact(ctx)
    rows
  end

  # Mixed segments of up to 25,000 rows (an append holds at most 16 MiB of
  # JSON), each a time slice of the hour; compaction merges them.
  defp load_hour(ctx, start, scale) do
    per_hour = Enum.map(@streams, fn {rate, kind} -> {round(rate * 3600 * scale), kind} end)
    total = Enum.sum_by(per_hour, &elem(&1, 0))
    chunks = max(div(total + 24_999, 25_000), 1)

    for c <- 0..(chunks - 1) do
      records =
        for {count, kind} <- per_hour,
            i <- c..(count - 1)//chunks,
            do: record(kind, start + div(i * @hour, count) + 1, i)

      :ok = S3.append(:logs, ctx.tenant, records)
    end

    total
  end

  # Log compaction as it runs in production, until nothing is left to merge.
  defp compact(ctx) do
    case LogCompactor.compact(ctx.tenant, ctx.config, settle_ms: 0) do
      {:ok, %{merged: n}} when n > 0 -> compact(ctx)
      {:ok, _} -> :ok
      {:error, :payload_too_large} -> :ok
    end
  end

  @surfaces ~w(docs marketing auth dashboard_authenticated)
  @accounts ~w(tuist acme globex initech umbrella hooli)

  defp record(:rum, ts, i) do
    env = if rem(i, 10) < 7, do: "prod", else: "staging"
    surface = Enum.at(@surfaces, rem(i, 4))
    dedup = if rem(i, 9) == 0, do: "duplicate", else: "unique"
    quality = if rem(i, 13) == 0, do: "ineligible", else: "eligible"

    page =
      if rem(i, 17) == 0, do: "https://tuist.dev/users/log_in", else: "https://tuist.dev/en/#{surface}/p#{rem(i, 50)}"

    body =
      "level=info kind=measurement type=web-vitals app_environment=#{env} session_id=s#{rem(i, 4000)} " <>
        "page_url=#{page} lcp=#{800 + rem(i * 37, 12_000)} cls=0.0#{rem(i, 9)} inp=#{rem(i * 7, 400)} " <>
        "context_rum_schema=1 context_rum_quality=#{quality} context_rum_deduplication=#{dedup} " <>
        "context_rum_surface=#{surface} context_rum_ray_id=#{if rem(i, 3) == 0, do: "", else: id()}"

    log(ts, "tuist-web", %{"service_name" => "tuist-web", "cluster" => "tuist-canary", "namespace" => "tuist"}, body)
  end

  defp record(:web_event, ts, i) do
    body = "level=info kind=event type=navigation app_environment=prod session_id=s#{rem(i, 4000)} event_id=#{id()}"
    log(ts, "tuist-web", %{"service_name" => "tuist-web", "cluster" => "tuist-canary", "namespace" => "tuist"}, body)
  end

  defp record(:docker, ts, i) do
    body = "#{id()} level=info msg=\"GET /api/cache/cas/#{id()}\" status=200 duration_ms=#{rem(i, 90)}"
    log(ts, nil, %{"app" => "docker", "instance" => "kura-#{rem(i, 4)}"}, body)
  end

  defp record(:cache_usage, ts, i) do
    type = if rem(i, 3) == 0, do: "module", else: "cas"

    body =
      "#{id()} event=cache_usage account_handle=#{Enum.at(@accounts, rem(i, 6))} cache_type=#{type} " <>
        "action=download count=#{rem(i, 20)} window_start=1762336800 window_end=1762336860"

    log(ts, nil, %{"app" => "docker", "instance" => "kura-#{rem(i, 4)}"}, body)
  end

  defp record(:server, ts, i) do
    body =
      ~s({"level":"info","msg":"Sent 200 in #{rem(i, 300)}ms","request_id":"#{id()}","auth_account_handle":"a#{rem(i, 50)}"})

    labels = %{"service_name" => "tuist", "cluster" => "tuist-canary", "namespace" => "tuist", "container" => "server"}
    log(ts, "tuist", Map.put(labels, "pod", "server-#{rem(i, 3)}"), body)
  end

  defp record(:kura, ts, i) do
    body = ~s({"level":"INFO","msg":"served","kura.tenant_id":"t#{rem(i, 20)}","bytes":#{i * 13},"trace":"#{id()}"})
    labels = %{"service_name" => "kura", "cluster" => "tuist-canary", "namespace" => "kura", "container" => "kura"}
    log(ts, "kura", Map.put(labels, "pod", "kura-#{rem(i, 4)}"), body)
  end

  defp record(:agent, ts, i) do
    body =
      ~s({"msg":"cache volume operation","operation":"acquire","result":"success","use":"u#{rem(i, 30)}","id":"#{id()}"})

    labels = %{"service_name" => "agent", "cluster" => "tuist-canary", "namespace" => "tuist-runners"}
    log(ts, "agent", labels, body)
  end

  defp record(:nginx, ts, i) do
    body =
      ~s(10.0.0.#{rem(i, 250)} - - [05/Nov/2026:10:00:00 +0000] "GET /v1/#{id()} HTTP/1.1" 200 #{rem(i, 9000)} "-" "curl")

    labels = %{"service_name" => "kura-eu-ingress-nginx", "cluster" => "tuist-canary", "namespace" => "kura"}
    log(ts, "kura-eu-ingress-nginx", labels, body)
  end

  # Random request IDs make lines compress about as well as real ones.
  defp id, do: Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)

  defp log(ts, service, resource, body), do: %Log{timestamp_ns: ts, service: service, resource: resource, body: body}

  defp run_queries(ctx, now) do
    queries = GrafanaCorpus.fixture()["queries"] |> Map.new(&{&1["id"], &1})

    alerts =
      for id <- @alerts do
        q = Map.fetch!(queries, id)
        {id, "#{q["alert_window_s"]}s", q["expr"]}
      end

    panels =
      for id <- @panels, range <- [3600, 21_600, 86_400] do
        expr = queries |> Map.fetch!(id) |> Map.fetch!("expr")
        macros = GrafanaCorpus.macros(60, range, 15)
        expr = GrafanaCorpus.interpolate(expr, "logql", %{"instance" => %{"value" => "$__all"}}, macros)
        {id, "#{div(range, 3600)}h", expr}
      end

    for {id, window, expr} <- alerts ++ panels do
      before = LatencyStore.stats(ctx.store)
      started = System.monotonic_time(:millisecond)
      params = %{"query" => expr, "time" => Integer.to_string(div(now, 1_000_000_000))}
      headers = [{"authorization", "Bearer bench"}, {"x-scope-orgid", ctx.tenant}]

      response =
        Req.get!(ctx.url <> "/loki/api/v1/query",
          headers: headers,
          params: params,
          receive_timeout: 300_000,
          retry: false
        )

      ms = System.monotonic_time(:millisecond) - started
      requests = delta(before, LatencyStore.stats(ctx.store))
      series = if response.status == 200, do: length(response.body["data"]["result"])
      error = if response.status != 200, do: String.slice(inspect(response.body), 0, 160)

      Map.merge(requests, %{id: id, window: window, status: response.status, ms: ms, series: series, error: error})
    end
  end

  # Segment GETs and bytes, and Class A/B requests, between two snapshots.
  defp delta(before, current) do
    Enum.reduce(current, %{gets: 0, get_bytes: 0, class_a: 0, class_b: 0}, fn {{class, purpose, method, _} = key,
                                                                               {n, bytes}},
                                                                              acc ->
      {n0, b0} = Map.get(before, key, {0, 0})
      {n, bytes} = {n - n0, bytes - b0}

      acc =
        case class do
          "A" -> %{acc | class_a: acc.class_a + n}
          "B" -> %{acc | class_b: acc.class_b + n}
          _ -> acc
        end

      if method == "GET" and String.starts_with?(purpose, "segment"),
        do: %{acc | gets: acc.gets + n, get_bytes: acc.get_bytes + bytes},
        else: acc
    end)
  end

  defp format(rows, label) do
    Enum.map_join(rows, "\n", fn r ->
      "#{label} #{r.id} #{r.window} #{r.status} #{r.ms} ms #{r.gets} GETs #{div(r.get_bytes, 1024)} KiB " <>
        "series=#{inspect(r.series)} #{r.error}"
    end)
  end
end
