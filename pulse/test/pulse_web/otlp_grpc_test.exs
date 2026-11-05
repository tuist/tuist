defmodule PulseWeb.OTLPGRPCTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.OTLP.GRPC.NIF
  alias Pulse.OTLP.Ingest
  alias Pulse.Record.Log
  alias Pulse.Record.Span
  alias Pulse.Storage
  alias Pulse.Test.FailingStorage
  alias Pulse.Test.GRPCClient
  alias Pulse.Test.OTLPLogFixture
  alias Pulse.Test.OTLPMetricFixture
  alias Pulse.Test.OTLPTraceFixture

  @traces "/opentelemetry.proto.collector.trace.v1.TraceService/Export"
  @logs "/opentelemetry.proto.collector.logs.v1.LogsService/Export"
  @metrics "/opentelemetry.proto.collector.metrics.v1.MetricsService/Export"

  setup do
    Pulse.Runtime.share()
    server = start_supervised!({PulseWeb.OTLPGRPC, port: 0, ip: "127.0.0.1"})
    {:ok, port: PulseWeb.OTLPGRPC.port(server), tenant: "grpc-#{System.unique_integer([:positive])}"}
  end

  defp tenant(ctx), do: [metadata: [{"x-scope-orgid", ctx.tenant}]]

  test "exports traces into the tenant's storage", ctx do
    response = GRPCClient.unary(ctx.port, @traces, OTLPTraceFixture.protobuf(), tenant(ctx))

    assert %{status: 0, body: ""} = response
    assert {:ok, [%Span{} = span]} = Storage.query(:traces, ctx.tenant)
    assert span.trace_id == OTLPTraceFixture.trace_id()
  end

  test "exports logs and metrics through the same services as Collector", ctx do
    assert %{status: 0} = GRPCClient.unary(ctx.port, @logs, OTLPLogFixture.protobuf(), tenant(ctx))
    assert {:ok, [%Log{} | _]} = Storage.query(:logs, ctx.tenant)

    assert %{status: 0} = GRPCClient.unary(ctx.port, @metrics, OTLPMetricFixture.protobuf(), tenant(ctx))
    assert {:ok, [_ | _]} = Storage.query(:metrics, ctx.tenant)
  end

  test "accepts gzip-compressed messages", ctx do
    response = GRPCClient.unary(ctx.port, @traces, OTLPTraceFixture.protobuf(), [gzip: true] ++ tenant(ctx))

    assert response.status == 0
    assert {:ok, [_span]} = Storage.query(:traces, ctx.tenant)
  end

  test "reports rejected items as partial success", ctx do
    valid = OTLPTraceFixture.span()
    invalid = Map.put(valid, "traceId", String.duplicate("0", 32))

    response =
      GRPCClient.unary(
        ctx.port,
        @traces,
        OTLPTraceFixture.protobuf(OTLPTraceFixture.payload([valid, invalid])),
        tenant(ctx)
      )

    assert response.status == 0
    assert response.body == Ingest.response_protobuf(1, "invalid records rejected: invalid_trace_id=1")
  end

  test "malformed messages are INVALID_ARGUMENT", ctx do
    assert %{status: 3} = GRPCClient.unary(ctx.port, @traces, <<0xFF, 0xFF, 0xFF>>, tenant(ctx))
  end

  test "unknown methods are UNIMPLEMENTED", ctx do
    path = "/opentelemetry.proto.collector.trace.v1.TraceService/Other"
    assert %{status: 12} = GRPCClient.unary(ctx.port, path, "", tenant(ctx))
  end

  test "authenticates bearer and Basic metadata like OTLP/HTTP", ctx do
    token = "grpc-secret"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
    Pulse.Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{ctx.tenant => digest})

    assert %{status: 16} = GRPCClient.unary(ctx.port, @traces, OTLPTraceFixture.protobuf(), tenant(ctx))

    bearer = [metadata: [{"x-scope-orgid", ctx.tenant}, {"authorization", "Bearer " <> token}]]
    assert %{status: 0} = GRPCClient.unary(ctx.port, @traces, OTLPTraceFixture.protobuf(), bearer)

    basic = [metadata: [{"authorization", "Basic " <> Base.encode64(ctx.tenant <> ":" <> token)}]]
    assert %{status: 0} = GRPCClient.unary(ctx.port, @traces, OTLPTraceFixture.protobuf(), basic)
    assert {:ok, [_, _]} = Storage.query(:traces, ctx.tenant)
  end

  test "invalid forwarded text metadata rejects rather than changing tenancy or idempotency", ctx do
    for metadata <- [
          [{"x-scope-orgid", "tenänt"}],
          [{"idempotency-key", <<128>>}],
          [{"authorization", "Bearer " <> <<128>>}],
          [{"x-scope-orgid", ctx.tenant}, {"x-scope-orgid", "tenänt"}]
        ] do
      assert %{status: 3} = GRPCClient.unary(ctx.port, @logs, OTLPLogFixture.protobuf(), metadata: metadata)
    end

    assert {:ok, []} = Storage.query(:logs, "default")
    assert {:ok, []} = Storage.query(:logs, ctx.tenant)

    # Unconsumed binary metadata remains legal; only forwarded text is checked.
    assert %{status: 0} =
             GRPCClient.unary(ctx.port, @logs, OTLPLogFixture.protobuf(),
               metadata: [{"x-scope-orgid", ctx.tenant}, {"grpc-trace-bin", Base.encode64(<<128>>)}]
             )
  end

  test "an incomplete body expires and frees admission without closing its HTTP2 connection" do
    {:ok, listener, port} = NIF.otlp_grpc_start("127.0.0.1", 0, self(), 1024, 1, 100)
    {:ok, conn} = Mint.HTTP2.connect(:http, "127.0.0.1", port, mode: :passive)
    tasks = start_supervised!(Task.Supervisor)

    try do
      {:ok, conn, ref} =
        Mint.HTTP2.request(conn, "POST", @logs, [{"content-type", "application/grpc"}, {"te", "trailers"}], :stream)

      admit(:logs)
      {:ok, conn} = Mint.HTTP2.stream_request_body(conn, ref, <<0, 1::32>>)
      {conn, headers} = incomplete_response(conn, ref, [])
      assert {"grpc-status", "14"} in headers
      refute_received {:pulse_otlp_grpc, _, _, _, _}

      next = Task.Supervisor.async_nolink(tasks, fn -> GRPCClient.unary(port, @logs, "") end)
      admit(:logs)
      assert_receive {:pulse_otlp_grpc, reply, :logs, _, ""}, 5_000
      assert :ok = NIF.otlp_grpc_reply(reply, 0, "", "")
      assert %{status: 0} = Task.await(next, 5_000)
      Mint.HTTP2.close(conn)
    after
      Mint.HTTP2.close(conn)
      NIF.otlp_grpc_stop(listener)
    end
  end

  defp incomplete_response(conn, ref, headers) do
    {:ok, conn, responses} = Mint.HTTP2.recv(conn, 0, 5_000)

    headers =
      Enum.reduce(responses, headers, fn
        {:headers, ^ref, next}, acc -> acc ++ next
        _, acc -> acc
      end)

    if {:done, ref} in responses, do: {conn, headers}, else: incomplete_response(conn, ref, headers)
  end

  test "storage unavailability is retryable UNAVAILABLE; overload carries RetryInfo", ctx do
    Pulse.Runtime.put_env(:pulse, Storage, adapter: FailingStorage)

    Pulse.Runtime.put_env(:pulse, FailingStorage, {:error, :storage_unavailable})
    assert %{status: 14} = GRPCClient.unary(ctx.port, @logs, OTLPLogFixture.protobuf(), tenant(ctx))

    Pulse.Runtime.put_env(:pulse, FailingStorage, {:error, :owner_overloaded})
    response = GRPCClient.unary(ctx.port, @logs, OTLPLogFixture.protobuf(), tenant(ctx))

    assert response.status == 8
    assert response.details =~ "type.googleapis.com/google.rpc.RetryInfo"
  end

  test "maps every classified outcome to the OTLP-specified gRPC code" do
    assert PulseWeb.OTLPGRPC.to_grpc({:ok, 0}) == {0, "", ""}
    assert {3, _, ""} = PulseWeb.OTLPGRPC.to_grpc({:error, {400, "invalid_protobuf"}})
    assert {16, _, ""} = PulseWeb.OTLPGRPC.to_grpc({:error, {401, "unauthorized"}})
    assert {6, _, ""} = PulseWeb.OTLPGRPC.to_grpc({:error, {409, "keyed_content_mismatch"}})
    assert {8, _, ""} = PulseWeb.OTLPGRPC.to_grpc({:error, {413, "payload_too_large"}})
    assert {14, _, ""} = PulseWeb.OTLPGRPC.to_grpc({:error, {503, "unavailable"}})
  end

  test "a timed out call retains its admission until the BEAM answers" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Callers})
    {:ok, listener, port} = NIF.otlp_grpc_start("127.0.0.1", 0, self(), 1_048_576, 1, 250)

    try do
      first = Task.Supervisor.async_nolink(tasks, fn -> GRPCClient.unary(port, @traces, "") end)
      admit(:traces)
      assert_receive {:pulse_otlp_grpc, first_reply, :traces, _, ""}, 5_000
      assert %{status: 14, message: "ingest timed out"} = Task.await(first, 5_000)

      # The queued call's deadline includes admission. Its completion, not a
      # fixed delay, proves it cannot bypass the retained BEAM reply handle.
      second = Task.Supervisor.async_nolink(tasks, fn -> GRPCClient.unary(port, @traces, "") end)
      assert %{status: 14, message: "ingest timed out"} = Task.await(second, 5_000)
      refute_received {:pulse_otlp_grpc, _, _, _, _}
      refute_received {:pulse_otlp_grpc_admit, _, _, _}

      assert :ok = NIF.otlp_grpc_reply(first_reply, 0, "", "")
      third = Task.Supervisor.async_nolink(tasks, fn -> GRPCClient.unary(port, @traces, "") end)
      admit(:traces)
      assert_receive {:pulse_otlp_grpc, third_reply, :traces, _, ""}, 5_000
      assert :ok = NIF.otlp_grpc_reply(third_reply, 0, "", "")
      assert %{status: 0} = Task.await(third, 5_000)
    after
      NIF.otlp_grpc_stop(listener)
    end
  end

  test "a stuck BEAM handler is killed at its watchdog deadline and frees admission", ctx do
    Pulse.Runtime.put_env(:pulse, Storage, adapter: FailingStorage)
    Pulse.Runtime.put_env(:pulse, FailingStorage, {:block, self()})

    server =
      start_supervised!({PulseWeb.OTLPGRPC, name: __MODULE__.Watchdog, port: 0, ip: "127.0.0.1", max_in_flight: 1})

    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.DeadlineCallers})
    port = PulseWeb.OTLPGRPC.port(server)

    request =
      Task.Supervisor.async_nolink(tasks, fn ->
        GRPCClient.unary(port, @logs, OTLPLogFixture.protobuf(), tenant(ctx))
      end)

    assert_receive {:append_started, handler}, 5_000
    monitor = Process.monitor(handler)
    state = :sys.get_state(server)
    [{ref, work}] = Map.to_list(state.pending)
    assert work.pid == handler
    assert is_integer(Process.read_timer(work.timer))
    assert state.handler_timeout_ms == 31_000
    send(server, {:handler_deadline, ref})
    assert_receive {:DOWN, ^monitor, :process, ^handler, :killed}, 5_000
    assert %{status: 14, message: "ingest handler deadline exceeded"} = Task.await(request, 5_000)
    Pulse.Runtime.put_env(:pulse, FailingStorage, {:error, :storage_unavailable})
    assert %{status: 14} = GRPCClient.unary(port, @logs, OTLPLogFixture.protobuf(), tenant(ctx))
  end

  test "the scheduled watchdog expires without injecting a timer message", ctx do
    Pulse.Runtime.put_env(:pulse, Storage, adapter: FailingStorage)
    Pulse.Runtime.put_env(:pulse, FailingStorage, {:block, self()})

    server =
      start_supervised!(
        {PulseWeb.OTLPGRPC,
         name: __MODULE__.ScheduledWatchdog, port: 0, ip: "127.0.0.1", timeout_ms: 50, max_in_flight: 1}
      )

    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.TimedCallers})
    port = PulseWeb.OTLPGRPC.port(server)

    call =
      Task.Supervisor.async_nolink(tasks, fn ->
        GRPCClient.unary(port, @logs, OTLPLogFixture.protobuf(), tenant(ctx))
      end)

    assert_receive {:append_started, handler}, 5_000
    monitor = Process.monitor(handler)
    assert %{status: 14} = Task.await(call, 5_000)
    assert_receive {:DOWN, ^monitor, :process, ^handler, :killed}, 5_000
    Pulse.Runtime.put_env(:pulse, FailingStorage, {:error, :storage_unavailable})
    assert %{status: 14} = GRPCClient.unary(port, @logs, OTLPLogFixture.protobuf(), tenant(ctx))
  end

  test "heap-killed handlers return permanent RESOURCE_EXHAUSTED without RetryInfo" do
    server =
      start_supervised!(
        {PulseWeb.OTLPGRPC, name: __MODULE__.SmallHeap, port: 0, ip: "127.0.0.1", max_heap_words: 1_000}
      )

    response = GRPCClient.unary(PulseWeb.OTLPGRPC.port(server), @logs, OTLPLogFixture.protobuf())
    assert response.status == 8
    assert response.details in [nil, ""]
  end

  test "a handler that dies without answering completes the call as UNAVAILABLE" do
    owner =
      start_supervised!(
        {Task,
         fn ->
           receive do
             {:pulse_otlp_grpc_admit, reply, :traces, _headers} -> NIF.otlp_grpc_reply(reply, 0, "", "")
           end

           receive do
             {:pulse_otlp_grpc, _reply, :traces, _headers, _body} -> exit(:crashed)
           end
         end}
      )

    {:ok, listener, port} = NIF.otlp_grpc_start("127.0.0.1", 0, owner, 1_048_576, 4, 10_000)

    try do
      assert %{status: 14, message: "ingest handler exited"} =
               GRPCClient.unary(port, @traces, OTLPTraceFixture.protobuf())
    after
      NIF.otlp_grpc_stop(listener)
    end
  end

  # Answer the listener's header-only admission request as the owner process.
  defp admit(signal) do
    assert_receive {:pulse_otlp_grpc_admit, reply, ^signal, _headers}, 5_000
    assert :ok = NIF.otlp_grpc_reply(reply, 0, "", "")
  end

  test "a call refused at admission never reads or forwards its message" do
    {:ok, listener, port} = NIF.otlp_grpc_start("127.0.0.1", 0, self(), 1_048_576, 4, 10_000)

    try do
      metadata = [{"authorization", "Bearer nope"}, {"x-scope-orgid", "acme"}]
      call = Task.async(fn -> GRPCClient.unary(port, @traces, OTLPTraceFixture.protobuf(), metadata: metadata) end)

      assert_receive {:pulse_otlp_grpc_admit, reply, :traces, headers}, 5_000
      assert {"authorization", "Bearer nope"} in headers
      assert :ok = NIF.otlp_grpc_reply(reply, 16, "unauthorized", "")
      assert %{status: 16, message: "unauthorized"} = Task.await(call, 5_000)
      refute_received {:pulse_otlp_grpc, _, _, _, _}
    after
      NIF.otlp_grpc_stop(listener)
    end
  end

  test "messages over the size limit are rejected before reaching the BEAM" do
    {:ok, listener, port} = NIF.otlp_grpc_start("127.0.0.1", 0, self(), 16, 4, 10_000)

    try do
      for opts <- [[], [gzip: true]] do
        call = Task.async(fn -> GRPCClient.unary(port, @traces, OTLPTraceFixture.protobuf(), opts) end)
        admit(:traces)
        assert %{status: 8} = Task.await(call, 5_000)
        refute_received {:pulse_otlp_grpc, _, _, _, _}
      end
    after
      NIF.otlp_grpc_stop(listener)
    end
  end
end
