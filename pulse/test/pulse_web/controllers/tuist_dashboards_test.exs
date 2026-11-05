defmodule PulseWeb.TuistDashboardsTest do
  # The TraceQL Tuist's Grafana dashboards send, against spans shaped like the
  # tuist server's: exceptions are span events, account errors need `>>`.
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.MCPMessages
  alias Pulse.Test.RuntimePlug
  alias Pulse.Test.TuistTraceFixture, as: Fixture
  alias Pulse.Traces.TempoSearch

  setup do
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

    object_server = start_supervised!({Bandit, plug: {CompactionStore, agent: store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, object_port}} = ThousandIsland.listener_info(object_server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{object_port}",
      region: "us-east-1",
      access_key_id: "tuist-dashboards-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    tenant = "tuist-#{System.unique_integer([:positive])}"
    token = "tuist-dashboards-token"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => digest})
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    Runtime.share()

    server =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0},
        id: :tuist_dashboards_api
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    now = System.system_time(:second)

    ctx = %{
      url: "http://127.0.0.1:#{port}",
      headers: [{"authorization", "Bearer " <> token}, {"x-scope-orgid", tenant}]
    }

    requests = Fixture.requests((now - 600) * 1_000_000_000)

    for request <- requests,
        do: assert(Req.post!(ctx.url <> "/v1/traces", headers: ctx.headers, json: request).status == 200)

    spans = Enum.flat_map(requests, fn request -> elem(Traces.decode(request), 1) end)
    Map.merge(ctx, %{now: now, spans: spans, params: %{"start" => now - 3600, "end" => now + 60}})
  end

  test "every dashboard search returns Tempo's spans, natively and in the Elixir reference", ctx do
    for {panel, query} <- Fixture.queries() do
      body = search(ctx, query)
      assert spans(body) == Fixture.expected()[panel], "#{panel}: #{query}"

      {:ok, parsed} = TempoSearch.parse(query)
      opts = [trace_start: ctx.params["start"] * 1_000_000_000, trace_end: ctx.params["end"] * 1_000_000_000]
      {:ok, reference} = TempoSearch.json(ctx.spans, parsed, opts ++ [limit: 20, spss: 10])
      assert Pulse.JSON.decode!(reference) == body, "#{panel} reference"
    end
  end

  test "select adds the requested event attributes to each returned span", ctx do
    attributes = fn query, span ->
      ctx
      |> search(query)
      |> get_in(["traces", Access.all(), "spanSet", "spans"])
      |> List.flatten()
      |> Enum.find(&(&1["spanID"] == Fixture.span_id(span)))
      |> Map.fetch!("attributes")
      |> Map.new(&{&1["key"], &1["value"]["stringValue"]})
    end

    queries = Fixture.queries()

    assert attributes.(queries.recent_errors, 13) == %{
             "status" => "error",
             "exception.type" => "Elixir.DBConnection.ConnectionError",
             "exception.message" => "connection not available"
           }

    # No typed event: only the selected value that exists.
    assert attributes.(queries.recent_errors, 63) == %{"status" => "error", "exception.message" => "no type"}
    # Several events: the first event with a matching value.
    assert attributes.(queries.errors_by_type, 52) == %{"exception.type" => "Postgrex.Error"}

    assert attributes.(queries.stacktraces, 62) == %{
             "exception.type" => "Elixir.TuistWeb.Errors.NotFoundError",
             "exception.stacktrace" => "lib/tuist.ex:1: Elixir.TuistWeb.Errors.NotFoundError"
           }
  end

  test "the other structural operators and chains follow parent links", ctx do
    for {query, expected} <- [
          {~s[{ span.selected_account_handle = "tuist" } > { span.error.type != "" }], %{1 => [12]}},
          {~s[{ span.error.type != "" } < { span.selected_account_handle = "tuist" }], %{1 => [11]}},
          {~s[{ span.error.type != "" } << { span.selected_account_handle = "tuist" }], %{1 => [11]}},
          {~s[{ event.exception.type = "Elixir.TuistWeb.Errors.NotFoundError" } ~ { status = error }], %{6 => [63]}},
          {~s[{ span.selected_account_handle = "tuist" } >> { span.error.type != "" } >> { status = error }],
           %{1 => [13]}}
        ] do
      expected = Map.new(expected, fn {trace, ids} -> {Fixture.id(trace), Enum.map(ids, &Fixture.span_id/1)} end)
      assert spans(search(ctx, query)) == expected, query
    end

    response =
      Req.get!(ctx.url <> "/api/search",
        headers: ctx.headers,
        params: Map.put(ctx.params, "q", ~s[{ status = error } | select(span:duration)])
      )

    assert response.status == 400
  end

  test "Error Monitoring rates count spans with a matching event, over HTTP and MCP", ctx do
    {start, finish} = {ctx.now - 3600, ctx.now + 60}

    for {query, count} <- Fixture.rates() do
      params = %{"q" => query, "start" => start, "end" => finish, "step" => "60s"}
      response = Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: params)
      assert response.status == 200, "#{query}: #{inspect(response.body)}"
      assert [%{"samples" => samples}] = response.body["series"], query
      assert round(Enum.sum_by(samples, & &1["value"]) * 60) == count, query

      args = %{"query" => query, "start_ts_ns" => start * 1_000_000_000, "end_ts_ns" => finish * 1_000_000_000}
      assert %{"series" => [%{"value" => value}]} = call_tool(ctx, "traceql_metrics", args)
      assert round(value * (finish - start)) == count, query
    end

    # Structural metrics are not supported; they must reject, not drop the join.
    params = %{"q" => ~s[{ status = error } >> { status = error } | rate()], "start" => start, "end" => finish}
    assert Req.get!(ctx.url <> "/api/metrics/query_range", headers: ctx.headers, params: params).status == 400
  end

  test "MCP search_trace_metadata answers the account error panel", ctx do
    args = %{
      "query" => Fixture.queries().account_errors,
      "start_ts_ns" => ctx.params["start"] * 1_000_000_000,
      "end_ts_ns" => ctx.params["end"] * 1_000_000_000,
      "limit" => 20,
      "spss" => 10
    }

    assert spans(call_tool(ctx, "search_trace_metadata", args)) == Fixture.expected().account_errors
  end

  defp search(ctx, query) do
    params = Map.merge(ctx.params, %{"q" => query, "limit" => 20, "spss" => 10})
    response = Req.get!(ctx.url <> "/api/search", headers: ctx.headers, params: params)
    assert response.status == 200, "#{query}: #{inspect(response.body)}"
    response.body
  end

  defp spans(%{"traces" => traces}) do
    Map.new(traces, fn trace ->
      {String.pad_leading(trace["traceID"], 32, "0"), Enum.map(trace["spanSet"]["spans"], & &1["spanID"])}
    end)
  end

  defp call_tool(ctx, name, args) do
    headers =
      ctx.headers ++
        [
          {"accept", "application/json, text/event-stream"},
          {"mcp-protocol-version", MCPMessages.version()},
          {"mcp-method", "tools/call"},
          {"mcp-name", name}
        ]

    args = Map.put(args, "tenant", ctx.headers |> List.keyfind("x-scope-orgid", 0) |> elem(1))
    body = MCPMessages.request(1, "tools/call", %{"name" => name, "arguments" => args})
    response = Req.post!(ctx.url <> "/mcp", headers: headers, json: body)
    assert response.status == 200
    refute response.body["result"]["isError"], inspect(response.body)
    [%{"text" => text}] = response.body["result"]["content"]
    Pulse.JSON.decode!(text)
  end
end
