defmodule TuistWeb.WellKnownControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Namespace.JWTToken

  describe "GET /.well-known/openid_configuration" do
    test "returns the OpenID configuration", %{conn: conn} do
      issuer = "https://test.example.com"

      expect(JWTToken, :issuer, fn -> issuer end)
      conn = get(conn, "/.well-known/openid-configuration")

      response = json_response(conn, 200)

      assert response["issuer"] == issuer
    end
  end

  describe "GET /.well-known/jwks.json" do
    test "returns the JWKS", %{conn: conn} do
      expect(JWTToken, :public_jwk, fn ->
        %{
          "kty" => "RSA",
          "use" => "sig",
          "alg" => "RS256",
          "kid" => "namespace-jwt-key-1",
          "n" => "mock_n_value",
          "e" => "AQAB"
        }
      end)

      conn = get(conn, "/.well-known/jwks.json")

      response = json_response(conn, 200)

      assert length(response["keys"]) == 1
    end
  end

  describe "GET /.well-known/oauth-authorization-server" do
    test "returns OAuth authorization server metadata", %{conn: conn} do
      stub(Environment, :app_url, fn -> "https://test.tuist.dev" end)

      conn = get(conn, "/.well-known/oauth-authorization-server")

      response = json_response(conn, 200)

      assert response["issuer"] == "https://test.tuist.dev"
      assert response["authorization_endpoint"] == "https://test.tuist.dev/oauth2/authorize"
      assert response["token_endpoint"] == "https://test.tuist.dev/oauth2/token"
      assert response["registration_endpoint"] == "https://test.tuist.dev/oauth2/register"
    end
  end

  describe "GET /.well-known/oauth-protected-resource/mcp" do
    test "returns MCP protected resource metadata", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-protected-resource/mcp")

      response = json_response(conn, 200)

      assert response["resource"] == "http://www.example.com/mcp"
      assert response["authorization_servers"] == ["http://www.example.com"]
      assert response["bearer_methods_supported"] == ["header"]
      refute Map.has_key?(response, "resource_documentation")
    end

    test "uses request origin including non-default port", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "custom.tuist.dev")
        |> Map.put(:port, 8443)
        |> get("/.well-known/oauth-protected-resource/mcp")

      response = json_response(conn, 200)

      assert response["resource"] == "http://custom.tuist.dev:8443/mcp"
      assert response["authorization_servers"] == ["http://custom.tuist.dev:8443"]
    end
  end

  describe "GET /.well-known/apple-app-site-association" do
    test "returns the apple app site association JSON", %{conn: conn} do
      conn = get(conn, "/.well-known/apple-app-site-association")

      assert json_response(conn, 200) == %{
               "applinks" => %{
                 "apps" => [],
                 "details" => [
                   %{
                     "appID" => "U6LC622NKF.dev.tuist.app",
                     "paths" => ["/*/*/previews/*"]
                   }
                 ]
               }
             }

      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end
  end

  describe "GET /.well-known/assetlinks.json" do
    test "returns Android asset links with release fingerprint", %{conn: conn} do
      conn = get(conn, "/.well-known/assetlinks.json")

      response = json_response(conn, 200)

      assert [link] = response
      assert link["relation"] == ["delegate_permission/common.handle_all_urls"]
      assert link["target"]["namespace"] == "android_app"
      assert link["target"]["package_name"] == "dev.tuist.app"
      assert is_list(link["target"]["sha256_cert_fingerprints"])

      assert "D9:94:6C:7F:C9:CA:86:91:38:26:7C:21:BC:C9:92:10:91:DB:A7:31:C5:AE:8E:05:30:89:5B:11:94:CF:E2:2D" in link[
               "target"
             ]["sha256_cert_fingerprints"]
    end
  end
end
