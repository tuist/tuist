defmodule Tuist.MCP.Transport.StreamableHTTP do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Tuist.MCP.Tool

  @latest_protocol_version "2026-07-28"
  @legacy_protocol_versions ["2025-06-18", "2025-03-26"]
  @supported_protocol_versions [@latest_protocol_version | @legacy_protocol_versions]
  @version_key "io.modelcontextprotocol/protocolVersion"
  @capabilities_key "io.modelcontextprotocol/clientCapabilities"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    with :ok <- validate_origin(conn, opts),
         :ok <- validate_http_method(conn),
         :ok <- validate_request(conn.body_params),
         :ok <- validate_method_params(conn.body_params),
         :ok <- validate_version(conn),
         :ok <- validate_metadata(conn) do
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
    case get_req_header(conn, "origin") do
      [] ->
        :ok

      [origin] ->
        origins = Keyword.get_lazy(opts, :allowed_origins, fn -> [Tuist.Environment.app_url(route_type: :app)] end)
        if origin in origins, do: :ok, else: failure(403, -32_600, "Invalid origin")

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
    arguments = Map.get(params, "arguments", %{})

    if is_binary(params[key]) and is_map(arguments),
      do: :ok,
      else: failure(400, -32_602, "Missing or invalid method parameters")
  end

  defp validate_method_params(_request), do: :ok

  defp validate_version(conn) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] -> :ok
      [version] when version in @supported_protocol_versions -> :ok
      [version] -> unsupported_version(version)
      _ -> failure(400, -32_020, "Malformed protocol version header")
    end
  end

  defp validate_metadata(conn) do
    meta = get_in(conn.body_params, ["params", "_meta"])
    header = get_req_header(conn, "mcp-protocol-version")

    if header == [@latest_protocol_version] or (is_map(meta) and Map.has_key?(meta, @version_key)) do
      validate_modern_metadata(conn, meta)
    else
      :ok
    end
  end

  defp validate_modern_metadata(conn, meta) when is_map(meta) do
    version = Map.get(meta, @version_key)

    cond do
      not Map.has_key?(conn.body_params, "id") ->
        failure(400, -32_600, "Notifications are not supported for this protocol version")

      not is_binary(version) or not is_map(Map.get(meta, @capabilities_key)) ->
        failure(400, -32_602, "Missing or invalid request metadata")

      get_req_header(conn, "mcp-protocol-version") != [version] ->
        failure(400, -32_020, "Protocol version header does not match request metadata")

      version != @latest_protocol_version ->
        unsupported_version(version)

      true ->
        validate_method_headers(conn)
    end
  end

  defp validate_modern_metadata(_conn, _meta), do: failure(400, -32_602, "Missing request metadata")

  defp validate_method_headers(conn) do
    with :ok <- matching_header(conn, "mcp-method", conn.body_params["method"]) do
      case conn.body_params["method"] do
        method when method in ["tools/call", "prompts/get"] ->
          matching_header(conn, "mcp-name", get_in(conn.body_params, ["params", "name"]))

        "resources/read" ->
          matching_header(conn, "mcp-name", get_in(conn.body_params, ["params", "uri"]))

        _ ->
          :ok
      end
    end
  end

  defp matching_header(conn, header, expected) do
    case get_req_header(conn, header) do
      [value] when is_binary(expected) ->
        if decode_header(value) == {:ok, expected},
          do: :ok,
          else: failure(400, -32_020, "Header mismatch: #{header}")

      _ ->
        failure(400, -32_020, "Missing or malformed header: #{header}")
    end
  end

  defp decode_header("=?base64?" <> encoded) do
    if String.ends_with?(encoded, "?="),
      do: Base.decode64(binary_part(encoded, 0, byte_size(encoded) - 2)),
      else: :error
  end

  defp decode_header(value) do
    if String.trim(value) == value and Regex.match?(~r/^[\x20-\x7E]+$/, value), do: {:ok, value}, else: :error
  end

  defp dispatch(conn, server) do
    request = conn.body_params
    modern? = get_req_header(conn, "mcp-protocol-version") == [@latest_protocol_version]

    response =
      case request["method"] do
        "server/discover" when modern? ->
          %{
            "jsonrpc" => "2.0",
            "id" => request["id"],
            "result" => %{
              "supportedVersions" => @supported_protocol_versions,
              "capabilities" => capabilities(),
              "instructions" => server.instructions
            }
          }

        "initialize" when modern? ->
          %{"jsonrpc" => "2.0", "id" => request["id"], "error" => %{"code" => -32_601, "message" => "Method not found"}}

        _ ->
          EMCP.Server.handle_message(server, conn, request)
      end

    case response do
      nil ->
        send_resp(conn, 202, "")

      %{"result" => result} ->
        result = decorate_result(result, request, server, modern?)
        respond(conn, 200, Map.put(response, "result", result))

      %{"error" => %{"code" => code}} ->
        respond(conn, error_status(code, modern?), response)
    end
  end

  defp error_status(-32_601, true), do: 404
  defp error_status(code, _modern?) when code in [-32_600, -32_602], do: 400
  defp error_status(_code, _modern?), do: 200

  defp decorate_result(result, request, server, modern?) do
    result =
      case request["method"] do
        "initialize" ->
          requested = get_in(request, ["params", "protocolVersion"])
          version = if requested in @legacy_protocol_versions, do: requested, else: hd(@legacy_protocol_versions)
          result |> Map.put("protocolVersion", version) |> Map.put("capabilities", capabilities())

        "tools/list" ->
          Map.put(
            result,
            "tools",
            Enum.map(result["tools"], fn tool ->
              Tool.descriptor(Map.fetch!(server.tools, tool["name"]))
            end)
          )

        _ ->
          result
      end

    if modern? do
      info = %{"name" => server.name, "version" => server.version}
      info = if server.title, do: Map.put(info, "title", server.title), else: info

      result
      |> Map.put("resultType", "complete")
      |> Map.update(
        "_meta",
        %{"io.modelcontextprotocol/serverInfo" => info},
        &Map.put(&1, "io.modelcontextprotocol/serverInfo", info)
      )
    else
      result
    end
  end

  # These catalogs are static within a release; there is no subscription stream.
  defp capabilities, do: %{"tools" => %{}, "prompts" => %{}}

  defp unsupported_version(version),
    do:
      {:error, 400, -32_022, "Unsupported protocol version",
       %{"supported" => @supported_protocol_versions, "requested" => version}}

  defp failure(status, code, message), do: {:error, status, code, message, nil}

  defp respond(conn, status, response) do
    conn = if status == 405, do: put_resp_header(conn, "allow", "POST"), else: conn
    conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(response)) |> halt()
  end
end
