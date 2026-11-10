defmodule Condukt.MCP.Transport do
  @moduledoc false

  # Behaviour shared by every MCP transport (`Condukt.MCP.Transport.Stdio`,
  # `Condukt.MCP.Transport.HttpSSE`, `Condukt.MCP.Transport.StreamableHttp`).
  #
  # Each transport is its own process. The `Condukt.MCP.Client` holds
  # protocol state and delegates wire I/O to the transport process by:
  #
  #   * calling `send_message/2` to push a JSON-RPC envelope outward
  #
  # The transport delivers inbound traffic to the client by sending the
  # client process the messages:
  #
  #   * `{:mcp_message, decoded_envelope}` for each parsed JSON object
  #   * `{:mcp_transport_down, reason}` when the underlying connection
  #     terminates
  #
  # `start_link/1` accepts a keyword list with at least `:server`
  # (`%Condukt.MCP.Server{}`) and `:owner` (the client pid that should
  # receive the inbound messages). Transport-specific options are passed
  # through unchanged.
  #
  # `start_link/1` returns the normal GenServer start result,
  # `send_message/2` returns `:ok` or `{:error, reason}`, and `close/1`
  # returns `:ok`.

  @doc """
  Returns the implementation module for the transport tag declared on
  the server.
  """
  def implementation({:stdio, _opts}), do: Condukt.MCP.Transport.Stdio
  def implementation({:http_sse, _opts}), do: Condukt.MCP.Transport.HttpSSE
  def implementation({:streamable_http, _opts}), do: Condukt.MCP.Transport.StreamableHttp
end
