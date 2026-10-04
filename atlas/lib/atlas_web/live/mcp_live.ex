defmodule AtlasWeb.MCPLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.MCP
  alias Atlas.MCP.OAuthSession
  alias Atlas.MCP.ServerConfiguration
  alias Atlas.Users

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("MCPs"))
     |> assign(:can_manage?, Users.has_scope?(socket.assigns.current_user, "admin:write"))
     |> assign_form(MCP.change_server_configuration(%ServerConfiguration{}))}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, load_servers(socket)}
  end

  defp load_servers(socket) do
    configurations = MCP.list_server_configurations()

    socket
    |> assign(:servers, MCP.list_servers(socket.assigns.current_user))
    |> assign(:configuration_ids, Map.new(configurations, &{&1.name, &1.id}))
  end

  def handle_event("validate_server", %{"server" => attrs}, %{assigns: %{can_manage?: true}} = socket) do
    changeset =
      %ServerConfiguration{}
      |> MCP.change_server_configuration(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("create_server", %{"server" => attrs}, %{assigns: %{can_manage?: true}} = socket) do
    case MCP.create_server_configuration(attrs) do
      {:ok, _server} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Server added."))
         |> assign_form(MCP.change_server_configuration(%ServerConfiguration{}))
         |> load_servers()}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("delete_server", %{"id" => id}, %{assigns: %{can_manage?: true}} = socket) do
    case MCP.delete_server_configuration(id) do
      {:ok, _server} ->
        {:noreply, socket |> put_flash(:info, gettext("Server removed.")) |> load_servers()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not remove server."))}
    end
  end

  def handle_event(_event, _params, socket) do
    {:noreply, put_flash(socket, :error, gettext("You cannot manage servers."))}
  end

  defp assign_form(socket, changeset), do: assign(socket, :server_form, to_form(changeset, as: :server))

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
                <:button :if={@can_manage? && Map.has_key?(@configuration_ids, entry.server.name)}>
                  <.button
                    id={"mcp-remove-#{entry.server.name}"}
                    phx-click="delete_server"
                    phx-value-id={@configuration_ids[entry.server.name]}
                    data-confirm={gettext("Remove this server and its saved connections?")}
                    label={gettext("Remove")}
                    size="small"
                    variant="secondary"
                  />
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

      <.card
        :if={@can_manage?}
        title={gettext("Add server")}
        icon="server"
        data-part="add-server-card"
      >
        <.card_section>
          <.form
            id="mcp-server-form"
            for={@server_form}
            phx-change="validate_server"
            phx-submit="create_server"
          >
            <.text_input id="mcp-server-name" field={@server_form[:name]} label={gettext("Name")} />
            <.text_input id="mcp-server-url" field={@server_form[:url]} label={gettext("Server URL")} />
            <.text_input
              id="mcp-server-authorization-url"
              field={@server_form[:authorization_url]}
              label={gettext("Authorization URL")}
            />
            <.text_input
              id="mcp-server-token-url"
              field={@server_form[:token_url]}
              label={gettext("Token URL")}
            />
            <.text_input
              id="mcp-server-registration-url"
              field={@server_form[:registration_url]}
              label={gettext("Registration URL (optional)")}
            />
            <.text_input
              id="mcp-server-scopes"
              field={@server_form[:scope_list]}
              label={gettext("OAuth scopes (space separated)")}
            />
            <.button id="mcp-server-create" type="submit" label={gettext("Add server")} />
          </.form>
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
