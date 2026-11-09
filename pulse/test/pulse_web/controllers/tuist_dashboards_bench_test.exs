defmodule PulseWeb.TuistDashboardsBenchTest do
  # Tuist dashboard TraceQL latency and object GETs at canary-like provider
  # latency: `mix test --include query_bench test/pulse_web/controllers/tuist_dashboards_bench_test.exs`.
  # 48 segments of Tuist-shaped spans, one per 150 s, newest last.
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.LatencyStore
  alias Pulse.Test.RuntimePlug
  alias Pulse.Test.TuistTraceFixture, as: Fixture
  alias Pulse.Traces.TempoSearch

  @moduletag :query_bench
  @moduletag timeout: 600_000
  @segments 48

  @tag :tmp_dir
  test "dashboard queries at 140-190 ms per GET", %{tmp_dir: dir} do
    store = LatencyStore.new(dir: dir, get_ms: {140, 190}, put_ms: {220, 350}, list_ms: {140, 190})
    object_server = start_supervised!({Bandit, plug: {LatencyStore, store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, object_port}} = ThousandIsland.listener_info(object_server)
    tenant = "tuist-bench-#{System.unique_integer([:positive])}"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, "bench"), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => digest})
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    Runtime.put_env(:pulse, Storage, adapter: S3)

    Runtime.put_env(:pulse, S3, %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{object_port}",
      region: "us-east-1",
      access_key_id: tenant,
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      # The production default (PULSE_QUERY_PREFETCH); tests default to 1.
      query_prefetch: 4
    })

    start_supervised!(ManifestSupervision)
    Runtime.share()

    server =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0},
        id: :tuist_bench_api
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    url = "http://127.0.0.1:#{port}"
    headers = [{"authorization", "Bearer bench"}, {"x-scope-orgid", tenant}]
    now = System.system_time(:second)

    for batch <- 1..@segments do
      start = (now - (@segments - batch + 1) * 150) * 1_000_000_000
      resource_spans = start |> Fixture.requests() |> Enum.flat_map(& &1["resourceSpans"]) |> renumber(batch)
      body = %{"resourceSpans" => resource_spans}
      assert Req.post!(url <> "/v1/traces", headers: headers, json: body, receive_timeout: 60_000).status == 200
    end

    window = %{"start" => now - 3 * 3600, "end" => now + 60}

    searches =
      for {panel, query} <- Enum.sort(Fixture.queries()),
          do: {"search #{panel}", "/api/search", Map.merge(window, %{"q" => query, "limit" => 20, "spss" => 3})}

    metrics =
      for {query, _} <- Enum.sort(Fixture.rates()),
          do: {"metrics #{query}", "/api/metrics/query_range", Map.merge(window, %{"q" => query, "step" => "60s"})}

    rows =
      for {name, path, params} <- searches ++ metrics do
        before = gets(store)
        started = System.monotonic_time(:millisecond)
        response = Req.get!(url <> path, headers: headers, params: params, receive_timeout: 120_000)
        elapsed = System.monotonic_time(:millisecond) - started
        %{name: name, status: response.status, ms: elapsed, gets: gets(store) - before}
      end

    report = Enum.map_join(rows, "\n", &"#{&1.status} #{&1.ms} ms #{&1.gets} GETs  #{&1.name}")
    IO.puts("\n#{@segments} segments\n" <> report)
    if path = System.get_env("TUIST_BENCH_REPORT"), do: File.write!(path, Pulse.JSON.encode!(rows))
  end

  defp gets(store) do
    # Every GET request, including free conditional 304s, excluding LIST.
    store
    |> LatencyStore.stats()
    |> Enum.filter(fn {{_class, purpose, method, _status}, _} -> method == "GET" and purpose != "list" end)
    |> Enum.sum_by(fn {_, {n, _}} -> n end)
  end

  # Unique trace IDs per batch; span IDs repeat across traces, as they may.
  defp renumber(resource_spans, batch) do
    update_in(resource_spans, [Access.all(), "scopeSpans", Access.all(), "spans", Access.all(), "traceId"], fn id ->
      Integer.to_string(batch * 1000 + String.to_integer(id, 16), 16)
      |> String.downcase()
      |> String.pad_leading(32, "0")
    end)
  end
end
