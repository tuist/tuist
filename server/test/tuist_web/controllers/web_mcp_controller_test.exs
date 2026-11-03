defmodule TuistWeb.WebMCPControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.MCP.Search
  alias TuistWeb.RateLimit

  @docs_tools ["list_tuist_files", "read_tuist_file", "search_tuist", "search_tuist_code"]

  setup do
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :codebase_search_enabled?, fn -> true end)
    stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)
    :ok
  end

  describe "POST /api/webmcp/public" do
    test "lists only the documentation and source tools", %{conn: conn} do
      names = conn |> list_tools("/api/webmcp/public") |> Enum.map(& &1["name"]) |> Enum.sort()

      assert names == @docs_tools
    end

    test "refuses to call a tool that is not public", %{conn: conn} do
      response =
        conn
        |> post_rpc("/api/webmcp/public", "tools/call", %{"name" => "list_accounts", "arguments" => %{}})
        |> json_response(200)

      assert response["error"]["code"] == -32_602
      refute response["result"]
    end

    test "calls tools without a session or CSRF token", %{conn: conn} do
      stub(Search, :search, fn %{"query" => "cache"} -> {:error, "Tuist search is unavailable: timeout"} end)

      result = call_tool(conn, "/api/webmcp/public", "search_tuist", %{"query" => "cache"})

      assert [%{"text" => "Tuist search is unavailable: timeout"}] = result["content"]
    end

    test "rate limits by client address", %{conn: conn} do
      test_process = self()
      stub(RateLimit.MCP, :hit, &Mimic.call_original(RateLimit.MCP, :hit, [&1]))

      stub(RateLimit, :hit, fn key, _opts ->
        send(test_process, {:rate_limit_key, key})
        {:allow, 1}
      end)

      post_rpc(conn, "/api/webmcp/public", "tools/list", %{})

      assert_received {:rate_limit_key, "mcp:unauth:" <> _address}
    end

    test "answers only tool listings and calls", %{conn: conn} do
      assert conn
             |> post_rpc("/api/webmcp/public", "prompts/list", %{})
             |> json_response(400)
             |> get_in(["error", "code"]) ==
               -32_600

      notification =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/webmcp/public", JSON.encode!(%{"jsonrpc" => "2.0", "method" => "tools/list"}))

      assert json_response(notification, 400)["error"]["code"] == -32_600

      nameless_call = post_rpc(build_conn(), "/api/webmcp/public", "tools/call", %{"arguments" => %{}})

      assert json_response(nameless_call, 400)["error"]["code"] == -32_600
    end

    test "documentation pages advertise it", %{conn: conn} do
      assert conn |> get("/en/docs/guides/install-tuist") |> html_response(200) =~
               ~s(<meta name="webmcp-endpoint" content="/api/webmcp/public">)
    end
  end

  defp list_tools(conn, path),
    do: conn |> post_rpc(path, "tools/list", %{}) |> json_response(200) |> get_in(["result", "tools"])

  defp call_tool(conn, path, name, arguments) do
    conn
    |> post_rpc(path, "tools/call", %{"name" => name, "arguments" => arguments})
    |> json_response(200)
    |> Map.fetch!("result")
  end

  defp post_rpc(conn, path, method, params) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> post(path, JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}))
  end
end
