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
     |> assign(:editing_server, nil)
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

  def handle_event("open_server_modal", _params, %{assigns: %{can_manage?: true}} = socket) do
    {:noreply,
     socket
     |> assign(:editing_server, nil)
     |> assign_form(MCP.change_server_configuration(%ServerConfiguration{}))
     |> push_event("open-modal", %{id: "add-mcp-server-modal"})}
  end

  def handle_event("open_edit_server_modal", %{"id" => id}, %{assigns: %{can_manage?: true}} = socket) do
    case MCP.get_server_configuration(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Server not found."))}

      server ->
        server = %{server | scope_list: Enum.join(server.scopes, " ")}

        {:noreply,
         socket
         |> assign(:editing_server, server)
         |> assign_form(MCP.change_server_configuration(server))
         |> push_event("open-modal", %{id: "edit-mcp-server-modal"})}
    end
  end

  def handle_event("close_server_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_form(MCP.change_server_configuration(%ServerConfiguration{}))
     |> push_event("close-modal", %{id: "add-mcp-server-modal"})}
  end

  def handle_event("close_edit_server_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_server, nil)
     |> assign_form(MCP.change_server_configuration(%ServerConfiguration{}))
     |> push_event("close-modal", %{id: "edit-mcp-server-modal"})}
  end

  def handle_event("validate_server", %{"server" => attrs}, %{assigns: %{can_manage?: true}} = socket) do
    changeset =
      (socket.assigns.editing_server || %ServerConfiguration{})
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
         |> load_servers()
         |> push_event("close-modal", %{id: "add-mcp-server-modal"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign_form(Map.put(changeset, :action, :validate))
         |> push_event("open-modal", %{id: "add-mcp-server-modal"})}
    end
  end

  def handle_event(
        "update_server",
        %{"server" => attrs},
        %{assigns: %{can_manage?: true, editing_server: %ServerConfiguration{} = server}} = socket
      ) do
    case MCP.update_server_configuration(server.id, attrs) do
      {:ok, _server} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Server updated."))
         |> assign(:editing_server, nil)
         |> assign_form(MCP.change_server_configuration(%ServerConfiguration{}))
         |> load_servers()
         |> push_event("close-modal", %{id: "edit-mcp-server-modal"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update server."))}
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

  attr :form, :any, required: true
  attr :prefix, :string, required: true

  defp server_fields(assigns) do
    ~H"""
    <.text_input id={"#{@prefix}-name"} field={@form[:name]} label={gettext("Name")} />
    <.text_input id={"#{@prefix}-url"} field={@form[:url]} label={gettext("Server URL")} />
    <.text_input
      id={"#{@prefix}-authorization-url"}
      field={@form[:authorization_url]}
      label={gettext("Authorization URL")}
    />
    <.text_input id={"#{@prefix}-token-url"} field={@form[:token_url]} label={gettext("Token URL")} />
    <.text_input
      id={"#{@prefix}-registration-url"}
      field={@form[:registration_url]}
      label={gettext("Registration URL (optional)")}
    />
    <.text_input
      id={"#{@prefix}-scopes"}
      field={@form[:scope_list]}
      label={gettext("OAuth scopes (space separated)")}
    />
    """
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
        <div :if={@can_manage?} data-part="actions">
          <.modal
            id="add-mcp-server-modal"
            title={gettext("Add server")}
            description={gettext("Connect an upstream server using per-user authorization.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_server_modal"
          >
            <:trigger :let={attrs}>
              <.button
                label={gettext("Add server")}
                size="medium"
                variant="primary"
                phx-click="open_server_modal"
                {attrs}
              >
                <:icon_left><.circle_plus /></:icon_left>
              </.button>
            </:trigger>
            <:header_icon><.server /></:header_icon>

            <.form
              id="mcp-server-form"
              for={@server_form}
              phx-change="validate_server"
              phx-submit="create_server"
              data-part="form"
            >
              <.server_fields form={@server_form} prefix="mcp-server" />
            </.form>

            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    label={gettext("Cancel")}
                    variant="secondary"
                    size="medium"
                    type="button"
                    phx-click="close_server_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="mcp-server-create"
                    label={gettext("Add server")}
                    size="medium"
                    variant="primary"
                    type="submit"
                    form="mcp-server-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>

          <.modal
            id="edit-mcp-server-modal"
            title={gettext("Edit server")}
            description={gettext("Changing server settings disconnects all saved user connections.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_edit_server_modal"
          >
            <:trigger :let={attrs}><button type="button" hidden {attrs}></button></:trigger>
            <:header_icon><.server /></:header_icon>

            <.form
              id="mcp-server-edit-form"
              for={@server_form}
              phx-change="validate_server"
              phx-submit="update_server"
              data-part="form"
            >
              <.server_fields form={@server_form} prefix="mcp-server-edit" />
            </.form>

            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    label={gettext("Cancel")}
                    variant="secondary"
                    size="medium"
                    type="button"
                    phx-click="close_edit_server_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="mcp-server-update"
                    label={gettext("Save changes")}
                    size="medium"
                    variant="primary"
                    type="submit"
                    form="mcp-server-edit-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
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
                    id={"mcp-edit-#{entry.server.name}"}
                    phx-click="open_edit_server_modal"
                    phx-value-id={@configuration_ids[entry.server.name]}
                    label={gettext("Edit")}
                    size="small"
                    variant="secondary"
                  />
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
