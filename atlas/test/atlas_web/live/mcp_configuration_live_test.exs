defmodule AtlasWeb.MCPConfigurationLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.MCP

  test "an administrator can add a server from the page", %{conn: conn} do
    attrs = server_attrs()
    {conn, _user} = log_in_user(conn, %{scopes: ["admin:write"]})
    {:ok, view, _html} = live(conn, ~p"/admin/mcps")

    assert has_element?(view, "#add-mcp-server-modal [data-part=trigger]")
    refute has_element?(view, "#mcp-server-form")
    view |> element("#add-mcp-server-modal [data-part=trigger]") |> render_click()

    render_hook(view, "create_server", %{"server" => attrs})

    assert has_element?(view, "#mcp-actions-#{attrs.name}[phx-hook=NooraDropdown]")
    assert has_portal_element?(view, "#mcp-connect-#{attrs.name}")
    assert has_portal_element?(view, "#mcp-edit-#{attrs.name}")
    assert has_portal_element?(view, "#mcp-remove-#{attrs.name}")
    assert MCP.get_server_configuration_by_name(attrs.name)
  end

  test "an administrator can create a shared-key server and rotate its key", %{conn: conn} do
    attrs = %{
      name: "integral-#{System.unique_integer([:positive])}",
      url: "https://tools.example.org/mcp",
      auth_type: "bearer_token",
      bearer_token: "original-key"
    }

    {conn, _user} = log_in_user(conn, %{scopes: ["admin:write"]})
    {:ok, view, _html} = live(conn, ~p"/admin/mcps")

    render_hook(view, "validate_server", %{"server" => Map.delete(attrs, :bearer_token)})
    assert has_portal_element?(view, "#mcp-server-bearer-token[type=password]")
    refute has_portal_element?(view, "#mcp-server-authorization-url")
    render_hook(view, "create_server", %{"server" => attrs})

    server = MCP.get_server_configuration_by_name(attrs.name)
    assert server.bearer_token == "original-key"
    assert has_portal_element?(view, "#mcp-edit-#{server.name}")
    refute has_portal_element?(view, "#mcp-connect-#{server.name}")

    render_hook(view, "open_edit_server_modal", %{"id" => server.id})
    assert has_portal_element?(view, "#mcp-server-edit-bearer-token[value='']")
    render_hook(view, "update_server", %{"server" => %{bearer_token: ""}})
    assert MCP.get_server_configuration(server.id).bearer_token == "original-key"

    render_hook(view, "open_edit_server_modal", %{"id" => server.id})
    render_hook(view, "update_server", %{"server" => %{bearer_token: "rotated-key"}})
    assert MCP.get_server_configuration(server.id).bearer_token == "rotated-key"
  end

  test "an administrator can edit a server from its modal", %{conn: conn} do
    {:ok, server} = MCP.create_server_configuration(server_attrs())
    {conn, _user} = log_in_user(conn, %{scopes: ["admin:write"]})
    {:ok, view, _html} = live(conn, ~p"/admin/mcps")

    render_hook(view, "open_edit_server_modal", %{"id" => server.id})
    attrs = server_attrs()
    render_hook(view, "update_server", %{"server" => attrs})

    assert has_portal_element?(view, "#mcp-edit-#{attrs.name}")
    refute has_portal_element?(view, "#mcp-edit-#{server.name}")
    assert MCP.get_server_configuration_by_name(attrs.name)
  end

  test "delete opens a confirmation modal and requires the server name", %{conn: conn} do
    {:ok, server} = MCP.create_server_configuration(server_attrs())
    {conn, user} = log_in_user(conn, %{scopes: ["admin:write"]})
    {:ok, upstream} = MCP.get_server(server.name)
    {:ok, _session} = MCP.upsert_oauth_session(user, upstream, %{access_token: "access-token"})
    {:ok, view, _html} = live(conn, ~p"/admin/mcps")

    render_hook(view, "open_delete_server_modal", %{"id" => server.id})

    assert_push_event(view, "open-modal", %{id: "delete-mcp-server-modal"})
    assert MCP.get_server_configuration(server.id)
    assert MCP.get_oauth_session(user, server.name)

    render_hook(view, "delete_server", %{"delete_server" => %{"name" => "wrong-name"}})

    assert MCP.get_server_configuration(server.id)
    assert MCP.get_oauth_session(user, server.name)

    render_hook(view, "delete_server", %{"delete_server" => %{"name" => server.name}})

    assert_push_event(view, "close-modal", %{id: "delete-mcp-server-modal"})
    refute has_element?(view, "#mcp-actions-#{server.name}")
    refute MCP.get_server_configuration(server.id)
    refute MCP.get_oauth_session(user, server.name)
  end

  test "cancelling deletion preserves the server and clears the pending action", %{conn: conn} do
    {:ok, server} = MCP.create_server_configuration(server_attrs())
    {conn, _user} = log_in_user(conn, %{scopes: ["admin:write"]})
    {:ok, view, _html} = live(conn, ~p"/admin/mcps")

    render_hook(view, "open_delete_server_modal", %{"id" => server.id})
    render_hook(view, "close_delete_server_modal", %{})

    assert_push_event(view, "close-modal", %{id: "delete-mcp-server-modal"})
    render_hook(view, "delete_server", %{"delete_server" => %{"name" => server.name}})

    assert MCP.get_server_configuration(server.id)
    assert has_element?(view, "#mcp-actions-#{server.name}")
  end

  test "read-only administrators cannot create or delete servers", %{conn: conn} do
    {:ok, server} = MCP.create_server_configuration(server_attrs())
    {conn, _user} = log_in_user(conn, %{scopes: ["admin:read"]})
    {:ok, view, _html} = live(conn, ~p"/admin/mcps")

    refute has_element?(view, "#add-mcp-server-modal [data-part=trigger]")
    refute has_element?(view, "#mcp-server-form")
    refute has_portal_element?(view, "#mcp-remove-#{server.name}")
    refute has_portal_element?(view, "#mcp-edit-#{server.name}")

    render_hook(view, "open_delete_server_modal", %{"id" => server.id})
    render_hook(view, "delete_server", %{"delete_server" => %{"name" => server.name}})

    render_hook(view, "create_server", %{
      "server" => %{
        name: "denied-#{System.unique_integer([:positive])}",
        url: "https://tools.example.org/mcp",
        auth_type: "bearer_token",
        bearer_token: "denied-key"
      }
    })

    render_hook(view, "open_edit_server_modal", %{"id" => server.id})
    render_hook(view, "update_server", %{"server" => %{auth_type: "bearer_token", bearer_token: "denied-key"}})

    assert MCP.get_server_configuration(server.id).auth_type == "oauth2"
    assert length(MCP.list_server_configurations()) == 1
  end

  # LiveViewTest does not mount portals, so expose their template contents to selectors.
  defp has_portal_element?(view, selector) do
    view
    |> render()
    |> String.replace("<template", "<div")
    |> String.replace("</template>", "</div>")
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.any?()
  end

  defp server_attrs do
    %{
      name: "example-#{System.unique_integer([:positive])}",
      url: "https://tools.example.org/mcp",
      authorization_url: "https://tools.example.org/oauth/authorize",
      token_url: "https://tools.example.org/oauth/token",
      scope_list: "tools:read"
    }
  end
end
