defmodule Tuist.MCP.Transport.StreamableHTTP do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias EMCP.Transport.StreamableHTTP

  @latest_protocol_version "2025-06-18"
  @supported_protocol_versions [@latest_protocol_version, "2025-03-26"]

  # Only these methods carry anything we decorate. Every other method (notably
  # `tools/call`, the hot path, whose bodies carry full structuredContent payloads)
  # is passed through without decoding and re-encoding the response body.
  @decorated_methods ["initialize", "tools/list"]

  @impl Plug
  def init(opts), do: StreamableHTTP.init(opts)

  @impl Plug
  def call(conn, opts) do
    case validate_protocol_version_header(conn) do
      :ok ->
        negotiated_protocol_version = negotiated_protocol_version(conn)
        method = request_method(conn)

        conn
        |> register_before_send(&decorate_response(&1, opts, negotiated_protocol_version, method))
        |> StreamableHTTP.call(opts)

      {:error, version} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          JSON.encode!(%{
            "error" => "Unsupported MCP protocol version: #{version}",
            "supported" => @supported_protocol_versions
          })
        )
        |> halt()
    end
  end

  defp validate_protocol_version_header(conn) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] -> :ok
      [version] when version in @supported_protocol_versions -> :ok
      [version] -> {:error, version}
      versions -> {:error, Enum.join(versions, ", ")}
    end
  end

  defp negotiated_protocol_version(%Plug.Conn{
         body_params: %{"method" => "initialize", "params" => %{"protocolVersion" => requested_version}}
       }) do
    if requested_version in @supported_protocol_versions,
      do: requested_version,
      else: @latest_protocol_version
  end

  defp negotiated_protocol_version(_conn), do: nil

  defp request_method(%Plug.Conn{body_params: %{"method" => method}}) when is_binary(method), do: method
  defp request_method(_conn), do: nil

  # An unrecognized method (a batch request, or a body Plug did not parse) falls back
  # to decorating, so we can never silently stop attaching output schemas.
  defp decorates_response?(nil), do: true
  defp decorates_response?(method), do: method in @decorated_methods

  defp decorate_response(%Plug.Conn{resp_body: body} = conn, opts, negotiated_protocol_version, method)
       when not is_nil(body) do
    if decorates_response?(method) do
      decode_and_decorate(conn, body, opts, negotiated_protocol_version)
    else
      conn
    end
  end

  defp decorate_response(conn, _opts, _negotiated_protocol_version, _method), do: conn

  defp decode_and_decorate(conn, body, opts, negotiated_protocol_version) do
    case body |> IO.iodata_to_binary() |> JSON.decode() do
      {:ok, response} ->
        response =
          response
          |> put_negotiated_protocol_version(negotiated_protocol_version)
          |> add_output_schemas(opts)

        conn
        |> delete_resp_header("content-length")
        |> Map.put(:resp_body, JSON.encode!(response))

      _ ->
        conn
    end
  end

  defp put_negotiated_protocol_version(
         %{"result" => %{"protocolVersion" => _current_version} = result} = response,
         negotiated_protocol_version
       )
       when is_binary(negotiated_protocol_version) do
    put_in(response, ["result"], Map.put(result, "protocolVersion", negotiated_protocol_version))
  end

  defp put_negotiated_protocol_version(response, _negotiated_protocol_version), do: response

  defp add_output_schemas(%{"result" => %{"tools" => tools} = result} = response, opts) when is_list(tools) do
    modules = opts |> Keyword.fetch!(:server) |> apply(:server, []) |> Map.fetch!(:tools)

    descriptors =
      Enum.map(tools, fn %{"name" => name} = tool ->
        case Map.fetch(modules, name) do
          {:ok, module} -> Tuist.MCP.Tool.descriptor(module)
          :error -> tool
        end
      end)

    put_in(response, ["result"], Map.put(result, "tools", descriptors))
  end

  defp add_output_schemas(response, _opts), do: response
end
