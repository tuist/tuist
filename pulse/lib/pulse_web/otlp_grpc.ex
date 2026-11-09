defmodule PulseWeb.OTLPGRPC do
  @moduledoc """
  OTLP/gRPC receiver for logs, metrics and traces (`opentelemetry.proto.
  collector.*.v1.*Service/Export`), so Collectors, Alloy and SDKs can export
  over gRPC without an HTTP bridge.

  A Rust listener (tonic) owns HTTP/2, gzip/zstd decompression, message
  limits and backpressure. Before it reads or decompresses a message, it asks
  this process to admit the call from its metadata alone (tenant and
  credential), so unauthenticated callers spend no decode work; only admitted
  calls hand their raw request message over. Every call then runs in its own
  supervised task through exactly
  the OTLP/HTTP path: the same tenancy (`x-scope-orgid` metadata or Basic
  credentials), authorization, idempotency keys, decoding, storage and
  partial-success semantics.

  Outcomes map to gRPC status codes as the OTLP specification asks:
  retryable overload is `RESOURCE_EXHAUSTED` with `RetryInfo`, storage
  unavailability `UNAVAILABLE`, and permanent rejections
  `INVALID_ARGUMENT`, `UNAUTHENTICATED` or `ALREADY_EXISTS`. A handler that
  crashes before answering completes its call as `UNAVAILABLE`.

  Options (see `config/runtime.exs`): `:port`, `:ip`, `:max_message_bytes`,
  `:max_in_flight` and `:timeout_ms`.
  """

  use Pulse.Runtime.GenServer

  alias Pulse.OTLP.GRPC.NIF
  alias Pulse.OTLP.Ingest
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias PulseWeb.OTLPHTTP

  @heap_words 16_000_000

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts) do
    Pulse.Runtime.GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "The bound TCP port (useful with `port: 0`)."
  def port(server \\ __MODULE__), do: Pulse.Runtime.GenServer.call(server, :port)

  @impl true
  def init(opts) do
    ensure_api!()
    {:ok, tasks} = Task.Supervisor.start_link()

    case NIF.otlp_grpc_start(
           Keyword.get(opts, :ip, "0.0.0.0"),
           Keyword.get(opts, :port, 4317),
           self(),
           Keyword.get(opts, :max_message_bytes, 16 * 1024 * 1024),
           Keyword.get(opts, :max_in_flight, 64),
           Keyword.get(opts, :timeout_ms, 30_000)
         ) do
      {:ok, listener, port} ->
        {:ok,
         %{
           listener: listener,
           port: port,
           tasks: tasks,
           pending: %{},
           handler_timeout_ms: Keyword.get(opts, :timeout_ms, 30_000) + 1_000,
           heap_words: Keyword.get(opts, :max_heap_words, @heap_words)
         }}

      {:error, reason} ->
        {:stop, {:otlp_grpc_listen_failed, reason}}
    end
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  @impl true
  def handle_info({:pulse_otlp_grpc, reply, signal, headers, body}, state) do
    heap_words = state.heap_words
    {:noreply, run(state, reply, fn -> answer(reply, signal, headers, body, heap_words) end)}
  end

  # Header-only admission: the listener waits for this answer before it reads
  # or decompresses the message.
  def handle_info({:pulse_otlp_grpc_admit, reply, signal, headers}, state) do
    {:noreply,
     run(state, reply, fn ->
       {code, message, details} = signal |> admit(headers) |> to_grpc()
       NIF.otlp_grpc_reply(reply, code, message, details)
     end)}
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {work, pending} = Map.pop(state.pending, ref)

    if work do
      Process.cancel_timer(work.timer, async: true, info: false)
      NIF.otlp_grpc_reply(work.reply, 14, "ingest handler exited", "")
    end

    {:noreply, %{state | pending: pending}}
  end

  def handle_info({:handler_deadline, ref}, state) do
    pending =
      case Map.fetch(state.pending, ref) do
        {:ok, work} ->
          Process.exit(work.pid, :kill)
          Map.put(state.pending, ref, %{work | expired?: true})

        :error ->
          state.pending
      end

    {:noreply, %{state | pending: pending}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {work, pending} = Map.pop(state.pending, ref)

    if work do
      Process.cancel_timer(work.timer, async: true, info: false)

      {code, message} =
        cond do
          work.expired? -> {14, "ingest handler deadline exceeded"}
          reason == :killed -> {8, "ingest resource limit"}
          true -> {14, "ingest handler exited"}
        end

      NIF.otlp_grpc_reply(work.reply, code, message, "")
    end

    {:noreply, %{state | pending: pending}}
  end

  @impl true
  def terminate(_reason, state) do
    NIF.otlp_grpc_stop(state.listener)
    :ok
  end

  # Every call answers through `reply`; a crashed or timed-out task answers
  # from the DOWN/deadline handlers instead.
  defp run(state, reply, fun) do
    task = Task.Supervisor.async_nolink(state.tasks, Runtime.capture(fun))
    timer = Process.send_after(self(), {:handler_deadline, task.ref}, state.handler_timeout_ms)
    pending = %{reply: reply, pid: task.pid, timer: timer, expired?: false}
    %{state | pending: Map.put(state.pending, task.ref, pending)}
  end

  defp ensure_api! do
    if NIF.otlp_grpc_api_version() != 3,
      do: raise("OTLP/gRPC native artifact is incompatible; rebuild with PULSE_NIF_FORCE_BUILD=1")
  end

  defp answer(reply, signal, headers, body, heap_words) do
    Process.flag(:max_heap_size, %{size: heap_words, kill: true, error_logger: false, include_shared_binaries: true})
    {code, message, payload} = signal |> handle(headers, body) |> to_grpc()
    NIF.otlp_grpc_reply(reply, code, message, payload)
  end

  @doc false
  # Authorization from metadata alone, before the message is read.
  def admit(signal, headers) do
    case authorize(headers) do
      {:ok, _conn, _tenant} -> {:ok, :admitted}
      {:error, reason} -> {:error, Ingest.classify(signal, reason)}
    end
  end

  @doc false
  # The OTLP/HTTP pipeline on a header-only conn: gRPC metadata carries the
  # same tenant, credential and idempotency headers. Authorization repeats
  # here because the message is a separate delivery from its admission.
  def handle(signal, headers, body) do
    result =
      with {:ok, conn, tenant} <- authorize(headers),
           :ok <- PulseWeb.Authenticate.charge_quota(conn, byte_size(body)),
           :ok <- acquire(signal, tenant, byte_size(body)),
           {:ok, key} <- OTLPHTTP.single_header(conn, "idempotency-key", nil) do
        with {:ok, _rejected, _message} = ok <-
               Ingest.ingest(signal, tenant, key, Ingest.decode(signal, :protobuf, body)) do
          Pulse.Usage.request(signal, tenant, byte_size(body))
          ok
        end
      end

    case result do
      {:ok, rejected, message} -> {:ok, rejected, message}
      {:error, reason} -> {:error, Ingest.classify(signal, reason)}
    end
  end

  # Each call runs in its own task, so its slot is released when it exits.
  # Configured tenant limits apply to the verified tenant and the decompressed
  # message size.
  defp acquire(signal, tenant, bytes) do
    limited = if Pulse.TenantLimits.configured?(), do: tenant

    with :ok <- tenant_rate(limited, bytes),
         :ok <- Pulse.IngestAdmission.acquire(signal, tenant, limited) do
      :ok
    else
      {:error, _} -> {:error, :owner_overloaded}
    end
  end

  defp tenant_rate(nil, _bytes), do: :ok

  defp tenant_rate(tenant, bytes) do
    with {:error, _} = error <- Pulse.TenantLimits.take_ingest_bytes(tenant, bytes) do
      Pulse.SelfMetrics.admission_rejection(:ingest, :tenant_rate)
      error
    end
  end

  defp authorize(headers) do
    conn =
      %Plug.Conn{req_headers: headers}
      |> PulseWeb.BasicTenant.call([])
      |> PulseWeb.Authenticate.assign_principal()

    with {:ok, tenant} <- OTLPHTTP.single_header(conn, "x-scope-orgid", "default"),
         :ok <- S3.validate_tenant(tenant),
         :ok <- Pulse.Auth.verify(conn, tenant, :ingest),
         do: {:ok, conn, tenant}
  end

  @doc false
  def to_grpc({:ok, :admitted}), do: {0, "", ""}
  def to_grpc({:ok, rejected}), do: to_grpc({:ok, rejected, "invalid records rejected"})
  def to_grpc({:ok, rejected, message}), do: {0, "", Ingest.response_protobuf(rejected, message)}
  def to_grpc({:error, {429, message}}), do: {8, message, status_details(8, message, retry_info(1))}
  def to_grpc({:error, {503, message}}), do: {14, message, ""}
  def to_grpc({:error, {401, message}}), do: {16, message, ""}
  def to_grpc({:error, {403, message}}), do: {7, message, ""}
  def to_grpc({:error, {409, message}}), do: {6, message, ""}
  # Too large to ever succeed: RESOURCE_EXHAUSTED without RetryInfo is permanent.
  def to_grpc({:error, {413, message}}), do: {8, message, ""}
  def to_grpc({:error, {_status, message}}), do: {3, message, ""}

  # google.rpc.Status{code, message, details: [Any(RetryInfo{retry_delay})]}
  defp status_details(code, message, detail) do
    IO.iodata_to_binary([<<8>>, Ingest.varint(code), Ingest.field_bytes(2, message), Ingest.field_bytes(3, detail)])
  end

  defp retry_info(seconds) do
    delay = IO.iodata_to_binary([<<8>>, Ingest.varint(seconds)])
    info = IO.iodata_to_binary(Ingest.field_bytes(1, delay))

    IO.iodata_to_binary([
      Ingest.field_bytes(1, "type.googleapis.com/google.rpc.RetryInfo"),
      Ingest.field_bytes(2, info)
    ])
  end
end
