defmodule AtlasWeb.WellKnownControllerTest do
  use AtlasWeb.ConnCase, async: true

  describe "GET /.well-known/oauth-authorization-server" do
    test "advertises the OAuth endpoints and supported scopes", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-authorization-server")

      assert %{
               "issuer" => issuer,
               "authorization_endpoint" => authorize,
               "token_endpoint" => token,
               "registration_endpoint" => register,
               "scopes_supported" => ["mcp"],
               "code_challenge_methods_supported" => ["S256"]
             } = json_response(conn, 200)

      assert authorize == "#{issuer}/oauth2/authorize"
      assert token == "#{issuer}/oauth2/token"
      assert register == "#{issuer}/oauth2/register"
    end
  end

  describe "GET /.well-known/oauth-protected-resource" do
    test "returns metadata for the MCP resource", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-protected-resource/mcp")
      body = json_response(conn, 200)

      assert String.ends_with?(body["resource"], "/mcp")
      assert body["scopes_supported"] == ["mcp"]
      assert body["bearer_methods_supported"] == ["header"]
    end

    test "404s for unknown resources", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-protected-resource/unknown")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end
end
