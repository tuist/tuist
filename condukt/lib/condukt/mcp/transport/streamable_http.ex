defmodule Condukt.MCP.Transport.StreamableHttp do
  @moduledoc false

  # MCP Streamable HTTP transport (2025-03-26 protocol revision).
  #
  # Each client-to-server message is a POST to a single endpoint URL
  # with `Accept: application/json, text/event-stream`. The server
  # responds with one of:
  #
  #   * `200 application/json` containing the JSON-RPC response
  #   * `200 text/event-stream` containing one or more SSE events that
  #     ultimately deliver the JSON-RPC response (and may interleave
  #     server-initiated requests or notifications)
  #   * `202 Accepted` with no body (for notifications and responses)
  #
  # The first response after the `initialize` request may include an
  # `Mcp-Session-Id` header that the client must echo on every
  # subsequent request to keep the session alive.

  use GenServer

  alias Condukt.MCP.{Auth, JSONRPC, SSE}

  defstruct [
    :owner,
    :server,
    :url,
    :static_headers,
    :auth_state,
    :http_request,
    :session_id
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
    {:streamable_http, transport_opts} = server.transport
    url = Keyword.fetch!(transport_opts, :url)
    static_headers = transport_opts |> Keyword.get(:headers, %{}) |> normalize_headers()
    auth_opts = Keyword.take(opts, [:fetch_env, :token_request])

    case Auth.resolve(server.auth, auth_opts) do
      {:ok, auth_headers, auth_state} ->
        state = %__MODULE__{
          owner: owner,
          server: server,
          url: url,
          static_headers: static_headers ++ auth_headers,
          auth_state: auth_state,
          http_request: Keyword.get(opts, :http_request, &default_post_request/3)
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:auth_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:send, envelope}, _from, state) do
    parent = self()
    request_fn = state.http_request
    headers = request_headers(state, envelope)

    # Run the POST in a linked Task so the GenServer can keep
    # receiving inbound messages from the owner. The Task delivers the
    # parsed response back via the `{:streamable_response, ...}`
    # message handled below.
    {:ok, _task} =
      Task.start_link(fn ->
        case request_fn.(state.url, envelope, headers) do
          {:ok, status, resp_headers, body} ->
            send(parent, {:streamable_response, status, resp_headers, body})

          {:error, reason} ->
            send(parent, {:streamable_error, reason})
        end
      end)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast(:stop, state), do: {:stop, :normal, state}

  @impl GenServer
  def handle_info({:streamable_response, status, headers, body}, state) do
    state = maybe_update_session_id(state, headers)

    cond do
      status == 202 ->
        {:noreply, state}

      status in 200..299 ->
        Enum.each(parse_response(headers, body), fn classified ->
          send(state.owner, {:mcp_message, classified})
        end)

        {:noreply, state}

      true ->
        send(state.owner, {:mcp_transport_down, {:http_status, status, body}})
        {:stop, :normal, state}
    end
  end

  def handle_info({:streamable_error, reason}, state) do
    send(state.owner, {:mcp_transport_down, {:http_error, reason}})
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, _state), do: :ok

  defp normalize_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_headers(_), do: []

  defp request_headers(state, _envelope) do
    base = state.static_headers ++ [{"accept", "application/json, text/event-stream"}]

    case state.session_id do
      nil -> base
      id -> [{"mcp-session-id", id} | base]
    end
  end

  defp maybe_update_session_id(state, headers) do
    case header_value(headers, "mcp-session-id") do
      nil -> state
      id -> %{state | session_id: id}
    end
  end

  defp header_value(headers, target) do
    Enum.find_value(headers, fn {name, value} ->
      if String.downcase(to_string(name)) == target, do: to_value(value)
    end)
  end

  defp to_value([single]), do: to_string(single)
  defp to_value(value) when is_binary(value), do: value
  defp to_value(value), do: to_string(value)

  defp parse_response(headers, body) do
    case content_type(headers) do
      "text/event-stream" <> _ -> parse_sse_body(body)
      "application/json" <> _ -> parse_json_body(body)
      _ -> parse_json_body(body)
    end
  end

  defp content_type(headers) do
    case header_value(headers, "content-type") do
      nil -> ""
      value -> String.downcase(value)
    end
  end

  defp parse_sse_body(body) when is_binary(body) do
    {events, state} = SSE.feed(SSE.new(), body)
    {trailing, _state} = SSE.flush(state)

    (events ++ trailing)
    |> Enum.flat_map(&classify_sse_event/1)
  end

  defp parse_sse_body(_), do: []

  defp classify_sse_event(%{event: event, data: data}) when event in ["message", nil, ""] do
    case JSONRPC.decode_and_classify(data) do
      {:error, _} -> []
      classified -> [classified]
    end
  end

  defp classify_sse_event(_), do: []

  defp parse_json_body(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> classify_json(decoded)
      {:error, _} -> []
    end
  end

  defp parse_json_body(body) when is_map(body), do: classify_json(body)
  defp parse_json_body(body) when is_list(body), do: classify_json(body)
  defp parse_json_body(_), do: []

  defp classify_json(items) when is_list(items) do
    Enum.flat_map(items, &single_classification/1)
  end

  defp classify_json(item), do: single_classification(item)

  defp single_classification(item) do
    case JSONRPC.classify(item) do
      {:error, _} -> []
      classified -> [classified]
    end
  end

  defp default_post_request(url, envelope, headers) do
    request_headers = headers ++ [{"content-type", "application/json"}]

    case Req.post(url, headers: request_headers, body: JSONRPC.encode!(envelope), retry: false, decode_body: false) do
      {:ok, %Req.Response{status: status, headers: response_headers, body: body}} ->
        {:ok, status, normalize_response_headers(response_headers), body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_response_headers(headers) when is_map(headers) do
    Enum.flat_map(headers, fn {k, values} ->
      Enum.map(List.wrap(values), fn v -> {to_string(k), to_string(v)} end)
    end)
  end

  defp normalize_response_headers(headers) when is_list(headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end
end
