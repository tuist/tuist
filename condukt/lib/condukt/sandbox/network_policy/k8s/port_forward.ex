defmodule Condukt.Sandbox.NetworkPolicy.K8s.PortForward do
  @moduledoc false

  # Owns a single Kubernetes `pods/portforward` WebSocket to the
  # session pod's egress sidecar control port.
  #
  # Why portforward instead of `pods/exec`: a control plane should run
  # over a real socket, not a process's stdout. exec multiplexes the
  # channel onto a spawned command's stdout/stdin, so any stray write
  # to fd 1 corrupts the NDJSON framing and there is no clean reconnect
  # story. portforward is a first-class socket to the port.
  #
  # We reuse the `K8s.Conn` the rest of the sandbox already holds for
  # auth and TLS (client cert / SA token / exec credential plugin /
  # cluster CA), drive `Mint.WebSocket` directly (the `:k8s` high-level
  # client models exec only), set the `v4.channel.k8s.io` subprotocol,
  # and run the channel framing through
  # `Condukt.Sandbox.NetworkPolicy.K8s.PortForward.Codec`.
  #
  # Requires a cluster that serves port-forward over WebSockets
  # (Kubernetes >= 1.30, GA per KEP-4006).
  #
  # The owner gets the same messages the control bridge already
  # handled over exec, so the bridge's frame logic is transport
  # agnostic:
  #
  #   * `{:control_bridge_data, binary}` - bytes off the pod port
  #   * `{:control_bridge_eof}`          - the channel closed

  use GenServer

  alias Condukt.Sandbox.NetworkPolicy.K8s.PortForward.Codec
  alias K8s.Conn.RequestOptions

  require Logger

  @subprotocol "v4.channel.k8s.io"
  @default_port 15_002

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Writes an application payload onto the forwarded port (data channel)."
  def send_payload(pid, payload) when is_binary(payload) do
    GenServer.cast(pid, {:send, payload})
  end

  @doc "Closes the channel and stops the process."
  def close(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000), else: :ok
  end

  @impl true
  def init(opts) do
    conn = Keyword.fetch!(opts, :conn)
    namespace = Keyword.fetch!(opts, :namespace)
    pod_name = Keyword.fetch!(opts, :pod_name)
    owner = Keyword.fetch!(opts, :owner)
    port = Keyword.get(opts, :port, @default_port)

    case connect(conn, namespace, pod_name, port) do
      {:ok, http, websocket, ref, initial_frames} ->
        state = %{
          owner: owner,
          http: http,
          websocket: websocket,
          ref: ref,
          codec: Codec.new()
        }

        {:ok, process_initial_frames(state, initial_frames)}

      {:error, reason} ->
        Logger.warning(fn -> "[sandbox.network_policy.k8s] portforward connect failed: #{inspect(reason)}" end)
        {:stop, {:portforward_failed, reason}}
    end
  end

  @impl true
  def handle_cast({:send, payload}, state) do
    with {:ok, websocket, data} <-
           Mint.WebSocket.encode(state.websocket, {:binary, Codec.frame(payload)}),
         {:ok, http} <- Mint.WebSocket.stream_request_body(state.http, state.ref, data) do
      {:noreply, %{state | http: http, websocket: websocket}}
    else
      {:error, transport, reason} when is_struct(transport) ->
        {:stop, {:send_failed, reason}, %{state | http: transport}}

      {:error, reason} ->
        {:stop, {:send_failed, reason}, state}
    end
  end

  @impl true
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.http, message) do
      {:ok, http, responses} ->
        handle_responses(%{state | http: http}, responses)

      {:error, http, _reason, _responses} ->
        eof(%{state | http: http})

      :unknown ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    with %{websocket: ws, http: http, ref: ref} when not is_nil(ws) <- state,
         {:ok, _ws, data} <- Mint.WebSocket.encode(ws, :close),
         {:ok, http} <- Mint.WebSocket.stream_request_body(http, ref, data) do
      Mint.HTTP.close(http)
    else
      _ -> if state[:http], do: Mint.HTTP.close(state.http)
    end

    :ok
  end

  defp connect(conn, namespace, pod_name, port) do
    with {:ok, request_options} <- RequestOptions.generate(conn),
         %URI{host: host} = uri when is_binary(host) <- URI.parse(conn.url),
         {:ok, http} <-
           Mint.HTTP.connect(scheme(uri), host, uri_port(uri),
             protocols: [:http1],
             transport_opts: request_options.ssl_options
           ),
         {:ok, http} <- Mint.HTTP.set_mode(http, :passive),
         path = portforward_path(namespace, pod_name, port),
         headers = upgrade_headers(request_options),
         {:ok, http, ref} <- Mint.WebSocket.upgrade(ws_scheme(uri), http, path, headers),
         {:ok, http, response} <- receive_upgrade_response(http, ref),
         {:ok, http} <- Mint.HTTP.set_mode(http, :active),
         {:ok, http, websocket} <-
           Mint.WebSocket.new(http, ref, response.status, response.headers),
         {:ok, websocket, initial} <- decode_initial(websocket, response.data) do
      # The API server frequently ships the port-forward channel
      # handshake frames in the same TCP read as the HTTP 101. Those
      # bytes come back as `response.data`; if we do not decode them
      # through the freshly built websocket here they are lost, the
      # codec never sees the per-channel port handshake, and it strips
      # two real bytes off the first data/error frame instead.
      {:ok, http, websocket, ref, initial}
    else
      {:error, _conn, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp scheme(%URI{scheme: "http"}), do: :http
  defp scheme(_), do: :https

  defp ws_scheme(%URI{scheme: "http"}), do: :ws
  defp ws_scheme(_), do: :wss

  defp uri_port(%URI{port: port}) when is_integer(port), do: port
  defp uri_port(_), do: 443

  defp portforward_path(namespace, pod_name, port) do
    "/api/v1/namespaces/#{namespace}/pods/#{pod_name}/portforward?ports=#{port}"
  end

  defp upgrade_headers(request_options) do
    request_options.headers
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
    |> List.keystore("sec-websocket-protocol", 0, {"sec-websocket-protocol", @subprotocol})
  end

  # Drain the HTTP upgrade response synchronously before flipping the
  # socket to active mode (mirrors the K8s client's own handshake).
  defp receive_upgrade_response(http, ref) do
    acc = %{status: nil, headers: [], data: "", done: false}

    Enum.reduce_while(Stream.cycle([:ok]), {http, acc}, fn _, {http, acc} ->
      recv_upgrade_step(http, ref, acc)
    end)
  end

  defp recv_upgrade_step(http, ref, acc) do
    case Mint.HTTP.recv(http, 0, 5_000) do
      {:ok, http, parts} ->
        acc = merge_upgrade_parts(acc, parts, ref)
        if acc.done, do: {:halt, {:ok, http, acc}}, else: {:cont, {http, acc}}

      {:error, http, error, _} ->
        {:halt, {:error, http, error}}
    end
  end

  # Data parts are concatenated, not overwritten: the early websocket
  # bytes (channel handshake, sometimes the first frame too) can span
  # parts and recv iterations, and dropping any of them reintroduces
  # the off-by-two strip.
  defp merge_upgrade_parts(acc, parts, ref) do
    Enum.reduce(parts, acc, fn
      {:status, ^ref, status}, acc -> %{acc | status: status}
      {:headers, ^ref, headers}, acc -> %{acc | headers: headers}
      {:data, ^ref, data}, acc -> %{acc | data: acc.data <> data}
      {:done, ^ref}, acc -> %{acc | done: true}
      _other, acc -> acc
    end)
  end

  defp decode_initial(websocket, ""), do: {:ok, websocket, []}

  defp decode_initial(websocket, data) do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} -> {:ok, websocket, frames}
      {:error, websocket, _reason} -> {:ok, websocket, []}
    end
  end

  defp handle_responses(state, responses) do
    Enum.reduce_while(responses, {:noreply, state}, fn response, {:noreply, state} ->
      case response do
        {:data, _ref, data} ->
          continue_or_stop(decode_frames(state, data))

        {:close, _ref, _code, _reason} ->
          {:halt, eof(state)}

        {:done, _ref} ->
          {:halt, eof(state)}

        _ ->
          {:cont, {:noreply, state}}
      end
    end)
  end

  defp continue_or_stop({:noreply, _state} = ok), do: {:cont, ok}
  defp continue_or_stop({:stop, _, _} = stop), do: {:halt, stop}

  defp decode_frames(state, data) do
    case Mint.WebSocket.decode(state.websocket, data) do
      {:ok, websocket, frames} ->
        Enum.reduce_while(frames, {:noreply, %{state | websocket: websocket}}, &reduce_frame/2)

      {:error, websocket, _reason} ->
        eof(%{state | websocket: websocket})
    end
  end

  defp reduce_frame(frame, {:noreply, state}) do
    case apply_frame(state, frame) do
      {:noreply, state} -> {:cont, {:noreply, state}}
      {:stop, _, _} = stop -> {:halt, stop}
    end
  end

  # Run the frames recovered from the upgrade read through the same
  # codec path as the steady-state loop, before the GenServer starts
  # receiving socket messages.
  defp process_initial_frames(state, frames) do
    Enum.reduce(frames, state, fn frame, state ->
      case apply_frame(state, frame) do
        {:noreply, state} -> state
        {:stop, _reason, state} -> state
      end
    end)
  end

  defp apply_frame(state, {:binary, bytes}) do
    {events, codec} = Codec.feed(state.codec, bytes)
    Enum.each(events, &emit(state.owner, &1))
    {:noreply, %{state | codec: codec}}
  end

  defp apply_frame(state, {:ping, payload}) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, {:pong, payload}),
         {:ok, http} <- Mint.WebSocket.stream_request_body(state.http, state.ref, data) do
      {:noreply, %{state | http: http, websocket: websocket}}
    else
      _ -> {:noreply, state}
    end
  end

  defp apply_frame(state, {:close, _code, _reason}), do: eof(state)
  defp apply_frame(state, _other), do: {:noreply, state}

  defp emit(owner, {:data, bytes}), do: send(owner, {:control_bridge_data, bytes})

  defp emit(_owner, {:error, bytes}) do
    Logger.warning(fn -> "[sandbox.network_policy.k8s] portforward error channel: #{inspect(bytes)}" end)
  end

  defp eof(state) do
    send(state.owner, {:control_bridge_eof})
    {:stop, :normal, state}
  end

  # Public for tests: the upgrade-data accumulation is the regression
  # surface for the dropped-handshake / off-by-two strip bug.
  @doc false
  def __upgrade_acc__, do: %{status: nil, headers: [], data: "", done: false}

  @doc false
  def __merge_upgrade_parts__(acc, parts, ref), do: merge_upgrade_parts(acc, parts, ref)
end
