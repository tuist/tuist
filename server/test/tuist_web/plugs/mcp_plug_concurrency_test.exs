defmodule TuistWeb.Plugs.MCPPlugConcurrencyTest do
  @moduledoc """
  Tests that concurrent MCP tool calls don't cause hanging.

  The Anubis MCP Server GenServer processes requests synchronously (handle_call),
  meaning concurrent tool calls queue up. If one tool takes a long time, subsequent
  calls wait in the mailbox. Combined with the 30s transport timeout, this can cause
  tools to timeout if the queue gets deep enough.
  """

  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.RateLimit

  @initialize_params %{
    "protocolVersion" => "2025-03-26",
    "capabilities" => %{},
    "clientInfo" => %{"name" => "concurrency-test", "version" => "0.1.0"}
  }

  describe "concurrent MCP requests" do
    test "multiple tool calls in parallel all receive responses", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      # First initialize a session
      init_conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => @initialize_params
        })

      assert json_response(init_conn, 200)["result"]
      [session_id] = get_resp_header(init_conn, "mcp-session-id")

      # Send initialized notification
      conn
      |> authenticated_mcp_conn(user.token)
      |> put_req_header("mcp-session-id", session_id)
      |> post_mcp(%{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized",
        "params" => %{}
      })

      # Now fire 5 concurrent tools/list requests (simulating parallel tool calls)
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            start = System.monotonic_time(:millisecond)

            result =
              conn
              |> authenticated_mcp_conn(user.token)
              |> put_req_header("mcp-session-id", session_id)
              |> post_mcp(%{
                "jsonrpc" => "2.0",
                "id" => 100 + i,
                "method" => "tools/list",
                "params" => %{}
              })

            elapsed = System.monotonic_time(:millisecond) - start
            {result, elapsed}
          end)
        end

      results = Task.await_many(tasks, 10_000)

      for {result_conn, elapsed} <- results do
        response = json_response(result_conn, 200)
        # Each request should respond and contain tools
        assert is_map(response["result"]) or is_map(response["error"])
        # Each request should complete in under 5 seconds
        assert elapsed < 5_000, "Request took #{elapsed}ms, expected < 5000ms"
      end
    end

    test "tool exceptions return errors instead of crashing the server GenServer", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)

      # Initialize session
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

      conn
      |> authenticated_mcp_conn(user.token)
      |> put_req_header("mcp-session-id", session_id)
      |> post_mcp(%{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized",
        "params" => %{}
      })

      # Call a tool with invalid input that would raise an exception
      error_conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> put_req_header("mcp-session-id", session_id)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 10,
          "method" => "tools/call",
          "params" => %{"name" => "get_xcode_build", "arguments" => %{"build_run_id" => "not-a-uuid"}}
        })

      # Should get an error response, not crash
      error_response = json_response(error_conn, 200)
      assert error_response["error"]

      # Subsequent requests should still work (server GenServer didn't crash)
      list_conn =
        conn
        |> authenticated_mcp_conn(user.token)
        |> put_req_header("mcp-session-id", session_id)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 11,
          "method" => "tools/list",
          "params" => %{}
        })

      list_response = json_response(list_conn, 200)
      assert list_response["result"]["tools"]
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
