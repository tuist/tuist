defmodule AtlasWeb.MCPLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.MCP
  alias Atlas.MCP.OAuthSession
  alias Atlas.MCP.OperatorGrant

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("MCPs"))}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, load_servers(socket)}
  end

  # There is no form here to start a request. Asking for a grant up front meant
  # naming the customer before looking at anything, which is backwards: the
  # refused tool call already knows which account it needed. The proxy turns
  # that refusal into a link to the reason form, so this page reports the grant
  # and can clear it, nothing more. The grant itself is never pasted — ops
  # appends it to `return_to` and redirects, so the bearer never reaches a
  # clipboard.
  def handle_event("clear_operator_grant", %{"server" => server_name}, socket) do
    {:ok, _} = MCP.delete_operator_grant(socket.assigns.current_user, server_name, interface: "dashboard")

    {:noreply, socket |> put_flash(:info, gettext("Operator grant cleared.")) |> load_servers()}
  end

  defp load_servers(socket) do
    user = socket.assigns.current_user

    servers =
      user
      |> MCP.list_servers()
      |> Enum.map(&Map.put(&1, :operator_grant, operator_grant_for(user, &1)))

    assign(socket, :servers, servers)
  end

  defp operator_grant_for(user, %{server: %{operator_grant_header: header, name: name}}) when is_binary(header) do
    MCP.get_operator_grant(user, name)
  end

  defp operator_grant_for(_user, _entry), do: nil

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
            <:col :let={entry} label={gettext("Operator grant")}>
              <div :if={entry.server.operator_grant_header} data-part="operator-grant">
                <span :if={entry.operator_grant} data-part="operator-grant-state">
                  {grant_label(entry.operator_grant)}
                </span>
                <span :if={is_nil(entry.operator_grant)} data-part="operator-grant-state">
                  {gettext("Requested when a tool call needs it")}
                </span>
                <.button
                  :if={entry.operator_grant}
                  id={"mcp-grant-clear-#{entry.server.name}"}
                  label={gettext("Clear")}
                  size="small"
                  variant="secondary"
                  phx-click="clear_operator_grant"
                  phx-value-server={entry.server.name}
                />
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

  defp grant_label(%OperatorGrant{account_handle: handle} = grant) do
    if OperatorGrant.active?(grant) do
      gettext("%{account} until %{datetime}",
        account: handle,
        datetime: Calendar.strftime(grant.expires_at, "%Y-%m-%d %H:%M UTC")
      )
    else
      gettext("Expired")
    end
  end

  defp expires_label(%OAuthSession{expires_at: expires_at}) do
    gettext("Expires %{datetime}", datetime: Calendar.strftime(expires_at, "%Y-%m-%d %H:%M UTC"))
  end
end
