defmodule Atlas.MCP.Transport.StreamableHTTP do
  @moduledoc """
  Stateless MCP Streamable HTTP transport.

  Requests dispatch through `Atlas.MCP.Server.handle_message/2` so Atlas can
  hoist upstream tools into `tools/list` and proxy `tools/call`. Responses are
  returned inline, without session IDs or a server-initiated SSE stream. GET
  and DELETE return 405 as permitted by Streamable HTTP. Legacy session
  headers are ignored so existing clients survive replicas and restarts.
  """

  @behaviour Plug

  import Plug.Conn

  alias Plug.Conn.Unfetched

  @invalid_request -32_600

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

  defp route_method(%Plug.Conn{method: "POST"} = conn, opts), do: handle_post(conn, opts)

  defp route_method(conn, _opts) do
    conn
    |> put_resp_header("allow", "POST")
    |> json_error(405, "Method not allowed")
  end

  defp handle_post(conn, opts) do
    case read_request(conn) do
      {:ok, request, conn} when is_map(request) ->
        if notification?(request) do
          send_resp(conn, 202, "")
        else
          conn
          |> json_response(200, handle_message(conn, request, opts))
        end

      {:ok, _request, conn} ->
        json_error(conn, 400, "Invalid JSON-RPC request")

      {:error, message} ->
        json_error(conn, 400, message)
    end
  end

  defp read_request(%{body_params: params} = conn)
       when is_map(params) and not is_struct(params, Unfetched) and params != %{} do
    {:ok, params, conn}
  end

  defp read_request(conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, request} <- decode_json(body) do
      {:ok, request, conn}
    end
  end

  defp notification?(request), do: Map.has_key?(request, "method") and not Map.has_key?(request, "id")

  # The proxy's privileged identity header is allowed only on this interface.
  defp handle_message(conn, request, opts) do
    conn
    |> assign(:audit_interface, "mcp")
    |> opts[:server].handle_message(request)
  end

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

  defp json_error(conn, status, message), do: json_response(conn, status, %{"error" => message})

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
      _ -> :ok
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
        host = host |> String.trim() |> String.downcase() |> String.trim_trailing(".")
        origin_base = "#{String.downcase(scheme)}://#{host}"

        Enum.any?(allowed, fn entry ->
          normalized = String.downcase(entry)
          normalized == origin_base || normalized == origin || normalized == host
        end)

      _ ->
        false
    end
  end
end
