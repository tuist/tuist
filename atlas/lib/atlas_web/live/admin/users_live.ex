defmodule AtlasWeb.Admin.UsersLive do
  use AtlasWeb, :live_view
  use Noora

  alias Atlas.Users
  alias Atlas.Users.User
  alias Phoenix.LiveView.JS

  @avatar_colors ~w(gray red orange yellow azure blue purple pink)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Users"))
     |> assign_users()}
  end

  def handle_event("save_user_role", %{"user_id" => user_id, "user" => user_params}, socket) do
    case Users.get_user(user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("User not found."))}

      user ->
        case Users.update_user_role(user, user_params) do
          {:ok, updated_user} ->
            handle_role_update(socket, updated_user)

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not update user role."))}
        end
    end
  end

  def handle_event("close-manage-role-modal-" <> user_id, _, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "manage-role-modal-#{user_id}"})}
  end

  def render(assigns) do
    ~H"""
    <div id="admin-users">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Users")}</h1>
          <p data-part="description">
            {gettext("Manage who can sign in to Atlas and which users can administer the workspace.")}
          </p>
        </div>
        <div data-part="summary">
          <Noora.Badge.badge
            id="admin-users-executive-count"
            label={role_count_label(:executive, @user_counts.executive)}
            color="success"
            style="light-fill"
          />
          <Noora.Badge.badge
            id="admin-users-employee-count"
            label={role_count_label(:employee, @user_counts.employee)}
            color="neutral"
            style="light-fill"
          />
        </div>
      </div>

      <Noora.Card.card title={gettext("Directory")} icon="users" data-part="users-card">
        <Noora.Card.card_section data-part="users-table-section">
          <Noora.Table.table_empty_state
            :if={@users_empty?}
            icon="users"
            title={gettext("No users yet")}
            subtitle={gettext("Users who sign in to Atlas will appear here.")}
          />

          <Noora.Table.table
            :if={!@users_empty?}
            id="admin-users-table"
            rows={@streams.users}
            row_key={fn {id, _user} -> id end}
          >
            <:col :let={{_id, user}} label={gettext("User")}>
              <Noora.Table.text_and_description_cell label={user_display_name(user)}>
                <:image>
                  <Noora.Avatar.avatar
                    id={"admin-user-avatar-#{user.id}"}
                    name={user_display_name(user)}
                    color={avatar_color(user)}
                    image_href={User.avatar_url(user)}
                  />
                </:image>
              </Noora.Table.text_and_description_cell>
            </:col>
            <:col :let={{_id, user}} label={gettext("Email")}>
              <Noora.Table.text_cell label={user.email} />
            </:col>
            <:col :let={{_id, user}} label={gettext("Role")}>
              <Noora.Table.badge_cell
                id={"user-role-#{user.id}"}
                label={User.role_label(user.role)}
                color={role_badge_color(user.role)}
                style="light-fill"
              />
            </:col>
            <:col :let={{_id, user}}>
              <Noora.Modal.modal
                id={"manage-role-modal-#{user.id}"}
                title={gettext("Manage role")}
                on_dismiss={"close-manage-role-modal-#{user.id}"}
                header_type="icon"
                header_size="small"
                data-part="manage-role-modal"
              >
                <:header_icon><.user /></:header_icon>
                <:trigger :let={modal_attrs}>
                  <button
                    id={"manage-role-trigger-#{user.id}"}
                    type="button"
                    {modal_attrs}
                  >
                  </button>
                </:trigger>

                <Noora.LineDivider.line_divider />

                <.form
                  id={"manage-role-form-#{user.id}"}
                  for={%{}}
                  as={:user}
                  phx-submit="save_user_role"
                >
                  <input type="hidden" name="user_id" value={user.id} />

                  <div data-part="role-management">
                    <label data-part="role-label">{gettext("Role")}</label>
                    <Noora.Select.select
                      id={"manage-role-select-#{user.id}"}
                      name="user[role]"
                      label={gettext("Select role")}
                      value={role_value(user.role)}
                    >
                      <:item value="executive" label={gettext("Executive")} />
                      <:item value="employee" label={gettext("Employee")} />
                    </Noora.Select.select>
                  </div>
                </.form>

                <Noora.LineDivider.line_divider />

                <:footer>
                  <Noora.Modal.modal_footer>
                    <:action>
                      <Noora.Button.button
                        label={gettext("Cancel")}
                        variant="secondary"
                        type="button"
                        phx-click={"close-manage-role-modal-#{user.id}"}
                      />
                    </:action>
                    <:action>
                      <Noora.Button.button
                        id={"save-user-role-#{user.id}"}
                        label={gettext("Save")}
                        form={"manage-role-form-#{user.id}"}
                        type="submit"
                      />
                    </:action>
                  </Noora.Modal.modal_footer>
                </:footer>
              </Noora.Modal.modal>

              <Noora.Table.button_cell>
                <:button>
                  <div data-part="actions-cell">
                    <Noora.Dropdown.dropdown id={"admin-user-actions-#{user.id}"} icon_only>
                      <:icon><.dots_vertical /></:icon>

                      <Noora.Dropdown.dropdown_item
                        label={gettext("Manage role")}
                        value="manage_role"
                        phx-click={
                          JS.dispatch("phx:open-modal",
                            detail: %{id: "manage-role-modal-#{user.id}"}
                          )
                        }
                      >
                        <:left_icon><.user /></:left_icon>
                      </Noora.Dropdown.dropdown_item>
                    </Noora.Dropdown.dropdown>
                  </div>
                </:button>
              </Noora.Table.button_cell>
            </:col>
          </Noora.Table.table>
        </Noora.Card.card_section>
      </Noora.Card.card>
    </div>
    """
  end

  defp assign_users(socket) do
    users = Users.list_users()

    socket
    |> assign(:user_counts, role_counts(users))
    |> assign(:users_empty?, users == [])
    |> stream(:users, users, reset: true)
  end

  defp handle_role_update(socket, updated_user) do
    current_user = socket.assigns.current_user
    modal_id = "manage-role-modal-#{updated_user.id}"

    cond do
      updated_user.id == current_user.id and not Users.executive?(updated_user) ->
        {:noreply,
         socket
         |> assign(:current_user, updated_user)
         |> put_flash(:info, gettext("Your role was updated. Admin access has been removed."))
         |> push_navigate(to: ~p"/commercial/sales")}

      updated_user.id == current_user.id ->
        {:noreply,
         socket
         |> assign(:current_user, updated_user)
         |> assign_users()
         |> put_flash(:info, gettext("User role updated."))
         |> push_event("close-modal", %{id: modal_id})}

      true ->
        {:noreply,
         socket
         |> assign_users()
         |> put_flash(:info, gettext("User role updated."))
         |> push_event("close-modal", %{id: modal_id})}
    end
  end

  defp avatar_color(user) do
    Enum.at(@avatar_colors, :erlang.phash2(user.name || user.email, length(@avatar_colors)))
  end

  defp user_display_name(%User{name: name}) when is_binary(name) and name != "", do: name
  defp user_display_name(%User{email: email}), do: email

  defp role_value(role) when is_atom(role), do: Atom.to_string(role)
  defp role_value(role), do: role

  defp role_counts(users) do
    frequencies = Enum.frequencies_by(users, & &1.role)

    %{
      executive: Map.get(frequencies, :executive, 0),
      employee: Map.get(frequencies, :employee, 0)
    }
  end

  defp role_count_label(:executive, count) do
    ngettext("%{count} executive", "%{count} executives", count, count: count)
  end

  defp role_count_label(:employee, count) do
    ngettext("%{count} employee", "%{count} employees", count, count: count)
  end

  defp role_badge_color(:executive), do: "success"
  defp role_badge_color("executive"), do: "success"
  defp role_badge_color(_role), do: "neutral"
end
