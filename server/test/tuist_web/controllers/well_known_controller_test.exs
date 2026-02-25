defmodule TuistWeb.WellKnownControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

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
