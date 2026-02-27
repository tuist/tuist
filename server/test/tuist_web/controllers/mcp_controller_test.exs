defmodule TuistWeb.MCPControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.RateLimit

  describe "POST /mcp" do
    test "returns a bearer challenge when not authenticated", %{conn: conn} do
      conn = post_mcp(conn, %{})
      response = json_response(conn, 401)

      [www_authenticate] = get_resp_header(conn, "www-authenticate")

      assert www_authenticate ==
               ~s(Bearer realm="tuist-mcp", resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/mcp")

      assert response == %{
               "error" => "invalid_token",
               "error_description" => "Missing or invalid access token."
             }
    end

    test "returns 202 for initialize over streamable transport", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{}
        })

      assert conn.status == 202
    end

    test "returns protocol error when session is not initialized", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/list",
          "params" => %{}
        })

      response = json_response(conn, 200)
      assert response["jsonrpc"] == "2.0"
      assert is_binary(response["id"])
      assert response["error"]["code"] == -32_600
      assert response["error"]["message"] == "Invalid Request"
    end

    test "returns 202 for notifications", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized",
          "params" => %{}
        })

      assert conn.status == 202
    end

    test "returns rate limit error when rate limited", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:deny, 0} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => "initialize",
          "params" => %{}
        })

      response = json_response(conn, 429)
      assert response["error"]["code"] == -32_603
      assert response["error"]["message"] =~ "Rate limit"
    end
  end

  defp post_mcp(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/mcp", Jason.encode!(body))
  end

  defp authenticated_mcp_conn(conn, token) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json, text/event-stream")
  end
end
