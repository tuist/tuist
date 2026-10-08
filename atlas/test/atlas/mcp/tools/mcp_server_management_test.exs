defmodule Atlas.MCP.Tools.MCPServerManagementTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP
  alias Atlas.MCP.Tools.CreateMCPServer
  alias Atlas.MCP.Tools.DeleteMCPServer

  @server_args %{
    "name" => "example",
    "url" => "https://tools.example.org/mcp",
    "authorization_url" => "https://tools.example.org/oauth/authorize",
    "token_url" => "https://tools.example.org/oauth/token",
    "scopes" => ["tools:read"]
  }

  test "administrator write access can add and remove a server" do
    conn = %{scopes: ["admin:write"]} |> insert_user!() |> mcp_conn()

    assert {:ok, %{server: %{name: "example", read_only: true}}} =
             execute_tool(CreateMCPServer, conn, @server_args)

    assert MCP.get_server_configuration_by_name("example").scopes == ["tools:read"]

    assert {:ok, %{deleted: true, name: "example"}} =
             execute_tool(DeleteMCPServer, conn, %{"name" => "example"})

    assert is_nil(MCP.get_server_configuration_by_name("example"))
  end

  test "read-only access cannot add or remove servers" do
    writer = %{scopes: ["admin:write"]} |> insert_user!() |> mcp_conn()
    reader = %{scopes: ["admin:read"]} |> insert_user!() |> mcp_conn()

    assert {:error, message} = execute_tool(CreateMCPServer, reader, @server_args)
    assert message =~ "admin:write"
    assert is_nil(MCP.get_server_configuration_by_name("example"))

    assert {:ok, _} = execute_tool(CreateMCPServer, writer, @server_args)
    assert {:error, message} = execute_tool(DeleteMCPServer, reader, %{"name" => "example"})
    assert message =~ "admin:write"
    assert MCP.get_server_configuration_by_name("example")
  end
end
