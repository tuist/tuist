defmodule TuistWeb.Plugs.MCPPlug do
  @moduledoc """
  Wraps the Hermes StreamableHTTP plug to return plain JSON for POST requests
  instead of opening an SSE stream that never closes.

  The Hermes plug opens an SSE stream for POST responses when the client has a
  GET SSE connection, but never closes the stream after delivering the response.
  This causes MCP clients to hang indefinitely. Since the MCP spec allows servers
  to respond with either JSON or SSE for POST requests, we always use JSON.

  GET and DELETE requests are delegated to the Hermes plug unchanged.

  See: https://github.com/cloudwalk/hermes-mcp/issues/244
  """

  @behaviour Plug

  import Plug.Conn

  alias Hermes.MCP.Error
  alias Hermes.MCP.ID
  alias Hermes.MCP.Message
  alias Hermes.Server.Transport.StreamableHTTP
  alias Hermes.Server.Transport.StreamableHTTP.Plug, as: HermesPlug
  alias Plug.Conn.Unfetched

  require Message

  @session_header "mcp-session-id"

  @impl Plug
  def init(opts), do: HermesPlug.init(opts)

  @impl Plug
  def call(%Plug.Conn{method: "POST"} = conn, opts), do: handle_post(conn, opts)
  def call(conn, opts), do: HermesPlug.call(conn, opts)

  defp handle_post(conn, %{transport: transport, timeout: timeout}) do
    with {:ok, body, conn} <- fetch_body(conn, timeout),
         {:ok, message} <- decode_message(body) do
      session_id = extract_session_id(conn)
      context = build_context(conn)

      conn
      |> maybe_put_session_header(session_id)
      |> dispatch(transport, session_id, message, context)
    else
      {:error, :invalid_json} ->
        send_error(conn, Error.protocol(:parse_error, %{message: "Invalid JSON"}), nil)

      {:error, reason} ->
        send_error(conn, Error.protocol(:parse_error, %{reason: reason}), nil)
    end
  end

  defp dispatch(conn, transport, session_id, message, context) do
    if Message.is_request(message),
      do: handle_request(conn, transport, session_id, message, context),
      else: handle_notification(conn, transport, session_id, message, context)
  end

  defp handle_request(conn, transport, session_id, message, context) do
    case StreamableHTTP.handle_message(transport, session_id, message, context) do
      {:ok, response} ->
        send_json(conn, 200, response)

      {:error, %Error{} = error} ->
        send_error(conn, error, message["id"])

      {:error, reason} ->
        send_error(conn, Error.protocol(:internal_error, %{reason: reason}), message["id"])
    end
  end

  defp handle_notification(conn, transport, session_id, message, context) do
    StreamableHTTP.handle_message(transport, session_id, message, context)
    send_json(conn, 202, "{}")
  end

  defp fetch_body(%{body_params: %Unfetched{}} = conn, timeout) do
    Plug.Conn.read_body(conn, read_timeout: timeout)
  end

  defp fetch_body(%{body_params: body} = conn, _timeout), do: {:ok, body, conn}

  defp decode_message(body) when is_binary(body) do
    case Message.decode(body) do
      {:ok, [message]} -> {:ok, message}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp decode_message(body) when is_map(body) do
    case Message.validate_message(body) do
      {:ok, message} -> {:ok, message}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp extract_session_id(conn) do
    case get_req_header(conn, @session_header) do
      [id] when id != "" -> id
      _ -> ID.generate_session_id()
    end
  end

  defp maybe_put_session_header(conn, session_id) do
    if get_req_header(conn, @session_header) == [],
      do: put_resp_header(conn, @session_header, session_id),
      else: conn
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp send_error(conn, %Error{} = error, id) do
    {:ok, body} = Error.to_json_rpc(error, id || ID.generate_error_id())
    send_json(conn, 400, body)
  end

  defp build_context(conn) do
    %{
      assigns: conn.assigns,
      type: :http,
      req_headers: conn.req_headers,
      query_params: safe_query_params(conn),
      remote_ip: conn.remote_ip,
      scheme: conn.scheme,
      host: conn.host,
      port: conn.port,
      request_path: conn.request_path
    }
  end

  defp safe_query_params(%{query_params: %Unfetched{}}), do: nil
  defp safe_query_params(%{query_params: params}), do: params
end
