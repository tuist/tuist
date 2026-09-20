defmodule AtlasWeb.Admin.RolesLive do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.CheckboxControl, only: [checkbox_control: 1]

  alias Atlas.Authorization
  alias Atlas.Authorization.Role
  alias Atlas.Authorization.Roles

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Roles · Atlas"))
     |> assign(:areas, Authorization.areas())
     |> assign(:area_slugs, Authorization.area_slugs())
     |> assign_roles()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:role, nil)
    |> assign(:form, nil)
    |> assign(:selected_scopes, MapSet.new())
  end

  defp apply_action(socket, :new, _params) do
    role = %Role{scopes: []}

    socket
    |> assign(:role, role)
    |> assign(:form, to_form(Roles.change_role(role), as: :role))
    |> assign(:selected_scopes, MapSet.new())
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case Roles.get_role(id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Role not found."))
        |> push_navigate(to: ~p"/admin/roles")

      role ->
        socket
        |> assign(:role, role)
        |> assign(:form, to_form(Roles.change_role(role), as: :role))
        |> assign(:selected_scopes, MapSet.new(role.scopes))
        |> assign(:delete_role_form, to_form(%{"slug" => ""}, as: :delete_role))
    end
  end

  @impl true
  def handle_event("validate", %{"role" => attrs}, socket) do
    scopes = MapSet.to_list(socket.assigns.selected_scopes)
    attrs = Map.put(attrs, "scopes", scopes)

    changeset =
      socket.assigns.role
      |> Roles.change_role(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :role))}
  end

  def handle_event("toggle_scope", %{"scope" => scope}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_scopes, scope) do
        MapSet.delete(socket.assigns.selected_scopes, scope)
      else
        MapSet.put(socket.assigns.selected_scopes, scope)
      end

    {:noreply, assign(socket, :selected_scopes, selected)}
  end

  def handle_event("save", %{"role" => attrs}, socket) do
    attrs = Map.put(attrs, "scopes", MapSet.to_list(socket.assigns.selected_scopes))

    case socket.assigns.live_action do
      :new -> create_role(socket, attrs)
      :edit -> update_role(socket, attrs)
    end
  end

  def handle_event("close_delete_role_modal", _, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "delete-role-modal"})}
  end

  def handle_event("delete", %{"delete_role" => %{"slug" => confirmation}}, socket) do
    role = socket.assigns.role

    cond do
      is_nil(role) ->
        {:noreply, put_flash(socket, :error, gettext("Role not found."))}

      role.builtin ->
        {:noreply, put_flash(socket, :error, gettext("Built-in roles cannot be deleted."))}

      String.trim(confirmation) != role.slug ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Type the role slug exactly to confirm the deletion.")
         )}

      true ->
        case Roles.delete_role(role) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Role deleted."))
             |> push_navigate(to: ~p"/admin/roles")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete role."))}
        end
    end
  end

  defp create_role(socket, attrs) do
    case Roles.create_role(attrs) do
      {:ok, _role} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Role created."))
         |> push_navigate(to: ~p"/admin/roles")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :role))}
    end
  end

  defp update_role(socket, attrs) do
    case Roles.update_role(socket.assigns.role, attrs) do
      {:ok, _role} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Role updated."))
         |> push_navigate(to: ~p"/admin/roles")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :role))}
    end
  end

  defp assign_roles(socket), do: assign(socket, :roles, Roles.list_roles())

  @impl true
  def render(assigns) do
    ~H"""
    <section id="admin-roles" data-part="admin-roles">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">
            {case @live_action do
              :index -> gettext("Roles")
              :new -> gettext("New role")
              :edit -> @role.name
            end}
          </h1>
          <p data-part="description">
            {case @live_action do
              :index ->
                gettext("Bundle scopes into roles, then assign them to users on the Users page.")

              :new ->
                gettext("Give the role a name, then choose which areas it grants access to.")

              :edit ->
                @role.description || gettext("Edit this role's details, scopes, and assignments.")
            end}
          </p>
        </div>
        <div :if={@live_action == :index} data-part="header-actions">
          <.link navigate={~p"/admin/roles/new"}>
            <.button
              id="admin-role-create-trigger"
              label={gettext("New role")}
              size="medium"
              type="button"
            >
              <:icon_left><.plus /></:icon_left>
            </.button>
          </.link>
        </div>
      </div>

      <%= case @live_action do %>
        <% :index -> %>
          <.render_index roles={@roles} />
        <% action when action in [:new, :edit] -> %>
          <.render_form
            live_action={@live_action}
            form={@form}
            role={@role}
            areas={@areas}
            area_slugs={@area_slugs}
            selected_scopes={@selected_scopes}
            delete_role_form={assigns[:delete_role_form]}
          />
      <% end %>
    </section>
    """
  end

  attr :roles, :list, required: true

  defp render_index(assigns) do
    ~H"""
    <.card title={gettext("All roles")} icon="lock" data-part="roles-card">
      <.card_section data-part="roles-table-section">
        <.table_empty_state
          :if={@roles == []}
          icon="lock"
          title={gettext("No roles yet")}
          subtitle={gettext("Create the first role to start bundling scopes.")}
        />

        <.table
          :if={@roles != []}
          id="admin-roles-table"
          rows={@roles}
          row_key={& &1.id}
          row_navigate={fn role -> ~p"/admin/roles/#{role.id}" end}
        >
          <:col :let={role} label={gettext("Role")}>
            <.text_and_description_cell
              label={role.name}
              description={role.description || role.slug}
              icon="lock"
            />
          </:col>
          <:col :let={role} label={gettext("Scopes")}>
            <.text_cell label={"#{length(role.scopes)}"} />
          </:col>
          <:col :let={role} label={gettext("Type")}>
            <.badge_cell
              id={"role-type-#{role.id}"}
              label={if role.builtin, do: gettext("Built-in"), else: gettext("Custom")}
              color={if role.builtin, do: "success", else: "neutral"}
              style="light-fill"
            />
          </:col>
        </.table>
      </.card_section>
    </.card>
    """
  end

  attr :live_action, :atom, required: true
  attr :form, :any, required: true
  attr :role, :any, required: true
  attr :areas, :map, required: true
  attr :area_slugs, :list, required: true
  attr :selected_scopes, :any, required: true
  attr :delete_role_form, :any, default: nil

  defp render_form(assigns) do
    ~H"""
    <.form for={@form} id="role-form" phx-change="validate" phx-submit="save">
      <.card title={gettext("Details")} icon="lock" data-part="role-details-card">
        <.card_section data-part="role-details-card-section">
          <.text_input
            id="role-name"
            field={@form[:name]}
            label={gettext("Name")}
            sublabel={gettext("What users see when assigning this role.")}
            required
            show_required
            show_suffix={false}
          />

          <.text_input
            id="role-slug"
            field={@form[:slug]}
            label={gettext("Slug")}
            sublabel={gettext("Used in URLs and audit logs. Lowercase letters, digits, and dashes.")}
            required
            show_required
            show_suffix={false}
            disabled={@role && @role.builtin}
          />

          <.text_area
            id="role-description"
            field={@form[:description]}
            label={gettext("Description")}
            sublabel={gettext("Optional. Explain when to assign this role.")}
            rows={2}
          />
        </.card_section>
      </.card>

      <.card title={gettext("Scopes")} icon="settings" data-part="role-scopes-card">
        <.card_section data-part="role-scopes-card-section">
          <.table id="role-scopes-table" rows={@area_slugs} row_key={&"scope-row-#{&1}"}>
            <:col :let={area} label={gettext("Area")}>
              <.text_and_description_cell
                label={area}
                description={Map.get(@areas, area)}
              />
            </:col>
            <:col :let={area} label={gettext("Read")}>
              <.scope_toggle area={area} action="read" selected_scopes={@selected_scopes} />
            </:col>
            <:col :let={area} label={gettext("Write")}>
              <.scope_toggle area={area} action="write" selected_scopes={@selected_scopes} />
            </:col>
          </.table>

          <div data-part="form-actions">
            <.link navigate={~p"/admin/roles"}>
              <.button
                label={gettext("Cancel")}
                variant="secondary"
                size="medium"
                type="button"
              />
            </.link>
            <.button
              id="save-role"
              label={
                if @live_action == :new, do: gettext("Create role"), else: gettext("Save changes")
              }
              size="medium"
              variant="primary"
              type="submit"
            />
          </div>
        </.card_section>
      </.card>
    </.form>

    <.card_section
      :if={@live_action == :edit}
      data-part="delete-role-card-section"
    >
      <div data-part="header">
        <span data-part="title">{gettext("Delete role")}</span>
        <span data-part="subtitle">
          {if @role.builtin,
            do: gettext("This is a built-in role that Atlas depends on. It cannot be deleted."),
            else: gettext("Deleting the role will remove it from every user that holds it.")}
        </span>
      </div>
      <div data-part="content">
        <.form
          data-part="form"
          for={@delete_role_form}
          id="delete-role-form"
          phx-submit="delete"
        >
          <.modal
            :if={not @role.builtin}
            id="delete-role-modal"
            title={gettext("Are you sure you want to delete this?")}
            header_size="large"
            on_dismiss="close_delete_role_modal"
          >
            <:trigger :let={attrs}>
              <.button
                label={gettext("Delete role")}
                variant="destructive"
                size="medium"
                {attrs}
              />
            </:trigger>
            <.line_divider />
            <.alert
              status="warning"
              type="secondary"
              size="small"
              title={
                gettext(
                  "Deleting the role will permanently remove it and unbundle its scopes from every user that holds it."
                )
              }
            />
            <.text_input
              label={gettext("Enter this role's slug to confirm")}
              field={@delete_role_form[:slug]}
              type="basic"
              placeholder={@role.slug}
            />
            <.line_divider />
            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    type="reset"
                    label={gettext("Cancel")}
                    variant="secondary"
                    phx-click="close_delete_role_modal"
                  />
                </:action>
                <:action>
                  <.button type="submit" label={gettext("Delete")} variant="destructive" />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
          <.button
            :if={@role.builtin}
            label={gettext("Delete role")}
            variant="destructive"
            size="medium"
            type="button"
            disabled
          />
        </.form>
      </div>
    </.card_section>
    """
  end

  attr :area, :string, required: true
  attr :action, :string, required: true
  attr :selected_scopes, :any, required: true

  defp scope_toggle(assigns) do
    assigns = assign(assigns, :scope, "#{assigns.area}:#{assigns.action}")
    assigns = assign(assigns, :checked, MapSet.member?(assigns.selected_scopes, assigns.scope))

    ~H"""
    <.checkbox_control
      id={"scope-#{@area}-#{@action}"}
      checked={@checked}
      data-part="scope-toggle"
      phx-click="toggle_scope"
      phx-value-scope={@scope}
    />
    """
  end
end
