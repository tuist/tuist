defmodule PulseWeb.MCPRequestGate do
  @moduledoc """
  Pre-parse checks for the MCP endpoint. Runs in the endpoint before
  `Plug.Parsers`, so rejected requests are refused before their body is read
  or parsed.

  The gate matches the path the way the router does (percent-decoded
  segments), so an encoded alias such as `/%6dcp` cannot route to the
  controller while skipping these checks.

  ## Origin

  The MCP Streamable HTTP transport requires rejecting a present but invalid
  `Origin` header with `403` to prevent DNS rebinding. Requests without an
  `Origin` header (server-side clients such as Atlas) are accepted. A present
  origin must match an entry of

      config :pulse, PulseWeb.MCPController, allowed_origins: ["https://example.com"]

  compared as `{scheme, host, port}` with case-insensitive scheme and host
  and the scheme's default port filled in. The default is an empty list,
  which rejects every browser origin. `null`, malformed, non-ASCII, repeated,
  or path-bearing origins are always rejected; configured entries that are
  not valid origins never match.

  ## Media type

  A POST body must be a single JSON-RPC message, so POSTs whose
  `Content-Type` is not `application/json` get `415` instead of reaching the
  form or multipart parsers.
  """

  @behaviour Plug

  import Plug.Conn

  alias Plug.Conn.Utils
  alias Pulse.Runtime

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if mcp_path?(conn.path_info), do: check(conn), else: conn
  end

  defp check(conn) do
    cond do
      not origin_allowed?(get_req_header(conn, "origin")) ->
        reject(conn, 403, "Forbidden origin")

      conn.method == "POST" and not json?(get_req_header(conn, "content-type")) ->
        reject(conn, 415, "Unsupported Media Type")

      true ->
        conn
    end
  end

  @doc "Whether `path_info` routes to the MCP endpoint once percent-decoded."
  @spec mcp_path?([String.t()]) :: boolean()
  def mcp_path?(path_info) do
    Enum.map(path_info, &URI.decode/1) == ["mcp"]
  rescue
    # The router fails on the same malformed encoding, so nothing is routed.
    ArgumentError -> false
  end

  defp origin_allowed?([]), do: true

  defp origin_allowed?([origin]) do
    case parse_origin(origin) do
      {:ok, parsed} -> parsed in allowed_origins()
      :error -> false
    end
  end

  defp origin_allowed?(_repeated), do: false

  defp allowed_origins do
    :pulse
    |> Runtime.get_env(PulseWeb.MCPController, [])
    |> Keyword.get(:allowed_origins, [])
    |> Enum.flat_map(fn origin ->
      case parse_origin(origin) do
        {:ok, parsed} -> [parsed]
        :error -> []
      end
    end)
  end

  defp parse_origin(origin) when is_binary(origin) do
    # URI parsing raises on some invalid byte sequences, so only visible
    # ASCII reaches it.
    if ascii_visible?(origin), do: parse_uri(origin), else: :error
  end

  defp parse_origin(_origin), do: :error

  defp parse_uri(origin) do
    case URI.new(origin) do
      {:ok, %URI{scheme: scheme, host: host, port: port, path: path, userinfo: nil, query: nil, fragment: nil}}
      when is_binary(scheme) and is_binary(host) and host != "" and is_integer(port) and path in [nil, ""] ->
        scheme = String.downcase(scheme)
        if scheme in ["http", "https"], do: {:ok, {scheme, String.downcase(host), port}}, else: :error

      _ ->
        :error
    end
  end

  defp ascii_visible?(value), do: value != "" and value |> :binary.bin_to_list() |> Enum.all?(&(&1 in 33..126))

  defp json?([content_type]) do
    case Utils.content_type(content_type) do
      {:ok, "application", "json", _params} -> true
      _ -> false
    end
  end

  defp json?(_content_type), do: false

  defp reject(conn, status, message) do
    body = Pulse.JSON.encode!(Pulse.MCP.error_response(nil, -32_600, message))

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
    |> halt()
  end
end
