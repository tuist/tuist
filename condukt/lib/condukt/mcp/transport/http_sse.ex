defmodule Condukt.MCP.Transport.HttpSSE do
  @moduledoc false

  # Legacy MCP HTTP+SSE transport (2024-11 protocol revision).
  #
  # The transport opens a long-lived `text/event-stream` GET on the
  # configured URL. The server publishes the request endpoint URL as
  # the first event (`event: endpoint`, `data: <url>`); subsequent
  # JSON-RPC responses arrive as `event: message` events containing
  # JSON. The client posts requests to the published endpoint URL.

  use GenServer

  alias Condukt.MCP.{Auth, JSONRPC, SSE}

  defstruct [
    :owner,
    :server,
    :base_url,
    :auth_state,
    :static_headers,
    :http_request,
    :sse_task,
    :post_url,
    sse_state: nil,
    pending: []
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def send_message(pid, envelope), do: GenServer.call(pid, {:send, envelope})

  def close(pid) do
    GenServer.cast(pid, :stop)
    :ok
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    server = Keyword.fetch!(opts, :server)
    owner = Keyword.fetch!(opts, :owner)
    {:http_sse, transport_opts} = server.transport
    base_url = Keyword.fetch!(transport_opts, :url)
    static_headers = Keyword.get(transport_opts, :headers, %{}) |> normalize_headers()
    auth_opts = Keyword.take(opts, [:fetch_env, :token_request])

    case Auth.resolve(server.auth, auth_opts) do
      {:ok, auth_headers, auth_state} ->
        all_headers = static_headers ++ auth_headers
        sse_task = start_sse_task(self(), base_url, all_headers, opts)

        state = %__MODULE__{
          owner: owner,
          server: server,
          base_url: base_url,
          static_headers: static_headers,
          auth_state: auth_state,
          http_request: Keyword.get(opts, :http_request, &default_post_request/3),
          sse_task: sse_task,
          sse_state: SSE.new()
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:auth_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:send, envelope}, _from, %{post_url: nil} = state) do
    {:reply, :ok, %{state | pending: state.pending ++ [envelope]}}
  end

  def handle_call({:send, envelope}, _from, state) do
    case post(state, envelope) do
      :ok -> {:reply, :ok, state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  @impl GenServer
  def handle_cast(:stop, state), do: {:stop, :normal, state}

  @impl GenServer
  def handle_info({:sse_chunk, chunk}, state) do
    {events, new_sse_state} = SSE.feed(state.sse_state, chunk)
    state = Enum.reduce(events, %{state | sse_state: new_sse_state}, &handle_event/2)
    {:noreply, state}
  end

  def handle_info(:sse_done, state) do
    send(state.owner, {:mcp_transport_down, :sse_closed})
    {:stop, :normal, state}
  end

  def handle_info({:sse_error, reason}, state) do
    send(state.owner, {:mcp_transport_down, {:sse_error, reason}})
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, task_pid, _reason}, %{sse_task: task_pid} = state) do
    send(state.owner, {:mcp_transport_down, :sse_closed})
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{sse_task: pid}) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp normalize_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_headers(_), do: []

  defp start_sse_task(parent, url, headers, opts) do
    sse_request = Keyword.get(opts, :sse_request, &default_sse_request/4)
    {:ok, pid} = Task.start_link(fn -> sse_request.(parent, url, headers, opts) end)
    pid
  end

  defp default_sse_request(parent, url, headers, _opts) do
    request_headers = headers ++ [{"accept", "text/event-stream"}]

    result =
      Req.get(url,
        headers: request_headers,
        receive_timeout: :infinity,
        retry: false,
        into: fn {:data, chunk}, {req, resp} ->
          send(parent, {:sse_chunk, chunk})
          {:cont, {req, resp}}
        end
      )

    case result do
      {:ok, _resp} -> send(parent, :sse_done)
      {:error, reason} -> send(parent, {:sse_error, reason})
    end
  end

  defp handle_event(%{event: "endpoint", data: data}, state) do
    url = absolute_url(state.base_url, String.trim(data))
    flush_pending(%{state | post_url: url})
  end

  defp handle_event(%{event: event, data: data}, state) when event in ["message", nil] do
    case JSONRPC.decode_and_classify(data) do
      {:error, _} ->
        state

      classified ->
        send(state.owner, {:mcp_message, classified})
        state
    end
  end

  defp handle_event(_other, state), do: state

  defp flush_pending(state) do
    Enum.each(state.pending, &post(state, &1))
    %{state | pending: []}
  end

  defp post(state, envelope) do
    headers = state.static_headers ++ auth_headers(state.auth_state)

    case state.http_request.(state.post_url, envelope, headers) do
      {:ok, status} when status in 200..299 -> :ok
      {:ok, status} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_post_request(url, envelope, headers) do
    case Req.post(url, headers: headers, json: envelope, retry: false) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  end

  defp auth_headers(%{kind: :bearer, value: value}) do
    [{"authorization", "Bearer " <> value}]
  end

  defp auth_headers(%{kind: :client_credentials, value: value}) when is_binary(value) do
    [{"authorization", "Bearer " <> value}]
  end

  defp auth_headers(_), do: []

  defp absolute_url(base, candidate) do
    case URI.parse(candidate) do
      %URI{scheme: scheme} when is_binary(scheme) -> candidate
      _ -> URI.merge(base, candidate) |> URI.to_string()
    end
  end
end
