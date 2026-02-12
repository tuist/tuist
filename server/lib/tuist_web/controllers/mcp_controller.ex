defmodule TuistWeb.MCPController do
  use TuistWeb, :controller

  alias Tuist.Environment
  alias TuistWeb.Authentication
  alias TuistWeb.AuthenticationPlug

  @mcp_resource_metadata_path "/.well-known/oauth-protected-resource/mcp"

  def request(conn, _params) do
    conn = AuthenticationPlug.call(conn, :load_authenticated_subject)

    if Authentication.authenticated?(conn) do
      not_implemented(conn)
    else
      unauthorized(conn)
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

  defp not_implemented(conn) do
    conn
    |> put_status(:not_implemented)
    |> json(%{
      jsonrpc: "2.0",
      error: %{
        code: -32_601,
        message: "Tuist MCP HTTP transport is not implemented yet."
      },
      id: nil
    })
  end
end
