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

  def public(conn, _params), do: handle(conn, WebMCP.public_server())

  defp handle(conn, server) do
    if supported?(conn.body_params) do
      json(conn, EMCP.Server.handle_message(server, conn, conn.body_params))
    else
      conn
      |> put_status(:bad_request)
      |> json(%{
        jsonrpc: "2.0",
        id: conn.body_params["id"],
        error: %{code: -32_600, message: "Only tools/list and tools/call requests are supported."}
      })
    end
  end

  # Both methods are requests, so a message without an `id` (a notification)
  # is refused rather than answered with an empty JSON-RPC response, and a
  # call has to name its tool.
  defp supported?(%{"jsonrpc" => "2.0", "id" => _, "method" => "tools/list"}), do: true

  defp supported?(%{"jsonrpc" => "2.0", "id" => _, "method" => "tools/call", "params" => %{"name" => name}})
       when is_binary(name), do: true

  defp supported?(_message), do: false
end
