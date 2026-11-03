defmodule TuistWeb.WebMCPController do
  @moduledoc """
  Answers the tool listings and calls of the WebMCP tools the website registers
  in the browser (`assets/shared/js/webmcp.mjs`). Requests are JSON-RPC
  `tools/list` and `tools/call` messages handled by the MCP server's own
  dispatcher, so input validation and tool authorization are the same as on
  `/mcp`; nothing else in the protocol is served.
  """
  use TuistWeb, :controller

  alias Tuist.MCP.WebMCP

  @methods ["tools/list", "tools/call"]

  def signed_in(conn, _params), do: handle(conn, WebMCP.signed_in_server())

  def public(conn, _params), do: handle(conn, WebMCP.public_server())

  # Both methods are requests, so a message without an `id` (a notification)
  # is refused rather than answered with an empty JSON-RPC response.
  defp handle(%{body_params: %{"jsonrpc" => "2.0", "id" => _, "method" => method} = request} = conn, server)
       when method in @methods do
    json(conn, EMCP.Server.handle_message(server, conn, request))
  end

  defp handle(conn, _server) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      jsonrpc: "2.0",
      id: conn.body_params["id"],
      error: %{code: -32_600, message: "Only tools/list and tools/call requests are supported."}
    })
  end
end
