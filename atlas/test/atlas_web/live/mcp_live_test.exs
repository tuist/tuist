defmodule AtlasWeb.MCPLiveTest do
  use ExUnit.Case, async: true

  alias Atlas.MCP.Proxy.Server
  alias Atlas.MCP.ServerConfiguration
  alias AtlasWeb.MCPLive

  test "renders configured MCP servers and connect actions" do
    html =
      Phoenix.LiveViewTest.rendered_to_string(
        MCPLive.render(%{
          __changed__: %{},
          can_manage?: true,
          configuration_ids: %{},
          server_form:
            Phoenix.Component.to_form(Atlas.MCP.change_server_configuration(%ServerConfiguration{}), as: :server),
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
