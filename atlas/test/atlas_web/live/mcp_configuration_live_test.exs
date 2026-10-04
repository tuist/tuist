defmodule AtlasWeb.MCPConfigurationLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.MCP

  test "an administrator can add a server from the page", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["admin:write"]})
    {:ok, view, _html} = live(conn, ~p"/admin/mcps")

    assert has_element?(view, "#mcp-server-form")

    view
    |> form("#mcp-server-form",
      server: %{
        name: "example",
        url: "https://tools.example.org/mcp",
        authorization_url: "https://tools.example.org/oauth/authorize",
        token_url: "https://tools.example.org/oauth/token",
        scope_list: "tools:read"
      }
    )
    |> render_submit()

    assert has_element?(view, "#mcp-connect-example")
    assert has_element?(view, "#mcp-remove-example")
    assert Enum.any?(MCP.list_server_configurations(), &(&1.name == "example"))
  end

  test "read-only administrators cannot create servers", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["admin:read"]})
    {:ok, view, _html} = live(conn, ~p"/admin/mcps")

    refute has_element?(view, "#mcp-server-form")
    refute has_element?(view, "#mcp-remove-example")
  end
end
