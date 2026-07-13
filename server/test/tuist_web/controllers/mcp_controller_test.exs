defmodule TuistWeb.MCPControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.RateLimit

  @initialize_params %{
    "protocolVersion" => "2025-06-18",
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
      assert response["result"]["protocolVersion"] == "2025-06-18"
      assert is_map(response["result"]["capabilities"])
    end

    test "negotiates the legacy protocol version when requested", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      initialize_params = Map.put(@initialize_params, "protocolVersion", "2025-03-26")

      conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => initialize_params
        })

      response = json_response(conn, 200)
      assert response["result"]["protocolVersion"] == "2025-03-26"
    end

    test "returns the latest supported protocol version for an unsupported initialization version", %{
      conn: conn
    } do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      initialize_params = Map.put(@initialize_params, "protocolVersion", "2099-01-01")

      conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => initialize_params
        })

      response = json_response(conn, 200)
      assert response["result"]["protocolVersion"] == "2025-06-18"
    end

    test "rejects an unsupported protocol version header", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> put_req_header("mcp-protocol-version", "2099-01-01")
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/list",
          "params" => %{}
        })

      response = json_response(conn, 400)
      assert response["error"] == "Unsupported MCP protocol version: 2099-01-01"
      assert response["supported"] == ["2025-06-18", "2025-03-26"]
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
        |> put_req_header("mcp-protocol-version", "2025-06-18")
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

    test "returns request responses inline when the session has a stale event stream registration", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

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

      stale_pid = spawn(fn -> :ok end)
      ref = Process.monitor(stale_pid)
      assert_receive {:DOWN, ^ref, :process, ^stale_pid, _reason}
      EMCP.SessionStore.ETS.register(session_id, stale_pid)

      conn =
        build_conn()
        |> authenticated_mcp_conn(user.token)
        |> put_req_header("mcp-session-id", session_id)
        |> put_req_header("mcp-protocol-version", "2025-06-18")
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/list",
          "params" => %{}
        })

      response = json_response(conn, 200)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 2

      tools = response["result"]["tools"]
      assert length(tools) == 34

      for tool <- tools do
        assert is_binary(tool["description"]) and tool["description"] != ""
        assert tool["outputSchema"]["type"] == "object"
        assert is_map(tool["outputSchema"]["properties"])
      end
    end

    test "serves methods that skip response decoration", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

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

      conn =
        build_conn()
        |> authenticated_mcp_conn(user.token)
        |> put_req_header("mcp-session-id", session_id)
        |> put_req_header("mcp-protocol-version", "2025-06-18")
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "prompts/list",
          "params" => %{}
        })

      response = json_response(conn, 200)
      assert response["id"] == 2
      assert is_list(response["result"]["prompts"])
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
    |> post("/mcp", JSON.encode!(body))
  end

  defp authenticated_mcp_conn(conn, token) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json, text/event-stream")
  end
end
