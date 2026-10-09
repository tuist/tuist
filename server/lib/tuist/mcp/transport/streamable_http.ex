defmodule Tuist.MCP.Transport.StreamableHTTP do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias EMCP.Transport.StreamableHTTP, as: EMCPTransport
  alias Tuist.MCP.Tool
  alias Tuist.MCP.Transport.Stateless

  @latest_protocol_version "2026-07-28"
  @legacy_protocol_versions ["2025-06-18", "2025-03-26"]
  @supported_protocol_versions [@latest_protocol_version | @legacy_protocol_versions]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    if modern_request?(conn) do
      Stateless.call(conn, opts)
    else
      call_legacy(conn, opts)
    end
  end

  defp modern_request?(conn) do
    get_req_header(conn, "mcp-protocol-version") == [@latest_protocol_version] or
      case conn.body_params do
        %{"params" => %{"_meta" => %{"io.modelcontextprotocol/protocolVersion" => version}}}
        when is_binary(version) ->
          true

        _ ->
          false
      end
  end

  defp call_legacy(conn, opts) do
    with :ok <- validate_origin(conn, opts),
         :ok <- validate_http_method(conn),
         :ok <- validate_request(conn.body_params),
         :ok <- validate_method_params(conn.body_params),
         :ok <- validate_version(conn) do
      dispatch(conn, Keyword.fetch!(opts, :server).server())
    else
      {:error, status, code, message, data} ->
        error = %{"code" => code, "message" => message}
        error = if data, do: Map.put(error, "data", data), else: error
        id = if is_map(conn.body_params), do: Map.get(conn.body_params, "id")
        respond(conn, status, %{"jsonrpc" => "2.0", "id" => id, "error" => error})
    end
  end

  defp validate_origin(conn, opts) do
    origins = Keyword.get_lazy(opts, :allowed_origins, fn -> [Tuist.Environment.app_url(route_type: :app)] end)

    case get_req_header(conn, "origin") do
      [] ->
        :ok

      [origin] ->
        if EMCPTransport.origin_allowed?(origin, origins),
          do: :ok,
          else: failure(403, -32_600, "Invalid origin")

      _ ->
        failure(403, -32_600, "Invalid origin")
    end
  end

  defp validate_http_method(%{method: "POST"}), do: :ok
  defp validate_http_method(_conn), do: failure(405, -32_600, "Method not allowed")

  defp validate_request(%{"jsonrpc" => "2.0", "method" => method} = request) when is_binary(method) do
    if (not Map.has_key?(request, "id") or is_binary(request["id"]) or is_integer(request["id"])) and
         is_map(Map.get(request, "params", %{})) do
      :ok
    else
      failure(400, -32_600, "Invalid request")
    end
  end

  defp validate_request(_request), do: failure(400, -32_600, "Invalid request")

  defp validate_method_params(%{"method" => method} = request)
       when method in ["tools/call", "prompts/get", "resources/read"] do
    key = if method == "resources/read", do: "uri", else: "name"
    params = Map.get(request, "params", %{})

    if is_binary(params[key]) and is_map(Map.get(params, "arguments", %{})),
      do: :ok,
      else: failure(400, -32_602, "Missing or invalid method parameters")
  end

  defp validate_method_params(_request), do: :ok

  defp validate_version(conn) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] ->
        :ok

      [version] when version in @legacy_protocol_versions ->
        :ok

      [version] ->
        {:error, 400, -32_022, "Unsupported protocol version",
         %{"supported" => @supported_protocol_versions, "requested" => version}}

      _ ->
        failure(400, -32_020, "Malformed protocol version header")
    end
  end

  defp dispatch(conn, server) do
    request = conn.body_params

    case EMCP.Server.handle_message(server, conn, request) do
      nil ->
        send_resp(conn, 202, "")

      %{"result" => result} = response ->
        respond(conn, 200, Map.put(response, "result", decorate_result(result, request, server)))

      %{"error" => %{"code" => code}} = response ->
        status = if code in [-32_600, -32_602], do: 400, else: 200
        respond(conn, status, response)
    end
  end

  defp decorate_result(result, %{"method" => "initialize"} = request, _server) do
    requested = get_in(request, ["params", "protocolVersion"])
    version = if requested in @legacy_protocol_versions, do: requested, else: hd(@legacy_protocol_versions)

    result
    |> Map.put("protocolVersion", version)
    |> Map.put("capabilities", %{"tools" => %{}, "prompts" => %{}})
  end

  defp decorate_result(result, %{"method" => "tools/list"}, server) do
    Map.put(result, "tools", Enum.map(result["tools"], &Tool.descriptor(Map.fetch!(server.tools, &1["name"]))))
  end

  defp decorate_result(result, _request, _server), do: result

  defp failure(status, code, message), do: {:error, status, code, message, nil}

  defp respond(conn, status, response) do
    conn = if status == 405, do: put_resp_header(conn, "allow", "POST"), else: conn
    conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(response)) |> halt()
  end
end
