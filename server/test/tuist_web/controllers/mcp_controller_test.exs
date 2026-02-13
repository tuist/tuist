defmodule TuistWeb.MCPControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.RateLimit

  describe "POST /mcp" do
    test "returns a bearer challenge when not authenticated", %{conn: conn} do
      stub(Environment, :app_url, fn -> "https://test.tuist.dev" end)

      conn = post(conn, "/mcp", %{})
      response = json_response(conn, 401)

      [www_authenticate] = get_resp_header(conn, "www-authenticate")

      assert www_authenticate =~ ~s(Bearer realm="tuist-mcp")

      assert www_authenticate =~
               ~s(resource_metadata="https://test.tuist.dev/.well-known/oauth-protected-resource/mcp")

      assert response == %{
               "error" => "invalid_token",
               "error_description" => "Missing or invalid access token."
             }
    end

    test "handles initialize request", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.Auth, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{}
        })

      response = json_response(conn, 200)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2025-03-26"
      assert response["result"]["serverInfo"]["name"] == "tuist"
      assert response["result"]["capabilities"]["tools"]
      assert response["result"]["capabilities"]["prompts"]
    end

    test "handles tools/list request", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.Auth, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/list",
          "params" => %{}
        })

      response = json_response(conn, 200)
      assert response["id"] == 2
      tools = response["result"]["tools"]
      assert is_list(tools)
      tool_names = Enum.map(tools, & &1["name"])
      assert "list_projects" in tool_names
      assert "list_flaky_tests" in tool_names
      assert "get_test_case" in tool_names
      assert "get_test_case_run" in tool_names
    end

    test "handles tools/call with list_projects", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.Auth, :hit, fn _conn -> {:allow, 1} end)

      stub(Projects, :list_accessible_projects, fn _subject, _opts ->
        [
          %Tuist.Projects.Project{
            id: 1,
            name: "my-project",
            account: %Tuist.Accounts.Account{name: "my-org"}
          }
        ]
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "tools/call",
          "params" => %{
            "name" => "list_projects",
            "arguments" => %{}
          }
        })

      response = json_response(conn, 200)
      assert response["id"] == 3
      content = response["result"]["content"]
      assert is_list(content)
      assert hd(content)["type"] == "text"
      data = Jason.decode!(hd(content)["text"])
      assert is_list(data)
      assert hd(data)["full_handle"] == "my-org/my-project"
    end

    test "returns error for unknown method", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.Auth, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 4,
          "method" => "unknown/method",
          "params" => %{}
        })

      response = json_response(conn, 200)
      assert response["id"] == 4
      assert response["error"]["code"] == -32_601
      assert response["error"]["message"] == "Method not found."
    end

    test "returns 202 for notifications", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.Auth, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized",
          "params" => %{}
        })

      assert conn.status == 202
    end

    test "returns rate limit error when rate limited", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.Auth, :hit, fn _conn -> {:deny, 0} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => "initialize",
          "params" => %{}
        })

      response = json_response(conn, 429)
      assert response["error"]["code"] == -32_603
      assert response["error"]["message"] =~ "Rate limit"
    end

    test "handles prompts/list request", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.Auth, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 6,
          "method" => "prompts/list",
          "params" => %{}
        })

      response = json_response(conn, 200)
      assert response["id"] == 6
      prompts = response["result"]["prompts"]
      assert is_list(prompts)
      prompt_names = Enum.map(prompts, & &1["name"])
      assert "fix_flaky_test" in prompt_names
    end

    test "handles prompts/get request", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.Auth, :hit, fn _conn -> {:allow, 1} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 7,
          "method" => "prompts/get",
          "params" => %{
            "name" => "fix_flaky_test",
            "arguments" => %{
              "test_case_id" => "some-uuid"
            }
          }
        })

      response = json_response(conn, 200)
      assert response["id"] == 7
      messages = response["result"]["messages"]
      assert is_list(messages)
      assert hd(messages)["role"] == "user"
      assert hd(messages)["content"]["text"] =~ "Fix Flaky Test"
    end
  end
end
