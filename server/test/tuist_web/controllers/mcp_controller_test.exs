defmodule TuistWeb.MCPControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.RateLimit

  @initialize_params %{
    "protocolVersion" => "2025-03-26",
    "capabilities" => %{},
    "clientInfo" => %{"name" => "test", "version" => "0.1.0"}
  }

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

    test "returns 200 with server capabilities for initialize", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => @initialize_params
        })

      response = json_response(conn, 200)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert is_map(response["result"])
      assert is_binary(response["result"]["protocolVersion"])
      assert is_map(response["result"]["capabilities"])
    end

    test "returns error when session is not initialized", %{conn: conn} do
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

      assert conn.status == 400
      response = json_response(conn, 400)
      assert response["error"] == "Missing session ID"
    end

    test "returns 202 for notifications after initialize", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      # First initialize to get a session ID
      init_conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => @initialize_params
        })

      [session_id] = get_resp_header(init_conn, "mcp-session-id")

      # Then send notification with the session ID
      notification_conn =
        build_conn()
        |> authenticated_mcp_conn(user.token)
        |> put_req_header("mcp-session-id", session_id)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized",
          "params" => %{}
        })

      assert notification_conn.status == 202
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
          "params" => @initialize_params
        })

      response = json_response(conn, 429)
      assert response["error"]["code"] == -32_603
      assert response["error"]["message"] =~ "Rate limit"
    end

    test "returns JSON content-type for requests, never SSE", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "initialize",
          "params" => @initialize_params
        })

      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/json"
      refute content_type =~ "text/event-stream"
    end

    test "assigns a session ID on first request", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => @initialize_params
        })

      assert [session_id] = get_resp_header(conn, "mcp-session-id")
      assert is_binary(session_id)
      assert session_id != ""
    end

    test "returns error for request without session ID", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{"invalid" => "not a jsonrpc message"})

      assert conn.status == 400
      response = json_response(conn, 400)
      assert response["error"] == "Missing session ID"
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
