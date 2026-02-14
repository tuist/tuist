defmodule TuistWeb.MCPController do
  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.MCP.Server, as: MCPServer
  alias TuistWeb.Authentication
  alias TuistWeb.AuthenticationPlug
  alias TuistWeb.RateLimit

  @mcp_resource_metadata_path "/.well-known/oauth-protected-resource/mcp"

  def request(conn, params) do
    conn = AuthenticationPlug.call(conn, :load_authenticated_subject)

    if Authentication.authenticated?(conn) do
      handle_authenticated(conn, params)
    else
      unauthorized(conn)
    end
  end

  defp handle_authenticated(conn, params) do
    case RateLimit.Auth.hit(conn) do
      {:allow, _} ->
        subject = Authentication.authenticated_subject(conn)
        response = MCPServer.handle_request(params, subject)

        if is_nil(response) do
          send_resp(conn, 202, "")
        else
          json(conn, response)
        end

      {:deny, _} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{
          jsonrpc: "2.0",
          id: Map.get(params, "id"),
          error: %{code: -32_603, message: "Rate limit exceeded. Please try again later."}
        })
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer realm="tuist-mcp", resource_metadata="#{Environment.app_url()}#{@mcp_resource_metadata_path}")
    )
    |> put_status(:unauthorized)
    |> json(%{
      error: "invalid_token",
      error_description: "Missing or invalid access token."
    })
    |> halt()
  end
end
