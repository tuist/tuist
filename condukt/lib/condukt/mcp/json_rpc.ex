defmodule Condukt.MCP.JSONRPC do
  @moduledoc false

  # Minimal JSON-RPC 2.0 helpers for MCP. The protocol uses only a small
  # subset of JSON-RPC: requests with integer ids, responses, and
  # notifications (requests without an id).

  @jsonrpc "2.0"

  @doc "Builds a request envelope."
  def request(id, method, params \\ nil) do
    base = %{"jsonrpc" => @jsonrpc, "id" => id, "method" => method}
    if params, do: Map.put(base, "params", params), else: base
  end

  @doc "Builds a notification envelope."
  def notification(method, params \\ nil) do
    base = %{"jsonrpc" => @jsonrpc, "method" => method}
    if params, do: Map.put(base, "params", params), else: base
  end

  @doc """
  Encodes an envelope to its newline-delimited JSON form, suitable for
  stdio transport.
  """
  def encode_line!(envelope), do: JSON.encode!(envelope) <> "\n"

  @doc """
  Encodes an envelope as JSON without trailing newline (HTTP transports).
  """
  def encode!(envelope), do: JSON.encode!(envelope)

  @doc """
  Decodes a JSON-RPC envelope binary, returning a tagged classification.

  Returns:

    * `{:response, id, {:ok, result}}` for a successful response
    * `{:response, id, {:error, %{"code" => _, "message" => _, ...}}}` for an error response
    * `{:request, id, method, params}` for a server-initiated request (rare for MCP clients)
    * `{:notification, method, params}` for a notification
    * `{:error, reason}` if the payload is not valid JSON-RPC 2.0
  """
  def classify(message) when is_map(message) do
    case message do
      %{"jsonrpc" => @jsonrpc, "id" => id, "result" => result} ->
        {:response, id, {:ok, result}}

      %{"jsonrpc" => @jsonrpc, "id" => id, "error" => error} ->
        {:response, id, {:error, error}}

      %{"jsonrpc" => @jsonrpc, "method" => method, "id" => id} = msg ->
        {:request, id, method, Map.get(msg, "params")}

      %{"jsonrpc" => @jsonrpc, "method" => method} = msg ->
        {:notification, method, Map.get(msg, "params")}

      _ ->
        {:error, :invalid_envelope}
    end
  end

  def classify(other), do: {:error, {:invalid_envelope, other}}

  @doc """
  Decodes a JSON binary and classifies it.
  """
  def decode_and_classify(binary) when is_binary(binary) do
    case JSON.decode(binary) do
      {:ok, decoded} -> classify(decoded)
      {:error, reason} -> {:error, {:decode_failed, reason}}
    end
  end
end
