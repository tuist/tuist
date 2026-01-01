defmodule TuistWeb.AuthenticationTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistWeb.Authentication

  describe "get_authorization_token_from_conn/1" do
    test "extracts token from Bearer authorization header", %{conn: conn} do
      token = "my_bearer_token_123"

      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      assert Authentication.get_authorization_token_from_conn(conn) == token
    end

    test "extracts token from Basic authorization header", %{conn: conn} do
      token = "tuist_abc123_secrethash"
      credentials = Base.encode64("token:#{token}")

      conn = put_req_header(conn, "authorization", "Basic #{credentials}")

      assert Authentication.get_authorization_token_from_conn(conn) == token
    end

    test "extracts token from Basic auth with different username", %{conn: conn} do
      token = "tuist_abc123_secrethash"
      credentials = Base.encode64("anyuser:#{token}")

      conn = put_req_header(conn, "authorization", "Basic #{credentials}")

      assert Authentication.get_authorization_token_from_conn(conn) == token
    end

    test "returns nil when no authorization header is present", %{conn: conn} do
      assert Authentication.get_authorization_token_from_conn(conn) == nil
    end

    test "returns nil for invalid authorization header format", %{conn: conn} do
      conn = put_req_header(conn, "authorization", "InvalidFormat token123")

      assert Authentication.get_authorization_token_from_conn(conn) == nil
    end

    test "returns nil for invalid Base64 in Basic auth", %{conn: conn} do
      conn = put_req_header(conn, "authorization", "Basic not_valid_base64!!!")

      assert Authentication.get_authorization_token_from_conn(conn) == nil
    end

    test "returns nil for Basic auth without colon separator", %{conn: conn} do
      credentials = Base.encode64("tokenwithoutseparator")

      conn = put_req_header(conn, "authorization", "Basic #{credentials}")

      assert Authentication.get_authorization_token_from_conn(conn) == nil
    end

    test "handles Basic auth with colon in password", %{conn: conn} do
      token = "token:with:colons"
      credentials = Base.encode64("user:#{token}")

      conn = put_req_header(conn, "authorization", "Basic #{credentials}")

      assert Authentication.get_authorization_token_from_conn(conn) == token
    end

    test "handles empty password in Basic auth", %{conn: conn} do
      credentials = Base.encode64("user:")

      conn = put_req_header(conn, "authorization", "Basic #{credentials}")

      assert Authentication.get_authorization_token_from_conn(conn) == ""
    end
  end
end
