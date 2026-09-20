defmodule AtlasWeb.Admin.UsersLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.CheckboxControl, only: [checkbox_control: 1]

  alias Atlas.Authorization.Roles
  alias Atlas.Users
  alias Atlas.Users.User
  alias Phoenix.LiveView.JS

  @avatar_colors ~w(gray red orange yellow azure blue purple pink)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Users"))
     |> assign(:all_roles, Roles.list_roles())
     |> assign_users()}
  end

  def handle_event("save_user_roles", %{"user_id" => user_id} = params, socket) do
    role_ids = params |> Map.get("role_ids", %{}) |> Map.values() |> Enum.reject(&(&1 in [nil, ""]))

    case Users.get_user(user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("User not found."))}

      user ->
        case Roles.set_user_roles(user, role_ids) do
          {:ok, _} -> handle_roles_update(socket, user)
          {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not update roles."))}
        end
    end
  end

  def handle_event("close-manage-roles-modal-" <> user_id, _, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "manage-roles-modal-#{user_id}"})}
  end

  def handle_event("close-delete-user-modal-" <> user_id, _, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "delete-user-modal-#{user_id}"})}
  end

  def handle_event("delete_user", %{"user_id" => user_id, "delete_user" => %{"email" => confirmation}}, socket) do
    case Users.get_user(user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("User not found."))}

      %User{} = user ->
        cond do
          user.id == socket.assigns.current_user.id ->
            {:noreply, put_flash(socket, :error, gettext("You cannot delete your own account."))}

          String.trim(confirmation) != user.email ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Type the user's email exactly to confirm the deletion.")
             )}

          true ->
            case Users.delete_user(user) do
              {:ok, _} ->
                {:noreply,
                 socket
                 |> put_flash(:info, gettext("User deleted."))
                 |> push_event("close-modal", %{id: "delete-user-modal-#{user.id}"})
                 |> assign_users()}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, gettext("Could not delete user."))}
            end
        end
    end
  end

  def render(assigns) do
    ~H"""
    <section id="admin-users" data-part="admin-users">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Users")}</h1>
          <p data-part="description">
            {gettext(
              "Assign roles to users. Roles bundle scopes and are managed on the Roles page."
            )}
          </p>
        </div>
      </div>

      <.card title={gettext("Directory")} icon="users" data-part="users-card">
        <.card_section data-part="users-table-section">
          <.table_empty_state
            :if={@users_empty?}
            icon="users"
            title={gettext("No users yet")}
            subtitle={gettext("Users who sign in to Atlas will appear here.")}
          />

          <.table
            :if={!@users_empty?}
            id="admin-users-table"
            rows={@users_with_roles}
            row_key={fn {user, _roles} -> user.id end}
          >
            <:col :let={{user, _roles}} label={gettext("User")}>
              <.text_and_description_cell label={user_display_name(user)} description={user.email}>
                <:image>
                  <.avatar
                    id={"admin-user-avatar-#{user.id}"}
                    name={user_display_name(user)}
                    color={avatar_color(user)}
                    image_href={User.avatar_url(user)}
                  />
                </:image>
              </.text_and_description_cell>
            </:col>
            <:col :let={{_user, roles}} label={gettext("Roles")}>
              <.text_cell label={roles_label(roles)} />
            </:col>
            <:col :let={{user, roles}} label={gettext("Scopes")}>
              <.badge_cell
                id={"user-scope-count-#{user.id}"}
                label={"#{scope_count(roles)}"}
                color={if scope_count(roles) == 0, do: "neutral", else: "success"}
                style="light-fill"
              />
            </:col>
            <:col :let={{user, roles}} label={gettext("Actions")}>
              <.manage_roles_modal user={user} roles={roles} all_roles={@all_roles} />
              <.delete_user_modal user={user} current_user={@current_user} />

              <.button_cell>
                <:button>
                  <div data-part="actions-cell">
                    <.dropdown id={"admin-user-actions-#{user.id}"} icon_only>
                      <:icon><.dots_vertical /></:icon>

                      <.dropdown_item
                        label={gettext("Manage roles")}
                        value="manage_roles"
                        phx-click={
                          JS.dispatch("phx:open-modal",
                            detail: %{id: "manage-roles-modal-#{user.id}"}
                          )
                        }
                      >
                        <:left_icon><.user /></:left_icon>
                      </.dropdown_item>

                      <.dropdown_item
                        :if={user.id != @current_user.id}
                        label={gettext("Delete user")}
                        value="delete_user"
                        phx-click={
                          JS.dispatch("phx:open-modal",
                            detail: %{id: "delete-user-modal-#{user.id}"}
                          )
                        }
                      >
                        <:left_icon><.trash /></:left_icon>
                      </.dropdown_item>
                    </.dropdown>
                  </div>
                </:button>
              </.button_cell>
            </:col>
          </.table>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :user, :any, required: true
  attr :roles, :list, required: true
  attr :all_roles, :list, required: true

  defp manage_roles_modal(assigns) do
    ~H"""
    <.modal
      id={"manage-roles-modal-#{@user.id}"}
      title={gettext("Manage roles")}
      description={gettext("Pick the roles this user should hold.")}
      on_dismiss={"close-manage-roles-modal-#{@user.id}"}
      header_type="icon"
      header_size="large"
      data-part="manage-roles-modal"
    >
      <:header_icon><.user /></:header_icon>
      <:trigger :let={_attrs}>
        <button
          id={"manage-roles-trigger-#{@user.id}"}
          type="button"
          data-part="hidden-trigger"
        >
        </button>
      </:trigger>

      <div data-part="manage-roles-content">
        <.line_divider />

        <.form
          id={"manage-roles-form-#{@user.id}"}
          for={%{}}
          as={:user}
          phx-submit="save_user_roles"
        >
          <input type="hidden" name="user_id" value={@user.id} />

          <div data-part="role-option-list">
            <label
              :for={role <- @all_roles}
              id={"role-option-label-#{@user.id}-#{role.id}"}
              data-part="role-option"
              for={"role-option-#{@user.id}-#{role.id}"}
            >
              <input
                id={"role-option-#{@user.id}-#{role.id}"}
                type="checkbox"
                data-part="role-input"
                name={"role_ids[#{role.slug}]"}
                value={role.id}
                checked={Enum.any?(@roles, &(&1.id == role.id))}
              />
              <.checkbox_control
                checked={Enum.any?(@roles, &(&1.id == role.id))}
                data-part="role-checkbox"
              />
              <span data-part="body">
                <span data-part="label">{role.name}</span>
                <span data-part="description">
                  {role.description ||
                    ngettext("%{count} scope", "%{count} scopes", length(role.scopes),
                      count: length(role.scopes)
                    )}
                </span>
              </span>
            </label>
          </div>
        </.form>

        <.line_divider />
      </div>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              type="button"
              phx-click={"close-manage-roles-modal-#{@user.id}"}
            />
          </:action>
          <:action>
            <.button
              id={"save-user-roles-#{@user.id}"}
              label={gettext("Save")}
              form={"manage-roles-form-#{@user.id}"}
              type="submit"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :user, :any, required: true
  attr :current_user, :any, required: true

  defp delete_user_modal(assigns) do
    ~H"""
    <.form
      :if={@user.id != @current_user.id}
      data-part="delete-user-form"
      for={to_form(%{"email" => ""}, as: :delete_user)}
      id={"delete-user-form-#{@user.id}"}
      phx-submit="delete_user"
    >
      <input type="hidden" name="user_id" value={@user.id} />
      <.modal
        id={"delete-user-modal-#{@user.id}"}
        title={gettext("Are you sure you want to delete this?")}
        header_size="large"
        on_dismiss={"close-delete-user-modal-#{@user.id}"}
        data-part="delete-user-modal"
      >
        <:trigger :let={_attrs}>
          <button
            id={"delete-user-trigger-#{@user.id}"}
            type="button"
            data-part="hidden-trigger"
          >
          </button>
        </:trigger>
        <.line_divider />
        <.alert
          status="warning"
          type="secondary"
          size="small"
          title={
            gettext(
              "Deleting the user will permanently remove their account and all role assignments."
            )
          }
        />
        <.text_input
          label={gettext("Enter this user's email to confirm")}
          name="delete_user[email]"
          type="basic"
          placeholder={@user.email}
        />
        <.line_divider />
        <:footer>
          <.modal_footer>
            <:action>
              <.button
                type="reset"
                label={gettext("Cancel")}
                variant="secondary"
                phx-click={"close-delete-user-modal-#{@user.id}"}
              />
            </:action>
            <:action>
              <.button type="submit" label={gettext("Delete")} variant="destructive" />
            </:action>
          </.modal_footer>
        </:footer>
      </.modal>
    </.form>
    """
  end

  defp assign_users(socket) do
    users = Users.list_users()

    users_with_roles = Enum.map(users, fn user -> {user, Roles.list_roles_for_user(user)} end)

    socket
    |> assign(:users_empty?, users == [])
    |> assign(:users_with_roles, users_with_roles)
  end

  defp handle_roles_update(socket, user) do
    modal_id = "manage-roles-modal-#{user.id}"

    socket =
      socket
      |> assign_users()
      |> put_flash(:info, gettext("User roles updated."))
      |> push_event("close-modal", %{id: modal_id})

    if user.id == socket.assigns.current_user.id and not Users.has_scope?(user, "admin:read") do
      {:noreply, push_navigate(socket, to: ~p"/commercial/sales")}
    else
      {:noreply, socket}
    end
  end

  defp roles_label([]), do: "-"
  defp roles_label(roles), do: roles |> Enum.map(& &1.name) |> Enum.join(", ")

  defp scope_count(roles),
    do: roles |> Enum.flat_map(& &1.scopes) |> Enum.uniq() |> length()

  defp avatar_color(user) do
    Enum.at(@avatar_colors, :erlang.phash2(user.name || user.email, length(@avatar_colors)))
  end

  defp user_display_name(%User{name: name}) when is_binary(name) and name != "", do: name
  defp user_display_name(%User{email: email}), do: email
end
