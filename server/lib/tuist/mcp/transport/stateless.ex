defmodule Tuist.MCP.Transport.Stateless do
  @moduledoc """
  Serves the stateless 2026-07-28 MCP request lifecycle while the existing
  session-based transport continues to serve older clients.
  """

  import Plug.Conn

  alias Tuist.MCP.Events
  alias Tuist.MCP.Server
  alias Tuist.MCP.Tool

  @protocol_version "2026-07-28"
  @server_info_key "io.modelcontextprotocol/serverInfo"
  @version_key "io.modelcontextprotocol/protocolVersion"

  def call(%Plug.Conn{method: "POST"} = conn, opts) do
    if valid_origin?(conn) do
      handle_request(conn, opts)
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, JSON.encode!(error(nil, -32_600, "Forbidden origin")))
    end
  end

  def call(conn, _opts), do: send_resp(conn, 405, "Method not allowed")

  defp handle_request(conn, opts) do
    request = conn.body_params
    request_id = if is_map(request), do: Map.get(request, "id")

    response =
      case validate_request(conn, request) do
        :ok ->
          dispatch(conn, request, opts)

        {:error, -32_022, message} ->
          error(request_id, -32_022, message, %{
            "supported" => [@protocol_version, "2025-06-18", "2025-03-26"],
            "requested" => get_in(request, ["params", "_meta", @version_key])
          })

        {:error, code, message} ->
          error(request_id, code, message)
      end

    if response do
      status = response_status(response)

      if status == 200 do
        conn
        |> put_resp_content_type("text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> send_resp(status, "event: message\ndata: #{JSON.encode!(response)}\n\n")
      else
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, JSON.encode!(response))
      end
    else
      send_resp(conn, 202, "")
    end
  end

  defp valid_origin?(conn) do
    case get_req_header(conn, "origin") do
      [] -> true
      [origin] -> EMCP.Transport.StreamableHTTP.origin_allowed?(origin, [Tuist.Environment.app_url()])
      _ -> false
    end
  end

  defp validate_request(conn, %{"jsonrpc" => "2.0", "method" => method, "params" => params})
       when is_binary(method) and is_map(params) do
    header_version = get_req_header(conn, "mcp-protocol-version")
    body_version = get_in(params, ["_meta", @version_key])
    header_method = get_req_header(conn, "mcp-method")
    header_name = get_req_header(conn, "mcp-name")
    expected_name = request_name(method, params)

    with :ok <- validate_version_headers(header_version, body_version, header_method) do
      validate_method_headers(header_method, method, header_name, expected_name)
    end
  end

  defp validate_request(_conn, _request), do: {:error, -32_600, "Invalid Request"}

  defp validate_version_headers(header_version, body_version, header_method) do
    cond do
      header_version == [] or header_method == [] ->
        {:error, -32_020, "Required MCP request header is missing"}

      header_version != [body_version] ->
        {:error, -32_020, "Protocol version header does not match the request"}

      body_version != @protocol_version ->
        {:error, -32_022, "Unsupported protocol version"}

      true ->
        :ok
    end
  end

  defp validate_method_headers(header_method, method, header_name, expected_name) do
    cond do
      header_method != [method] -> {:error, -32_020, "Mcp-Method does not match the request"}
      expected_name && header_name != [expected_name] -> {:error, -32_020, "Mcp-Name does not match the request"}
      true -> :ok
    end
  end

  defp response_status(%{"error" => %{"code" => code}}) when code in [-32_022, -32_020], do: 400
  defp response_status(%{"error" => %{"code" => -32_601}}), do: 404
  defp response_status(_response), do: 200

  defp request_name(method, params) when method in ["tools/call", "prompts/get"], do: params["name"]
  defp request_name("resources/read", params), do: params["uri"]
  defp request_name(_method, _params), do: nil

  defp dispatch(_conn, %{"id" => id, "method" => "server/discover"}, _opts) do
    server = Server.server()

    result(id, %{
      "supportedVersions" => [@protocol_version],
      "capabilities" => %{"tools" => %{}, "prompts" => %{}, "events" => %{}},
      "instructions" => server.instructions,
      "ttlMs" => 0,
      "cacheScope" => "private"
    })
  end

  defp dispatch(_conn, %{"id" => id, "method" => "events/list"}, _opts) do
    result(id, Map.merge(Events.list(), %{"ttlMs" => 0, "cacheScope" => "private"}))
  end

  defp dispatch(conn, %{"id" => id, "method" => "events/subscribe", "params" => params}, _opts) do
    event_result(id, Events.subscribe(conn, params))
  end

  defp dispatch(conn, %{"id" => id, "method" => "events/unsubscribe", "params" => params}, _opts) do
    event_result(id, Events.unsubscribe(conn, params))
  end

  defp dispatch(conn, %{"id" => _id, "method" => method} = request, opts) do
    server = opts |> Keyword.fetch!(:server) |> apply(:server, [])

    response = EMCP.Server.handle_message(server, conn, request)

    case_result =
      case response do
        %{"result" => result} = response when is_map(result) ->
          result =
            result
            |> maybe_add_tool_descriptors(method, server)
            |> maybe_add_cache_hints(method)

          Map.put(response, "result", complete_result(result))

        other ->
          other
      end

    stamp_server_info(case_result, server)
  end

  defp dispatch(_conn, _request, _opts), do: nil

  defp maybe_add_tool_descriptors(%{"tools" => tools} = result, "tools/list", server) do
    descriptors =
      Enum.map(tools, fn %{"name" => name} = tool ->
        case Map.fetch(server.tools, name) do
          {:ok, module} -> Tool.descriptor(module)
          :error -> tool
        end
      end)

    Map.put(result, "tools", descriptors)
  end

  defp maybe_add_tool_descriptors(result, _method, _server), do: result

  defp maybe_add_cache_hints(result, method)
       when method in ["tools/list", "prompts/list", "resources/list", "resources/templates/list", "resources/read"] do
    Map.merge(result, %{"ttlMs" => 0, "cacheScope" => "private"})
  end

  defp maybe_add_cache_hints(result, _method), do: result

  defp complete_result(result), do: Map.put(result, "resultType", "complete")

  defp event_result(id, {:ok, value}), do: result(id, value)
  defp event_result(id, {:error, code, message}), do: error(id, code, message)
  defp event_result(id, {:error, code, message, data}), do: error(id, code, message, data)

  defp result(id, data) do
    stamp_server_info(%{"jsonrpc" => "2.0", "id" => id, "result" => complete_result(data)}, Server.server())
  end

  defp error(id, code, message, data \\ nil) do
    details = %{"code" => code, "message" => message}
    details = if data, do: Map.put(details, "data", data), else: details

    stamp_server_info(
      %{"jsonrpc" => "2.0", "id" => id, "error" => details},
      Server.server()
    )
  end

  defp stamp_server_info(nil, _server), do: nil

  defp stamp_server_info(response, server) do
    case response do
      %{"result" => result} when is_map(result) ->
        meta = Map.get(result, "_meta", %{})
        put_in(response, ["result", "_meta"], Map.put(meta, @server_info_key, server_info(server)))

      _ ->
        response
    end
  end

  defp server_info(server), do: %{"name" => server.name, "version" => server.version}
end
