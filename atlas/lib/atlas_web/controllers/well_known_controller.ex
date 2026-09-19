defmodule AtlasWeb.WellKnownController do
  use AtlasWeb, :controller

  alias AtlasWeb.RequestOrigin

  @mcp_path "/mcp"
  @oauth_token_path "/oauth2/token"
  @oauth_authorize_path "/oauth2/authorize"
  @oauth_registration_path "/oauth2/register"

  def oauth_authorization_server(conn, _params) do
    issuer = RequestOrigin.from_conn(conn)

    json(conn, %{
      issuer: issuer,
      authorization_endpoint: "#{issuer}#{@oauth_authorize_path}",
      token_endpoint: "#{issuer}#{@oauth_token_path}",
      registration_endpoint: "#{issuer}#{@oauth_registration_path}",
      grant_types_supported: ["authorization_code", "refresh_token"],
      response_types_supported: ["code"],
      code_challenge_methods_supported: ["S256"],
      scopes_supported: ["mcp"],
      token_endpoint_auth_methods_supported: [
        "none",
        "client_secret_basic",
        "client_secret_post"
      ]
    })
  end

  def oauth_protected_resource(conn, params) do
    origin = RequestOrigin.from_conn(conn)

    case Map.get(params, "resource_path", []) do
      [] ->
        json(conn, resource_metadata(origin))

      ["mcp"] ->
        json(conn, resource_metadata(origin, @mcp_path))

      _ ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  defp resource_metadata(origin, resource_path \\ "") do
    %{
      resource: "#{origin}#{resource_path}",
      authorization_servers: [origin],
      bearer_methods_supported: ["header"],
      scopes_supported: ["mcp"]
    }
  end
end
