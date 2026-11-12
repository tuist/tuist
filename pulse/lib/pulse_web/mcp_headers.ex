defmodule PulseWeb.MCPHeaders do
  @moduledoc """
  Validates the request metadata headers that the Streamable HTTP transport
  mirrors from the JSON-RPC body (MCP `2026-07-28`).

  `MCP-Protocol-Version` and `Mcp-Method` are required on every request, and
  `Mcp-Name` on `tools/call`, `resources/read`, and `prompts/get`. Each must
  appear once, contain only visible ASCII, space, or tab, and match the body.
  `Mcp-Name` may use the `=?base64?…?=` sentinel encoding, which is decoded
  before comparison.

  The protocol version and `Mcp-Name` are checked against the body only
  when the body carries them as strings; a missing or malformed body field
  is reported by `Pulse.MCP` as invalid params instead.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @named_methods %{"tools/call" => "name", "resources/read" => "uri", "prompts/get" => "name"}
  @version_key "io.modelcontextprotocol/protocolVersion"

  @spec validate(Plug.Conn.t(), {:request, term(), String.t(), map()}) :: :ok | {:error, String.t()}
  def validate(conn, {:request, _id, method, params}) do
    with {:ok, version} <- required(conn, "mcp-protocol-version", "MCP-Protocol-Version"),
         {:ok, header_method} <- required(conn, "mcp-method", "Mcp-Method"),
         :ok <- match_version(version, params),
         :ok <- match("Mcp-Method", header_method, method) do
      validate_name(conn, method, params)
    end
  end

  defp validate_name(conn, method, params) do
    with {:ok, field} <- Map.fetch(@named_methods, method),
         body when is_binary(body) <- params[field],
         {:ok, encoded} <- required(conn, "mcp-name", "Mcp-Name"),
         {:ok, name} <- decode(encoded) do
      match("Mcp-Name", name, body)
    else
      {:error, _reason} = error -> error
      _not_named_or_malformed_body -> :ok
    end
  end

  defp required(conn, header, display) do
    case get_req_header(conn, header) do
      [value] ->
        if header_safe?(value), do: {:ok, value}, else: {:error, "#{display} header contains invalid characters"}

      [] ->
        {:error,
         "Missing #{display} header; supported protocol versions: #{Enum.join(Pulse.MCP.supported_versions(), ", ")}"}

      _ ->
        {:error, "Duplicate #{display} header"}
    end
  end

  defp match_version(version, %{"_meta" => %{@version_key => body}}) when is_binary(body),
    do: match("MCP-Protocol-Version", version, body)

  defp match_version(_version, _params), do: :ok

  defp match(_display, value, value), do: :ok

  defp match(display, header, body),
    do:
      {:error, "Header mismatch: #{display} header value #{inspect(header)} does not match body value #{inspect(body)}"}

  defp decode("=?base64?" <> rest = value) do
    with true <- String.ends_with?(rest, "?="),
         {:ok, decoded} <- Base.decode64(String.slice(rest, 0..-3//1)),
         true <- String.valid?(decoded) do
      {:ok, decoded}
    else
      _ -> {:error, "Mcp-Name header has an invalid Base64 value: #{inspect(value)}"}
    end
  end

  defp decode(value), do: {:ok, value}

  defp header_safe?(value), do: value |> :binary.bin_to_list() |> Enum.all?(&(&1 == 9 or &1 in 32..126))
end
