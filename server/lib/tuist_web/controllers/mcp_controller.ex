defmodule TuistWeb.MCPController do
  use TuistWeb, :controller

  alias Tuist.MCP.Server, as: MCPServer
  alias TuistWeb.Authentication
  alias TuistWeb.Plugs.MCPRateLimitPlug

  plug TuistWeb.AuthenticationPlug, :load_authenticated_subject
  plug TuistWeb.AuthenticationPlug, {:require_authentication, response_type: :mcp}
  plug MCPRateLimitPlug

  def request(conn, params) do
    subject = Authentication.authenticated_subject(conn)
    response = MCPServer.handle_request(params, subject)

    if is_nil(response) do
      send_resp(conn, 202, "")
    else
      json(conn, response)
    end
  end
end
