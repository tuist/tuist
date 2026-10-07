defmodule AtlasWeb.MCPLiveTest do
  use ExUnit.Case, async: true

  alias Atlas.MCP
  alias Atlas.MCP.OAuthSession
  alias Atlas.MCP.Proxy.Server
  alias Atlas.MCP.ServerConfiguration
  alias AtlasWeb.MCPLive

  test "deployment-configured servers expose connection actions only" do
    document = render_page([oauth_entry()])

    assert exists?(document, "#mcp-actions-grafana[phx-hook=NooraDropdown]")
    assert exists?(document, "#mcp-connect-grafana[href='/mcps/grafana/authorize?return_to=/admin/mcps']")
    assert exists?(document, "#mcp-auth-grafana[data-part=cell][data-type=badge]")
    refute exists?(document, "#mcp-edit-grafana")
    refute exists?(document, "#mcp-remove-grafana")
  end

  test "database-configured servers expose edit and delete dropdown items" do
    document = render_page([oauth_entry()], configuration_ids: %{"grafana" => 42})

    assert exists?(document, "#mcp-edit-grafana[data-part=item][phx-click=open_edit_server_modal]")
    assert exists?(document, "#mcp-remove-grafana[data-part=item][phx-click=open_delete_server_modal]")
    refute exists?(document, "#mcp-remove-grafana[data-confirm]")
    assert exists?(document, "#delete-mcp-server-modal[phx-hook=NooraModal]")
  end

  test "read-only users have no edit or delete actions" do
    document = render_page([oauth_entry()], can_manage?: false, configuration_ids: %{"grafana" => 42})

    assert exists?(document, "#mcp-connect-grafana")
    refute exists?(document, "#mcp-edit-grafana")
    refute exists?(document, "#mcp-remove-grafana")
    refute exists?(document, "#delete-mcp-server-modal")
  end

  test "session status and expiry are separate parts of a padded cell" do
    entry = %{oauth_entry() | status: :connected, session: %OAuthSession{expires_at: ~U[2099-10-07 17:42:00Z]}}
    document = render_page([entry])

    assert exists?(document, "[data-part=cell][data-type=mcp-session] > #mcp-session-grafana")

    assert document
           |> LazyHTML.query("[data-type=mcp-session] > [data-part=session-expiry]")
           |> LazyHTML.text()
           |> String.trim() == "Expires Oct 7, 2099 at 17:42 UTC"

    assert document |> LazyHTML.query("#mcp-connect-grafana") |> LazyHTML.text() =~ "Reconnect"
  end

  test "expired sessions use past-tense expiry copy" do
    entry = %{
      oauth_entry()
      | status: :needs_authorization,
        session: %OAuthSession{expires_at: ~U[2020-09-18 10:22:00Z]}
    }

    document = render_page([entry])

    assert document |> LazyHTML.query("#mcp-session-grafana") |> LazyHTML.text() |> String.trim() ==
             "Reconnect required"

    assert document
           |> LazyHTML.query("[data-part=session-expiry]")
           |> LazyHTML.text()
           |> String.trim() == "Expired Sep 18, 2020 at 10:22 UTC"
  end

  test "sessions without expiry omit the secondary line" do
    document = render_page([oauth_entry()])

    refute exists?(document, "[data-part=session-expiry]")
  end

  test "shared credentials have no connection dropdown" do
    entry = %{
      oauth_entry()
      | server: %Server{name: "shared", url: "https://tools.example.org/mcp", auth_type: :bearer_token},
        status: :shared_credentials
    }

    document = render_page([entry])

    assert exists?(document, "#mcp-session-shared")
    refute exists?(document, "#mcp-actions-shared")
  end

  defp oauth_entry do
    %{
      server: %Server{name: "grafana", url: "https://mcp.grafana.com/mcp", auth_type: :oauth2},
      session: nil,
      status: :not_connected
    }
  end

  defp render_page(servers, overrides \\ []) do
    assigns = %{
      __changed__: %{},
      can_manage?: true,
      configuration_ids: %{},
      deleting_server: nil,
      delete_server_form: Phoenix.Component.to_form(%{"name" => ""}, as: :delete_server),
      server_form: Phoenix.Component.to_form(MCP.change_server_configuration(%ServerConfiguration{}), as: :server),
      servers: servers
    }

    # Expose portal template contents without requiring a browser to mount them.
    assigns
    |> Map.merge(Map.new(overrides))
    |> MCPLive.render()
    |> Phoenix.LiveViewTest.rendered_to_string()
    |> String.replace("<template", "<div")
    |> String.replace("</template>", "</div>")
    |> LazyHTML.from_fragment()
  end

  defp exists?(document, selector), do: document |> LazyHTML.query(selector) |> Enum.any?()
end
