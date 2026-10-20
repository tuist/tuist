defmodule AtlasWeb.MCPAuthTest do
  use AtlasWeb.ConnCase, async: true

  import Ecto.Query

  alias Atlas.Guardian
  alias Atlas.OAuth.AccessTokens
  alias Boruta.Ecto.Token

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

  test "rejects a JWT without a persisted OAuth grant", %{conn: conn} do
    {_session_conn, user} = log_in_user(conn)
    {:ok, jwt, _claims} = Guardian.encode_and_sign(user, %{"scopes" => ["mcp"]}, token_type: "access_token")

    conn = conn |> put_req_header("authorization", "Bearer #{jwt}") |> post("/mcp", %{})
    assert conn.status == 401
  end

  test "rejects a token revoked in shared OAuth state after a successful request", %{conn: conn} do
    {_session_conn, user} = log_in_user(conn)
    jwt = oauth_access_token_fixture(user)
    request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"}

    assert conn |> put_req_header("authorization", "Bearer #{jwt}") |> post("/mcp", request) |> response(200)
    assert {:ok, _revoked} = jwt |> then(&AccessTokens.get_by(value: &1)) |> AccessTokens.revoke()

    conn = build_conn() |> put_req_header("authorization", "Bearer #{jwt}") |> post("/mcp", request)
    assert conn.status == 401
  end

  test "rejects an expired persisted OAuth grant even while its JWT remains unexpired", %{conn: conn} do
    {_session_conn, user} = log_in_user(conn)
    jwt = oauth_access_token_fixture(user)
    assert {:ok, claims} = Guardian.decode_and_verify(jwt)
    assert claims["exp"] > System.system_time(:second)
    Atlas.Repo.update_all(from(t in Token, where: t.value == ^jwt), set: [expires_at: 0])

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{jwt}")
      |> post("/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})

    assert conn.status == 401
  end

  test "real-router initialization is stateless and advertises no change notifications", %{conn: conn} do
    {_session_conn, user} = log_in_user(conn)
    jwt = oauth_access_token_fixture(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{jwt}")
      |> put_req_header("content-type", "application/json")
      |> post("/mcp", JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}))

    assert get_resp_header(conn, "mcp-session-id") == []

    for capability <- ~w(tools prompts resources) do
      assert json_response(conn, 200)["result"]["capabilities"][capability]["listChanged"] == false
    end
  end

  describe "POST /mcp with a valid Guardian token" do
    test "resolves the user and passes the request to EMCP", %{conn: conn} do
      {_session_conn, user} = log_in_user(conn)
      jwt = oauth_access_token_fixture(user)

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
