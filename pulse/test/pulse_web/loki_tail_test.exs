defmodule PulseWeb.LokiTailTest do
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.Parser
  alias Pulse.Loki.Tail
  alias Pulse.Record.Log
  alias Pulse.Runtime
  alias Pulse.Test.RuntimePlug
  alias Pulse.Test.WebSocketClient

  setup do
    Runtime.share()
    api = start_supervised!({Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(api)
    {:ok, port: port, tenant: "tail-#{System.unique_integer([:positive])}"}
  end

  test "mailbox admission overflow closes explicitly with WebSocket 1013" do
    assert {:stop, :normal, {1013, "tail backlog limit"}, %{}} =
             PulseWeb.LokiTail.handle_info(:tail_overloaded, %{})
  end

  defp push(ctx, stream, lines) do
    values = Enum.map(lines, fn {ts, line} -> [Integer.to_string(ts), line] end)

    response =
      Req.post!("http://127.0.0.1:#{ctx.port}/loki/api/v1/push",
        json: %{"streams" => [%{"stream" => stream, "values" => values}]},
        headers: [{"x-scope-orgid", ctx.tenant}],
        retry: false
      )

    assert response.status == 204
  end

  defp tail(ctx, query, params \\ []) do
    path = "/loki/api/v1/tail?" <> URI.encode_query([{"query", query} | params])
    WebSocketClient.connect(ctx.port, path, [{"x-scope-orgid", ctx.tenant}])
  end

  defp now, do: System.system_time(:nanosecond)

  test "sends recent history oldest first, then matching live entries through the pipeline", ctx do
    t = now()
    push(ctx, %{"service_name" => "api"}, [{t - 3_000, "level=info msg=old"}, {t - 2_000, "level=error msg=older"}])
    push(ctx, %{"service_name" => "web"}, [{t - 1_000, "level=error msg=web"}])

    {:ok, socket} = tail(ctx, ~s({service_name="api"} | logfmt | level="error"), limit: "10")

    assert %{"streams" => [history], "dropped_entries" => nil} = WebSocketClient.next_json(socket)
    assert history["values"] == [[Integer.to_string(t - 2_000), "level=error msg=older"]]
    assert history["stream"]["service_name"] == "api"
    assert history["stream"]["msg"] == "older"

    push(ctx, %{"service_name" => "web"}, [{t + 1_000, "level=error msg=other"}])
    push(ctx, %{"service_name" => "api"}, [{t + 3_000, "level=error msg=b"}, {t + 2_000, "level=error msg=a"}])
    push(ctx, %{"service_name" => "api"}, [{t + 4_000, "level=info msg=skip"}])
    push(ctx, %{"service_name" => "api"}, [{t + 5_000, "level=error msg=c"}])

    assert %{"streams" => streams} = WebSocketClient.next_json(socket)
    lines = for s <- streams, [_ts, line] <- s["values"], do: line
    assert lines == ["level=error msg=a", "level=error msg=b"]

    assert %{"streams" => [%{"values" => [[_, "level=error msg=c"]]}]} = WebSocketClient.next_json(socket)
    WebSocketClient.close(socket)
  end

  test "history keeps only the newest limit entries", ctx do
    t = now()
    push(ctx, %{"service_name" => "api"}, for(i <- 1..5, do: {t - 10_000 + i, "line #{i}"}))

    {:ok, socket} = tail(ctx, ~s({service_name="api"}), limit: "2")
    assert %{"streams" => [%{"values" => values}]} = WebSocketClient.next_json(socket)
    assert Enum.map(values, &List.last/1) == ["line 4", "line 5"]
    WebSocketClient.close(socket)
  end

  test "a closed socket leaves the tenant's tailers", ctx do
    {:ok, socket} = tail(ctx, ~s({service_name="api"}))
    assert %{"streams" => []} = WebSocketClient.next_json(socket)
    [pid] = Tail.tailers(ctx.tenant)
    ref = Process.monitor(pid)
    WebSocketClient.close(socket)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5_000
    assert Tail.tailers(ctx.tenant) == []
  end

  test "follower loss closes explicitly and a reconnect receives history and live logs", ctx do
    {:ok, socket} = tail(ctx, ~s({service_name="api"}))
    assert %{"streams" => []} = WebSocketClient.next_json(socket)
    [tailer] = Tail.tailers(ctx.tenant)
    tailer_ref = Process.monitor(tailer)
    assert {:ok, follower} = Tail.follower(ctx.tenant)
    follower_ref = Process.monitor(follower)
    Process.exit(follower, :kill)
    assert_receive {:DOWN, ^follower_ref, :process, ^follower, :killed}

    assert {:close, <<1013::16, "tail follower unavailable">>} = WebSocketClient.next_frame(socket, 2_000)
    WebSocketClient.close(socket)
    assert_receive {:DOWN, ^tailer_ref, :process, ^tailer, _}, 5_000

    t = now()
    push(ctx, %{"service_name" => "api"}, [{t, "during reconnect"}])
    {:ok, reconnected} = tail(ctx, ~s({service_name="api"}))
    assert %{"streams" => [%{"values" => [[_, "during reconnect"]]}]} = WebSocketClient.next_json(reconnected)
    push(ctx, %{"service_name" => "api"}, [{t + 1, "live again"}])
    assert %{"streams" => [%{"values" => [[_, "live again"]]}]} = WebSocketClient.next_json(reconnected)
    WebSocketClient.close(reconnected)
  end

  test "registry restart closes existing sockets instead of silently losing membership", ctx do
    {:ok, socket} = tail(ctx, ~s({service_name="api"}))
    assert %{"streams" => []} = WebSocketClient.next_json(socket)
    [tailer] = Tail.tailers(ctx.tenant)
    ref = Process.monitor(tailer)
    :ok = Supervisor.stop(Runtime.whereis(Tail.Registry), :shutdown)
    assert {:close, <<1013::16, "tail follower unavailable">>} = WebSocketClient.next_frame(socket, 2_000)
    WebSocketClient.close(socket)
    assert_receive {:DOWN, ^ref, :process, ^tailer, _}, 5_000
    _ = :sys.get_state(Runtime.whereis(Tail))
    assert Tail.tailers(ctx.tenant) == []

    {:ok, reconnected} = tail(ctx, ~s({service_name="api"}))
    assert %{"streams" => []} = WebSocketClient.next_json(reconnected)
    push(ctx, %{"service_name" => "api"}, [{now(), "after registry restart"}])

    assert %{"streams" => [%{"values" => [[_, "after registry restart"]]}]} =
             WebSocketClient.next_json(reconnected)

    WebSocketClient.close(reconnected)
  end

  test "tail supervision unavailability returns HTTP 503 before upgrading", ctx do
    assert :ok = stop_supervised(Tail)
    assert {:error, {503, _}} = tail(ctx, ~s({service_name="api"}))
  end

  test "rejects metric queries, plain HTTP and invalid parameters before upgrading", ctx do
    assert {:error, {400, _}} = tail(ctx, ~s<count_over_time({service_name="api"}[1m])>)
    assert {:error, {400, _}} = tail(ctx, ~s({service_name="api"}), limit: "0")
    assert {:error, {400, _}} = tail(ctx, ~s({service_name="api"}), delay_for: "6")
    assert {:error, {400, _}} = tail(ctx, ~s<{service_name=~"("}>)

    response =
      Req.get!("http://127.0.0.1:#{ctx.port}/loki/api/v1/tail",
        params: [query: ~s({service_name="api"})],
        headers: [{"x-scope-orgid", ctx.tenant}],
        retry: false
      )

    assert response.status == 400
    assert Tail.tailers(ctx.tenant) == []
  end

  test "limits concurrent tails per tenant", ctx do
    Runtime.put_env(:pulse, Tail, max_per_tenant: 1)
    {:ok, socket} = tail(ctx, ~s({service_name="api"}))
    assert %{"streams" => []} = WebSocketClient.next_json(socket)
    assert {:error, {429, _}} = tail(ctx, ~s({service_name="api"}))
    WebSocketClient.close(socket)
  end

  test "an overloaded tailer drops batches and reports them" do
    state = %{compiled: Tail.compile(parse!(~s({service_name="api"}))), limit: 100, max_backlog: -1}
    record = %Log{timestamp_ns: 42, service: "api", body: "x", resource: %{}, attributes: %{}}

    assert {:push, {:text, frame}, ^state} = PulseWeb.LokiTail.handle_info({Tail, [record]}, state)

    assert %{"streams" => [], "dropped_entries" => [%{"timestamp" => "42", "labels" => %{"service_name" => "api"}}]} =
             JSON.decode!(frame)
  end

  defp parse!(query) do
    {:ok, ast} = Parser.parse(query)
    ast
  end
end
