defmodule Atlas.MCP.Transport.StreamableHTTP do
  @moduledoc """
  Atlas MCP Streamable HTTP transport.

  This mirrors EMCP's Streamable HTTP transport, but dispatches requests through
  `Atlas.MCP.Server.handle_message/2` so Atlas can hoist configured upstream
  MCP tools into `tools/list` and dispatch proxied `tools/call` requests.
  """

  @behaviour Plug

  import Plug.Conn

  alias Plug.Conn.Unfetched

  @default_session_ttl to_timeout(minute: 10)
  @default_keepalive_interval to_timeout(second: 30)
  @invalid_request -32_600

  @doc "Send a notification to a specific session's SSE connection."
  def notify(store, session_id, message) do
    case store.get_pid(session_id) do
      nil ->
        {:error, :no_sse_connection}

      pid ->
        send(pid, {:sse_message, JSON.encode!(message)})
        :ok
    end
  end

  @doc "Broadcast a notification to all sessions with active SSE connections."
  def broadcast(store, message) do
    encoded = JSON.encode!(message)

    store.all_sessions()
    |> Enum.each(fn
      %EMCP.Session{pid: pid} when is_pid(pid) ->
        send(pid, {:sse_message, encoded})

      _ ->
        :ok
    end)
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    with :ok <- validate_protocol_version(conn, opts),
         :ok <- validate_origin(conn, opts) do
      route_method(conn, opts)
    else
      {:unsupported_protocol_version, version} -> unsupported_protocol_version(conn, version, opts)
      {:error, conn} -> conn
    end
  end

  # Clients that speak a revision we do not support are told so up front, rather than
  # receiving responses shaped for a protocol they cannot interpret.
  defp validate_protocol_version(conn, opts) do
    supported = supported_protocol_versions(opts)

    case get_req_header(conn, "mcp-protocol-version") do
      [] ->
        :ok

      [version] when is_binary(version) ->
        if version in supported, do: :ok, else: {:unsupported_protocol_version, version}

      versions ->
        {:unsupported_protocol_version, Enum.join(versions, ", ")}
    end
  end

  defp unsupported_protocol_version(conn, version, opts) do
    conn
    |> json_response(400, %{
      "jsonrpc" => "2.0",
      "error" => %{
        "code" => @invalid_request,
        "message" => "Unsupported MCP protocol version: #{version}",
        "data" => %{"supported" => supported_protocol_versions(opts)}
      }
    })
    |> halt()
  end

  defp supported_protocol_versions(opts), do: opts[:server].supported_protocol_versions()

  defp route_method(%Plug.Conn{method: "GET"} = conn, opts), do: handle_get(conn, opts)
  defp route_method(%Plug.Conn{method: "POST"} = conn, opts), do: handle_post(conn, opts)
  defp route_method(%Plug.Conn{method: "DELETE"} = conn, opts), do: handle_delete(conn, opts)
  defp route_method(conn, _opts), do: json_error(conn, 405, "Method not allowed")

  defp handle_get(conn, opts) do
    store = get_store(opts)

    if accepts_event_stream?(conn) do
      with_session(conn, store, opts, fn session_id ->
        store.register(session_id, self())

        conn =
          conn
          |> put_resp_content_type("text/event-stream")
          |> put_resp_header("cache-control", "no-cache")
          |> send_chunked(200)

        try do
          sse_loop(conn, session_id, 0)
        after
          store.unregister(session_id)
        end
      end)
    else
      json_error(conn, 406, "Accept header must include text/event-stream")
    end
  end

  defp sse_loop(conn, session_id, event_id) do
    receive do
      {:sse_message, data} ->
        case chunk(conn, sse_encode(data, event_id)) do
          {:ok, conn} -> sse_loop(conn, session_id, event_id + 1)
          {:error, _} -> conn
        end

      :close_sse ->
        conn
    after
      keepalive_interval() ->
        case chunk(conn, sse_keepalive()) do
          {:ok, conn} -> sse_loop(conn, session_id, event_id)
          {:error, _} -> conn
        end
    end
  end

  defp handle_post(conn, opts) do
    case read_request(conn) do
      {:ok, request, conn} ->
        if initialize?(request) do
          initialize_session(conn, request, opts)
        else
          store = get_store(opts)

          with_session(conn, store, opts, fn session_id ->
            dispatch(conn, request, session_id, opts)
          end)
        end

      {:error, message} ->
        json_error(conn, 400, message)
    end
  end

  defp initialize_session(conn, request, opts) do
    store = get_store(opts)
    session_id = generate_session_id()
    store.store(session_id)

    conn
    |> put_resp_header("mcp-session-id", session_id)
    |> json_response(200, handle_message(conn, request, opts))
  end

  defp dispatch(conn, request, _session_id, opts) do
    if notification?(request) do
      send_resp(conn, 202, "")
    else
      response = handle_message(conn, request, opts)
      json_response(conn, 200, response)
    end
  end

  defp handle_delete(conn, opts) do
    store = get_store(opts)

    with_session(conn, store, opts, fn session_id ->
      case store.get_pid(session_id) do
        pid when is_pid(pid) -> send(pid, :close_sse)
        nil -> :ok
      end

      store.delete(session_id)
      json_response(conn, 200, %{"success" => true})
    end)
  end

  defp with_session(conn, store, opts, fun) do
    with {:ok, session_id} <- require_session_id(conn),
         :ok <- validate_session(store, session_id, opts) do
      fun.(session_id)
    else
      {:error, status, message} -> json_error(conn, status, message)
    end
  end

  defp require_session_id(conn) do
    case get_req_header(conn, "mcp-session-id") do
      [session_id] -> {:ok, session_id}
      _ -> {:error, 400, "Missing session ID"}
    end
  end

  defp validate_session(store, session_id, opts) do
    recreate? = Keyword.get(opts, :recreate_missing_session, true)

    case store.lookup(session_id) do
      nil -> handle_missing_session(store, session_id, recreate?)
      session -> validate_existing_session(store, session_id, session, recreate?)
    end
  end

  defp validate_existing_session(store, session_id, session, recreate?) do
    if session_expired?(session) do
      handle_expired_session(store, session_id, recreate?)
    else
      store.touch(session_id)
      :ok
    end
  end

  defp handle_missing_session(store, session_id, true) do
    store.store(session_id)
    :ok
  end

  defp handle_missing_session(_store, _session_id, false), do: {:error, 404, "Session not found"}

  defp handle_expired_session(store, session_id, true) do
    store.store(session_id)
    :ok
  end

  defp handle_expired_session(store, session_id, false) do
    store.delete(session_id)
    {:error, 404, "Session expired"}
  end

  defp session_expired?(%EMCP.Session{last_seen: last_seen}) do
    System.monotonic_time(:millisecond) - last_seen > session_ttl()
  end

  defp session_expired?(nil), do: true

  defp generate_session_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  defp read_request(%{body_params: %Unfetched{}} = conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, request} <- decode_json(body) do
      {:ok, request, conn}
    end
  end

  defp read_request(%{body_params: params} = conn) when is_map(params) and params != %{} do
    {:ok, params, conn}
  end

  defp read_request(conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, request} <- decode_json(body) do
      {:ok, request, conn}
    end
  end

  defp initialize?(request), do: request["method"] == "initialize"

  defp notification?(request), do: Map.has_key?(request, "method") and not Map.has_key?(request, "id")

  # Names the interface rather than leaving it to the audit default, so callers
  # that gate on it (the proxy's Atlas identity header) can allowlist it.
  defp handle_message(conn, request, opts) do
    conn
    |> assign(:audit_interface, "mcp")
    |> opts[:server].handle_message(request)
  end

  defp get_store(opts) do
    opts[:server].server().session_store
  end

  defp accepts_event_stream?(conn) do
    conn
    |> get_req_header("accept")
    |> List.first("")
    |> String.contains?("text/event-stream")
  end

  defp sse_encode(data, id), do: "id: #{id}\nevent: message\ndata: #{data}\n\n"
  defp sse_keepalive, do: ": keepalive\n\n"

  defp decode_json(body) do
    case JSON.decode(body) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, "Invalid JSON"}
    end
  end

  defp json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end

  defp json_error(conn, status, message) do
    json_response(conn, status, %{"error" => message})
  end

  defp validate_origin(conn, opts) do
    allowed = Keyword.get(opts, :allowed_origins, [])
    should_validate_origin? = Keyword.get(opts, :validate_origin, false)

    with true <- should_validate_origin?,
         {:ok, origin} <- get_origin_header(conn),
         false <- origin_allowed?(origin, allowed) do
      {:error,
       json_response(conn, 403, %{
         "jsonrpc" => "2.0",
         "error" => %{"code" => @invalid_request, "message" => "Forbidden origin"}
       })}
    else
      _ ->
        :ok
    end
  end

  defp get_origin_header(conn) do
    case get_req_header(conn, "origin") do
      [origin] -> {:ok, origin}
      [] -> :missing_header
    end
  end

  @doc false
  def origin_allowed?(origin, allowed) do
    case URI.parse(origin) do
      %URI{scheme: scheme, host: host} when is_binary(scheme) and is_binary(host) ->
        host =
          host
          |> String.trim()
          |> String.downcase()
          |> String.trim_trailing(".")

        origin_base = "#{String.downcase(scheme)}://#{host}"

        Enum.any?(allowed, fn entry ->
          normalized = String.downcase(entry)
          normalized == origin_base || normalized == origin || normalized == host
        end)

      _ ->
        false
    end
  end

  defp session_ttl do
    Application.get_env(:emcp, :session_ttl, @default_session_ttl)
  end

  defp keepalive_interval do
    Application.get_env(:emcp, :keepalive_interval, @default_keepalive_interval)
  end
end
