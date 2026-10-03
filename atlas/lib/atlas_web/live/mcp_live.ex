defmodule AtlasWeb.MCPLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.MCP
  alias Atlas.MCP.OAuthSession

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("MCPs"))}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, load_servers(socket)}
  end

  defp load_servers(socket) do
    assign(socket, :servers, MCP.list_servers(socket.assigns.current_user))
  end

  def render(assigns) do
    ~H"""
    <div id="mcps">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("MCPs")}</h1>
          <p data-part="description">
            {gettext("Upstream MCP servers proxied through Atlas with shared or per-user sessions.")}
          </p>
        </div>
      </div>

      <.card title={gettext("Servers")} icon="server" data-part="servers-card">
        <.card_section data-part="servers-table-section">
          <.table id="mcp-servers-table" rows={@servers}>
            <:col :let={entry} label={gettext("Server")}>
              <.text_and_description_cell
                label={entry.server.name}
                description={entry.server.url}
              />
            </:col>
            <:col :let={entry} label={gettext("Auth")}>
              <.badge
                id={"mcp-auth-#{entry.server.name}"}
                label={auth_label(entry.server.auth_type)}
                color="neutral"
                style="light-fill"
              />
            </:col>
            <:col :let={entry} label={gettext("Session")}>
              <div data-part="session-state">
                <.badge
                  id={"mcp-session-#{entry.server.name}"}
                  label={status_label(entry.status)}
                  color={status_color(entry.status)}
                  style="light-fill"
                />
                <span :if={entry.session && entry.session.expires_at} data-part="session-expiry">
                  {expires_label(entry.session)}
                </span>
              </div>
            </:col>
            <:col :let={entry} label={gettext("Actions")}>
              <.button_cell>
                <:button :if={entry.server.auth_type == :oauth2}>
                  <.button
                    id={"mcp-connect-#{entry.server.name}"}
                    href={~p"/mcps/#{entry.server.name}/authorize?return_to=/admin/mcps"}
                    label={action_label(entry.status)}
                    size="small"
                    variant={if(entry.status == :connected, do: "secondary", else: "primary")}
                  >
                    <:icon_right><.arrow_right /></:icon_right>
                  </.button>
                </:button>
              </.button_cell>
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="server"
                title={gettext("No MCP servers configured")}
                subtitle={gettext("Configured upstream MCP servers will show up here.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp auth_label(:oauth2), do: gettext("OAuth")
  defp auth_label(:bearer_token), do: gettext("Shared token")
  defp auth_label(:none), do: gettext("None")

  defp status_label(:connected), do: gettext("Connected")
  defp status_label(:shared_credentials), do: gettext("Shared")
  defp status_label(:not_connected), do: gettext("Not connected")
  defp status_label(:needs_authorization), do: gettext("Reconnect")
  defp status_label(:expired), do: gettext("Expired")

  defp status_color(status) when status in [:connected, :shared_credentials], do: "success"
  defp status_color(status) when status in [:needs_authorization, :expired], do: "destructive"
  defp status_color(_status), do: "neutral"

  defp action_label(:connected), do: gettext("Reconnect")
  defp action_label(_status), do: gettext("Connect")

  defp expires_label(%OAuthSession{expires_at: expires_at}) do
    gettext("Expires %{datetime}", datetime: Calendar.strftime(expires_at, "%Y-%m-%d %H:%M UTC"))
  end
end
