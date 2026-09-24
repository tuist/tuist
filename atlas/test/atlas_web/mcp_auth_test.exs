defmodule AtlasWeb.MCPAuthTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Guardian
  alias Atlas.Repo
  alias Atlas.Users.User

  describe "POST /mcp without a token" do
    test "responds with 401 and a www-authenticate header", %{conn: conn} do
      conn = post(conn, "/mcp", %{})

      assert conn.status == 401
      assert [www_authenticate] = get_resp_header(conn, "www-authenticate")
      assert www_authenticate =~ ~s(Bearer realm="atlas-mcp")
      assert www_authenticate =~ "/.well-known/oauth-protected-resource/mcp"

      assert JSON.decode!(conn.resp_body) == %{
               "error" => "invalid_token",
               "error_description" => "Missing or invalid access token."
             }
    end
  end

  describe "POST /mcp with an invalid token" do
    test "responds with 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-a-real-token")
        |> post("/mcp", %{})

      assert conn.status == 401
    end
  end

  describe "POST /mcp with a valid Guardian token" do
    test "resolves the user and passes the request to EMCP", %{conn: conn} do
      {:ok, user} =
        %User{} |> User.changeset(%{email: "mcp@tuist.dev", name: "MCP"}) |> Repo.insert()

      {:ok, jwt, _claims} =
        Guardian.encode_and_sign(user, %{"scopes" => ["mcp"]}, token_type: "access_token")

      # EMCP requires an MCP-shaped JSON-RPC body; without it the transport
      # responds with a JSON-RPC error rather than the auth 401.
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{jwt}")
        |> put_req_header("content-type", "application/json")
        |> post("/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})

      refute conn.status == 401
    end
  end
end
