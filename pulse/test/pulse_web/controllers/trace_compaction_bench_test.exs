defmodule PulseWeb.TraceCompactionBenchTest do
  # Tuist's trace panels over canary-shaped history, before and after trace
  # compaction, at Tigris latency (GET 140-190 ms, PUT 220-350 ms):
  #
  #     mix test --include query_bench test/pulse_web/controllers/trace_compaction_bench_test.exs
  #
  # History is written without latency: TRACE_BENCH_HOURS (6) hours of
  # TRACE_BENCH_SEGMENTS_PER_HOUR (8300, canary's measured candidates per
  # hour) segments of Tuist-shaped spans, newest ending a minute ago. Every
  # panel is then timed over 1 h and 6 h on the uncompacted history (what
  # 1.34.1 keeps) and again once compaction has merged it. TRACE_BENCH_REPORT
  # writes the rows and request counts as JSON.
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.Retention
  alias Pulse.Storage.S3.TraceCompactor
  alias Pulse.Test.LatencyStore
  alias Pulse.Test.RuntimePlug
  alias Pulse.Test.TuistTraceFixture, as: Fixture
  alias Pulse.Traces.TempoSearch

  @moduletag :query_bench
  @moduletag timeout: :infinity

  # Canary's spellings of the two panels whose fixture variants differ.
  @canary %{
    kura_cache:
      ~s[{ resource.service.namespace = "kura" && resource.service.name =~ "kura-.*" && span.http.route =~ "/api/cache.*|/api/metro/cache.*|/v1/cache.*" } with (most_recent=true)],
    registry:
      ~s[{ resource.service.namespace = "tuist" && resource.service.name = "tuist-registry" && resource.deployment.environment =~ "production" } with (most_recent=true)]
  }

  @tag :tmp_dir
  test "trace panels before and after compaction", %{tmp_dir: dir} do
    hours = String.to_integer(System.get_env("TRACE_BENCH_HOURS", "6"))
    per_hour = String.to_integer(System.get_env("TRACE_BENCH_SEGMENTS_PER_HOUR", "8300"))
    store = LatencyStore.new(dir: dir, get_ms: {0, 0}, put_ms: {0, 0}, list_ms: {0, 0}, delete_ms: {0, 0})
    object_server = start_supervised!({Bandit, plug: {LatencyStore, store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, object_port}} = ThousandIsland.listener_info(object_server)
    tenant = "tuist-trace-bench-#{System.unique_integer([:positive])}"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, "bench"), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => digest})
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
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
    start_supervised!(ManifestSupervision)
    Runtime.share()

    server =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0},
        id: :trace_bench_api
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    url = "http://127.0.0.1:#{port}"
    now = System.system_time(:second)
    newest = (now - 60) * 1_000_000_000
    total = hours * per_hour
    spacing = div(3_600_000_000_000, per_hour)

    {micros, _} =
      :timer.tc(fn ->
        1..total
        |> Pulse.Runtime.Task.async_stream(
          fn batch ->
            spans = segment_spans(newest - (total - batch) * spacing, batch)
            :ok = S3.append(:traces, tenant, spans)
          end,
          max_concurrency: 16,
          timeout: :infinity,
          ordered: false
        )
        |> Stream.run()
      end)

    IO.puts("\nwrote #{total} segments in #{div(micros, 1_000_000)} s")
    # 1.34.1 read search context from every retained source (horizon 0).
    # TRACE_BENCH_BEFORE=false measures only the compacted history.
    {baseline, before} =
      if System.get_env("TRACE_BENCH_BEFORE", "true") == "true" do
        IO.puts("uncompacted, context from all retained sources:")
        Runtime.put_env(:pulse, S3, Map.put(config, :trace_context_horizon_ms, 0))
        baseline = measure(store, url, tenant, now)
        Runtime.put_env(:pulse, S3, config)
        IO.puts("uncompacted, one-hour context horizon:")
        {baseline, measure(store, url, tenant, now)}
      else
        {[], []}
      end

    LatencyStore.set_latency(store, get_ms: {0, 0}, put_ms: {0, 0}, list_ms: {0, 0}, delete_ms: {0, 0})
    stats = LatencyStore.stats(store)
    {micros, passes} = :timer.tc(fn -> compact(tenant, config, 0) end)
    requests = delta(stats, LatencyStore.stats(store))

    {:ok, root, _} = Retention.load(tenant, "traces", config)
    outputs = JournalManifest.referenced(root)

    IO.puts(
      "compacted in #{passes} merges, #{div(micros, 1_000_000)} s; requests #{inspect(requests)}; " <>
        "active trace segments #{inspect(outputs)}"
    )

    IO.puts("compacted:")
    after_rows = measure(store, url, tenant, now)

    if path = System.get_env("TRACE_BENCH_REPORT"),
      do:
        File.write!(
          path,
          Pulse.JSON.encode!(%{
            segments: total,
            merges: passes,
            compaction_requests: requests,
            baseline: baseline,
            before: before,
            after: after_rows
          })
        )

    slow = for row <- after_rows, row.status != 200 or row.ms > 3000, do: row
    assert slow == []
  end

  # As the worker does pass after pass: an empty pass only rotates the
  # bounded candidate cursor, so stop after many empty passes in a row.
  defp compact(tenant, config, passes, idle \\ 0)
  defp compact(_tenant, _config, passes, 64), do: passes

  defp compact(tenant, config, passes, idle) do
    case TraceCompactor.compact(tenant, config, settle_ms: 0) do
      {:ok, %{merged: merged}} when merged > 0 -> compact(tenant, config, passes + 1, 0)
      {:ok, _} -> compact(tenant, config, passes, idle + 1)
    end
  end

  defp measure(store, url, tenant, now) do
    LatencyStore.set_latency(store, get_ms: {140, 190}, put_ms: {220, 350}, list_ms: {140, 190})
    headers = [{"authorization", "Bearer bench"}, {"x-scope-orgid", tenant}]
    queries = Map.merge(Fixture.queries(), @canary)

    rows =
      for hours <- [1, 6],
          window = %{"start" => now - hours * 3600, "end" => now},
          {name, path, params} <-
            Enum.map(Enum.sort(queries), fn {panel, q} ->
              {"search #{panel}", "/api/search", Map.merge(window, %{"q" => q, "limit" => 20, "spss" => 10})}
            end) ++
              Enum.map(Enum.sort(Fixture.rates()), fn {q, _} ->
                {"metrics #{q}", "/api/metrics/query_range", Map.merge(window, %{"q" => q, "step" => "60s"})}
              end) do
        before = LatencyStore.stats(store)
        started = System.monotonic_time(:millisecond)
        response = Req.get!(url <> path, headers: headers, params: params, receive_timeout: 120_000, retry: false)
        elapsed = System.monotonic_time(:millisecond) - started
        requests = delta(before, LatencyStore.stats(store))
        error = if response.status != 200, do: inspect(response.body) |> String.slice(0, 160)
        %{name: name, hours: hours, status: response.status, ms: elapsed, gets: Map.get(requests, "B", 0), error: error}
      end

    IO.puts(Enum.map_join(rows, "\n", &"#{&1.hours}h #{&1.status} #{&1.ms} ms #{&1.gets} GETs  #{&1.name} #{&1.error}"))
    rows
  end

  # Requests by billing class between two store snapshots.
  defp delta(before, later) do
    later
    |> Enum.map(fn {{class, _, _, _} = key, {count, _}} -> {class, count - elem(Map.get(before, key, {0, 0}), 0)} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {class, counts} -> {class, Enum.sum(counts)} end)
  end

  # One flush: the fixture's traces with trace IDs unique to the batch.
  defp segment_spans(start, batch) do
    for request <- Fixture.requests(start) do
      request =
        update_in(
          request,
          ["resourceSpans", Access.all(), "scopeSpans", Access.all(), "spans", Access.all(), "traceId"],
          &renumber(&1, batch)
        )

      {:ok, spans, 0} = Traces.decode(request)
      spans
    end
    |> List.flatten()
  end

  defp renumber(id, batch) do
    Integer.to_string(batch * 1000 + String.to_integer(id, 16), 16)
    |> String.downcase()
    |> String.pad_leading(32, "0")
  end
end
