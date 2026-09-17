defmodule AtlasWeb.MCPLiveTest do
  use ExUnit.Case, async: true

  alias Atlas.MCP.Proxy.Server
  alias AtlasWeb.MCPLive

  test "renders configured MCP servers and connect actions" do
    html =
      Phoenix.LiveViewTest.rendered_to_string(
        MCPLive.render(%{
          __changed__: %{},
          servers: [
            %{
              server: %Server{
                name: "grafana",
                url: "https://mcp.grafana.com/mcp",
                auth_type: :oauth2
              },
              session: nil,
              status: :not_connected
            }
          ]
        })
      )

    assert html =~ "MCPs"
    assert html =~ "grafana"
    assert html =~ "OAuth"
    assert html =~ "Not connected"
    assert html =~ ~s(href="/mcps/grafana/authorize?return_to=/admin/mcps")
  end
end
