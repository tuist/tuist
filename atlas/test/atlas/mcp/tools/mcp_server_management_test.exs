defmodule Atlas.MCP.Tools.MCPServerManagementTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Audit.Activity
  alias Atlas.MCP
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.CreateMCPServer
  alias Atlas.MCP.Tools.DeleteMCPServer

  test "administrator write access can add and remove a server" do
    conn = %{scopes: ["admin:write"]} |> insert_user!() |> mcp_conn()
    args = server_args()

    assert {:ok, %{server: %{name: name, read_only: true}}} = execute_tool(CreateMCPServer, conn, args)
    assert name == args["name"]
    assert MCP.get_server_configuration_by_name(name).scopes == ["tools:read"]

    assert {:ok, %{deleted: true, name: ^name}} = execute_tool(DeleteMCPServer, conn, %{"name" => name})
    assert is_nil(MCP.get_server_configuration_by_name(name))
  end

  test "shared API keys can be added without OAuth endpoints and never enter responses or audits" do
    conn = %{scopes: ["admin:write"]} |> insert_user!() |> mcp_conn()
    args = bearer_args()

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "create_mcp_server", "arguments" => args}
      })

    refute response["result"]["isError"]
    refute inspect(response) =~ args["bearer_token"]
    assert MCP.get_server_configuration_by_name(args["name"]).bearer_token == args["bearer_token"]
    assert activity = Repo.get_by(Activity, action: "mcp.tool_called", target_id: "create_mcp_server")
    assert activity.metadata["arguments"]["name"] == args["name"]
    refute Map.has_key?(activity.metadata["arguments"], "bearer_token")
    refute inspect(Repo.all(Activity)) =~ args["bearer_token"]
  end

  test "invalid credentials are omitted from failed-call audits too" do
    conn = %{scopes: ["admin:write"]} |> insert_user!() |> mcp_conn()
    args = Map.put(bearer_args(), "bearer_token", "Bearer invalid-secret")

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "create_mcp_server", "arguments" => args}
      })

    assert response["result"]["isError"]
    refute inspect(response) =~ "invalid-secret"
    refute inspect(Repo.all(Activity)) =~ "invalid-secret"
  end

  test "read-only access cannot add or remove servers with either authentication type" do
    writer = %{scopes: ["admin:write"]} |> insert_user!() |> mcp_conn()
    reader = %{scopes: ["admin:read"]} |> insert_user!() |> mcp_conn()

    for args <- [server_args(), bearer_args()] do
      assert {:error, message} = execute_tool(CreateMCPServer, reader, args)
      assert message =~ "admin:write"
      assert is_nil(MCP.get_server_configuration_by_name(args["name"]))

      assert {:ok, _} = execute_tool(CreateMCPServer, writer, args)
      assert {:error, message} = execute_tool(DeleteMCPServer, reader, %{"name" => args["name"]})
      assert message =~ "admin:write"
      assert MCP.get_server_configuration_by_name(args["name"])
    end
  end

  defp server_args do
    %{
      "name" => "example-#{System.unique_integer([:positive])}",
      "url" => "https://tools.example.org/mcp",
      "authorization_url" => "https://tools.example.org/oauth/authorize",
      "token_url" => "https://tools.example.org/oauth/token",
      "scopes" => ["tools:read"]
    }
  end

  defp bearer_args do
    %{
      "name" => "integral-#{System.unique_integer([:positive])}",
      "url" => "https://tools.example.org/mcp",
      "auth_type" => "bearer_token",
      "bearer_token" => "integral-tool-test-secret"
    }
  end
end
