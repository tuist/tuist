defmodule TuistWeb.MembersLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Phoenix.LiveView.JS
  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Authorization

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account}} = socket) do
    socket =
      socket
      |> assign(
        :head_title,
        "#{dgettext("dashboard_account", "Members")} · #{account.name} · Tuist"
      )
      |> assign(
        form: to_form(%{}, as: :invitation),
        selected_tab: "members",
        selected_inner_tab: "members",
        managing_member: nil
        # invite_role: :user,
        # invite_emails: []
      )
      |> assign_organization()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="members">
      <h2 data-part="title">{dgettext("dashboard_account", "Members")}</h2>
      <div data-part="row">
        <.form :if={@selected_inner_tab == "members"} for={%{}} phx-change="search">
          <.text_input
            id="search-members"
            name="search"
            type="search"
            placeholder={dgettext("dashboard_account", "Search members...")}
            show_suffix={false}
          />
        </.form>
        <div :if={@selected_inner_tab == "invitations"} />

        <.invite_member_form
          :if={Authorization.authorize(:invitation_create, @current_user, @selected_account) == :ok}
          id="invite-member-form"
          form={@form}
        />
      </div>
      <div id="members-tabs">
        <div data-part="root">
          <.tab_menu_horizontal data-part="list">
            <.tab_menu_horizontal_item
              label={dgettext("dashboard_account", "All members")}
              phx-click="select-inner-tab"
              phx-value-tab="members"
              data-selected={@selected_inner_tab == "members"}
            />
            <.tab_menu_horizontal_item
              :if={Authorization.authorize(:invitation_read, @current_user, @selected_account) == :ok}
              label={dgettext("dashboard_account", "Invitations")}
              phx-click="select-inner-tab"
              phx-value-tab="invitations"
              data-selected={@selected_inner_tab == "invitations"}
            />
          </.tab_menu_horizontal>
          <div :if={@selected_inner_tab == "members"} data-part="content">
            <.table
              id="members-table"
              rows={@members}
              row_key={fn [member, _role] -> "member-#{member.id}" end}
            >
              <:col :let={[member, _role]} label={dgettext("dashboard_account", "Member")}>
                <.text_and_description_cell label={member.account.name}>
                  <:image>
                    <.avatar
                      id={"member-#{member.id}-avatar"}
                      name={member.account.name}
                      image_href={User.gravatar_url(member)}
                      color={Accounts.avatar_color(member.account)}
                    />
                  </:image>
                </.text_and_description_cell>
              </:col>
              <:col :let={[member, _role]} label={dgettext("dashboard_account", "E-mail")}>
                <.text_cell label={member.email} />
              </:col>
              <:col :let={[_member, role]} label={dgettext("dashboard_account", "Role")}>
                <.text_cell label={Macro.camelize(role)} />
              </:col>
              <:col :let={[member, role]}>
                <.modal
                  id={"manage-role-modal-#{member.id}"}
                  title={dgettext("dashboard_account", "Manage role")}
                  on_dismiss={"close-manage-role-modal-#{member.id}"}
                  header_type="icon"
                  header_size="small"
                  data-part="manage-role-modal"
                >
                  <:header_icon>
                    <.user />
                  </:header_icon>
                  <:trigger :let={modal_attrs}>
                    <button
                      id={"manage-role-trigger-#{member.id}"}
                      type="button"
                      {modal_attrs}
                    >
                    </button>
                  </:trigger>
                  <.line_divider />
                  <div data-part="change-role">
                    <label>{dgettext("dashboard_account", "Role")}</label>
                    <.dropdown
                      id={"role-dropdown-#{member.id}"}
                      label={
                        case get_selected_role(@managing_member, member.id, role) do
                          "user" -> dgettext("dashboard_account", "User")
                          "admin" -> dgettext("dashboard_account", "Admin")
                        end
                      }
                    >
                      <.dropdown_item
                        value="user"
                        label={dgettext("dashboard_account", "User")}
                        phx-click="select-member-role"
                        phx-value-member_id={member.id}
                        phx-value-role="user"
                        data-selected={get_selected_role(@managing_member, member.id, role) == "user"}
                      >
                        <:right_icon><.check /></:right_icon>
                      </.dropdown_item>
                      <.dropdown_item
                        value="admin"
                        label={dgettext("dashboard_account", "Admin")}
                        phx-click="select-member-role"
                        phx-value-member_id={member.id}
                        phx-value-role="admin"
                        data-selected={
                          get_selected_role(@managing_member, member.id, role) == "admin"
                        }
                      >
                        <:right_icon><.check /></:right_icon>
                      </.dropdown_item>
                    </.dropdown>
                  </div>
                  <.line_divider />
                  <:footer>
                    <.modal_footer>
                      <:action>
                        <.button
                          label={dgettext("dashboard_account", "Cancel")}
                          variant="secondary"
                          type="button"
                          phx-click={"close-manage-role-modal-#{member.id}"}
                        />
                      </:action>
                      <:action>
                        <.button
                          label={dgettext("dashboard_account", "Save")}
                          type="button"
                          phx-click="save-member-role"
                          phx-value-member-id={member.id}
                          disabled={get_selected_role(@managing_member, member.id, role) == role}
                        />
                      </:action>
                    </.modal_footer>
                  </:footer>
                </.modal>

                <.modal
                  id={"remove-member-modal-#{member.id}"}
                  title={dgettext("dashboard_account", "Remove member")}
                  header_type="icon"
                  header_size="small"
                  on_dismiss={"close-remove-member-modal-#{member.id}"}
                >
                  <:trigger :let={modal_attrs}>
                    <button
                      id={"remove-member-trigger-#{member.id}"}
                      type="button"
                      style="display: none;"
                      {modal_attrs}
                    >
                    </button>
                  </:trigger>
                  <:header_icon>
                    <.trash_x />
                  </:header_icon>
                  <p>
                    {dgettext(
                      "dashboard_account",
                      "Are you sure you want to remove %{name} from this organization?",
                      name: member.account.name
                    )}
                  </p>
                  <:footer>
                    <.modal_footer>
                      <:action>
                        <.button
                          label={dgettext("dashboard_account", "Cancel")}
                          variant="secondary"
                          type="button"
                          phx-click={"close-remove-member-modal-#{member.id}"}
                        />
                      </:action>
                      <:action>
                        <.button
                          label={dgettext("dashboard_account", "Remove")}
                          variant="destructive"
                          type="button"
                          phx-click="confirm-remove-member"
                          phx-value-member-id={member.id}
                        />
                      </:action>
                    </.modal_footer>
                  </:footer>
                </.modal>

                <.dropdown
                  :if={
                    Authorization.authorize(:member_update, @current_user, @selected_account) == :ok
                  }
                  id={"member-actions-#{member.id}"}
                  icon_only
                >
                  <:icon><.dots_vertical /></:icon>

                  <.dropdown_item
                    :if={member.id != @current_user.id}
                    label={dgettext("dashboard_account", "Manage role")}
                    value="manage_role"
                    phx-click={
                      JS.dispatch("phx:open-modal", detail: %{id: "manage-role-modal-#{member.id}"})
                    }
                  >
                    <:left_icon><.user /></:left_icon>
                  </.dropdown_item>

                  <.dropdown_item
                    label={dgettext("dashboard_account", "Remove member")}
                    value="remove"
                    phx-click={
                      JS.dispatch("phx:open-modal", detail: %{id: "remove-member-modal-#{member.id}"})
                    }
                  >
                    <:left_icon><.trash_x /></:left_icon>
                  </.dropdown_item>
                </.dropdown>
              </:col>

              <:empty_state>
                <.table_empty_state
                  icon="user_x"
                  title={dgettext("dashboard_account", "No members found")}
                  subtitle={dgettext("dashboard_account", "Try changing your search term")}
                />
              </:empty_state>
            </.table>
          </div>
          <div
            :if={
              @selected_inner_tab == "invitations" and
                Authorization.authorize(:invitation_read, @current_user, @selected_account) == :ok
            }
            data-part="content"
          >
            <.table id="invitations-table" rows={@invitations}>
              <:col :let={invitation} label={dgettext("dashboard_account", "Email")}>
                <.text_cell label={invitation.invitee_email} />
              </:col>
              <:col label={dgettext("dashboard_account", "Status")}>
                <.status_badge_cell
                  label={dgettext("dashboard_account", "Pending")}
                  status="attention"
                />
              </:col>
              <:col :let={invitation}>
                <.dropdown id={"invite-actions-#{invitation.id}"} icon_only>
                  <:icon><.dots_vertical /></:icon>
                  <.dropdown_item
                    label={dgettext("dashboard_account", "Revoke invite")}
                    value="revoke"
                    on_click="revoke_invite"
                    phx-value-id={invitation.id}
                  >
                    <:left_icon><.trash_x /></:left_icon>
                  </.dropdown_item>
                </.dropdown>
              </:col>
              <:empty_state>
                <.table_empty_state>
                  <.background_grid_light />
                  <.cards_light />
                  <.background_grid_dark />
                  <.cards_dark />
                  <div data-part="title">
                    {dgettext("dashboard_account", "No invitations created")}
                  </div>
                  <div data-part="subtitle">
                    {dgettext("dashboard_account", "Invite members to your organization")}
                  </div>
                  <.invite_member_form id="invite-member-form-empty-state" form={@form} />
                </.table_empty_state>
              </:empty_state>
            </.table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp invite_member_form(assigns) do
    ~H"""
    <.form id={@id} for={@form} phx-submit="invite-members">
      <.modal
        id={"#{@id}-modal"}
        title={dgettext("dashboard_account", "Invite member")}
        on_dismiss="close-invite-members"
      >
        <:trigger :let={attrs}>
          <.button variant="primary" label={dgettext("dashboard_account", "Invite members")} {attrs} />
        </:trigger>
        <.line_divider />
        <.text_input
          id={"#{@id}-input"}
          field={@form[:invitee_email]}
          type="email"
          label={dgettext("dashboard_account", "Email address")}
          show_prefix={false}
        />
        <.line_divider />
        <:footer>
          <.modal_footer>
            <:action>
              <.button
                label="Cancel"
                variant="secondary"
                type="button"
                phx-click="close-invite-members"
              />
            </:action>
            <:action>
              <.button label="Save" type="submit" tabindex="1" />
            </:action>
          </.modal_footer>
        </:footer>
      </.modal>
    </.form>

    <%!-- <div id="invite-members-input" phx-hook="NooraTagsInput"> --%>
    <%!--   <div data-part="root"> --%>
    <%!--     <span data-part="placeholder">{dgettext("dashboard_account", "Email, comma separated")}</span> --%>
    <%!--     <.input_tag --%>
    <%!--       :for={{email, index} <- Enum.with_index(@invite_emails)} --%>
    <%!--       label={email} --%>
    <%!--       data-value={email} --%>
    <%!--       data-index={index} --%>
    <%!--       dismissible --%>
    <%!--       on_dismiss="remove-invite-email" --%>
    <%!--       dismiss_value={email} --%>
    <%!--       data-invalid={!String.contains?(email, "@")} --%>
    <%!--     /> --%>
    <%!--     <input --%>
    <%!--       id="invite-members-text" --%>
    <%!--       name="invite-members-text" --%>
    <%!--       data-part="input" --%>
    <%!--       phx-keydown="add-invite-email" --%>
    <%!--     /> --%>
    <% # NOTE: This doesn't work. The dropdown items disappear once one is selected, and for some reason the modal closes as well. %>
    <%!-- <.inline_dropdown id="invite-members-role" label={Macro.camelize(Atom.to_string(@invite_role))}> --%>
    <%!--   <.dropdown_item label={dgettext("dashboard_account", "User")} on_click="select-invite-role" value="user" /> --%>
    <%!--   <.dropdown_item label={dgettext("dashboard_account", "Admin")} on_click="select-invite-role" value="admin" /> --%>
    <%!-- </.inline_dropdown> --%>
    <%!-- </div> --%>
    <%!-- </div> --%>
    """
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    members =
      Enum.filter(socket.assigns.all_members, fn [member, _role] ->
        String.contains?(member.email, search) || String.contains?(member.account.name, search)
      end)

    socket = assign(socket, members: members)
    {:noreply, socket}
  end

  def handle_event("select-inner-tab", %{"tab" => tab}, socket) do
    socket = assign(socket, selected_inner_tab: tab)
    {:noreply, socket}
  end

  def handle_event("revoke_invite", %{"id" => id}, socket) do
    id
    |> Accounts.get_invitation_by_id()
    |> then(&Accounts.delete_invitation(%{invitation: &1}))

    socket = assign_organization(socket)

    {:noreply, socket}
  end

  # def handle_event("add-invite-email", %{"key" => key, "value" => email}, socket)
  #     when key in ["Enter", ","] do
  #   socket = assign(socket, invite_emails: socket.assigns.invite_emails ++ [email])
  #   {:noreply, socket}
  # end

  # def handle_event("add-invite-email", params, socket), do: {:noreply, socket}
  #
  # def handle_event("remove-invite-email", %{"data" => email} = params, socket) do
  #   socket = assign(socket, invite_emails: List.delete(socket.assigns.invite_emails, email))
  #   {:noreply, socket}
  # end

  def handle_event("close-invite-members", _, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "invite-member-form-modal"})
      |> push_event("close-modal", %{id: "invite-member-form-empty-state-modal"})

    {:noreply, socket}
  end

  def handle_event("select-member-role", %{"member_id" => member_id, "role" => role}, socket) do
    member_id_int = String.to_integer(member_id)
    socket = assign(socket, managing_member: {member_id_int, role})
    {:noreply, socket}
  end

  def handle_event("save-member-role", %{"member-id" => member_id}, %{assigns: %{organization: organization}} = socket) do
    member_id_int = String.to_integer(member_id)
    {^member_id_int, new_role} = socket.assigns.managing_member

    [member, _role] = Enum.find(socket.assigns.members, fn [m, _role] -> m.id == member_id_int end)

    {:ok, _} = Accounts.update_user_role_in_organization(member, organization, String.to_existing_atom(new_role))

    socket =
      socket
      |> assign_organization()
      |> assign(managing_member: nil)
      |> push_event("close-modal", %{id: "manage-role-modal-#{member_id}"})

    {:noreply, socket}
  end

  def handle_event("close-manage-role-modal-" <> member_id, _, socket) do
    socket =
      socket
      |> assign(managing_member: nil)
      |> push_event("close-modal", %{id: "manage-role-modal-#{member_id}"})

    {:noreply, socket}
  end

  def handle_event("close-remove-member-modal-" <> member_id, _, socket) do
    socket = push_event(socket, "close-modal", %{id: "remove-member-modal-#{member_id}"})
    {:noreply, socket}
  end

  # def handle_event("select-invite-role", %{"data" => role}, socket) do
  #   socket = assign(socket, invite_role: String.to_existing_atom(role))
  #   {:noreply, socket}
  # end

  def handle_event("invite-members", %{"invitation" => %{"invitee_email" => email}}, socket) do
    email = String.trim(email)

    # NOTE: Enable this when tag-input is used.
    # Accounts.invite_users_to_organization(socket.assigns.invite_emails, %{
    #   inviter: socket.assigns.current_user,
    #   to: socket.assigns.organization,
    #   url: &url(~p"/auth/invitations/#{&1}")
    # })

    with {:ok, _invitation} <-
           Accounts.invite_user_to_organization(
             email,
             %{
               inviter: socket.assigns.current_user,
               to: socket.assigns.organization,
               url: &url(~p"/auth/invitations/#{&1}")
             }
           ),
         {:ok, organization} <-
           Accounts.get_organization_by_id(socket.assigns.organization.id,
             preload: [:invitations]
           ) do
      socket =
        socket
        |> assign(
          invitations: organization.invitations,
          invite_emails: [],
          form: to_form(%{}, as: :invitation),
          selected_inner_tab: "invitations"
        )
        |> push_event("close-modal", %{id: "invite-member-form-modal"})
        |> push_event("close-modal", %{id: "invite-member-form-empty-state-modal"})

      {:noreply, socket}
    else
      {:error, changeset} ->
        socket = assign(socket, form: to_form(changeset))

        {:noreply, socket}
    end
  end

  def handle_event("confirm-remove-member", %{"member-id" => member_id}, socket) do
    :ok = Authorization.authorize(:member_update, socket.assigns.current_user, socket.assigns.selected_account)

    [member, _role] = Enum.find(socket.assigns.members, fn [m, _role] -> m.id == String.to_integer(member_id) end)
    organization = socket.assigns.organization

    :ok = Accounts.remove_user_from_organization(member, organization)

    socket =
      socket
      |> assign_organization()
      |> push_event("close-modal", %{id: "remove-member-modal-#{member_id}"})

    {:noreply, socket}
  end

  defp assign_organization(socket) do
    {:ok, organization} =
      Accounts.get_organization_by_id(socket.assigns.selected_account.organization_id,
        preload: [:invitations]
      )

    members = Accounts.get_organization_members_with_role(organization)

    assign(socket,
      organization: organization,
      members: members,
      all_members: members,
      invitations: organization.invitations
    )
  end

  defp get_selected_role(managing_member, member_id, current_role) do
    case managing_member do
      {id, selected_role} when id == member_id -> selected_role
      _ -> current_role
    end
  end

  defp background_grid_light(assigns) do
    ~H"""
    <div data-part="background" data-style="light">
      <svg
        width="1216"
        height="294"
        viewBox="0 0 1216 294"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <mask
          id="mask0_2122_77256"
          style="mask-type:alpha"
          maskUnits="userSpaceOnUse"
          x="0"
          y="0"
          width="1216"
          height="294"
        >
          <rect width="1216" height="294" fill="url(#paint0_radial_2122_77256)" fill-opacity="0.25" />
        </mask>
        <g mask="url(#mask0_2122_77256)">
          <path
            d="M554.231 0H604.615M554.231 0V50.3846M554.231 0H503.846M604.615 0V50.3846M604.615 0H655V50.3846M604.615 50.3846H554.231M604.615 50.3846H655M604.615 50.3846V100.769M554.231 50.3846V100.769M554.231 50.3846H503.846M655 50.3846V100.769M604.615 100.769H554.231M604.615 100.769V151.154M604.615 100.769H655M554.231 100.769V151.154M554.231 100.769H503.846M604.615 151.154H554.231M604.615 151.154V201.538M604.615 151.154H655M554.231 151.154V201.538M554.231 151.154H503.846M604.615 201.538H554.231M604.615 201.538V251.923M604.615 201.538H655M554.231 201.538V251.923M554.231 201.538H503.846M604.615 251.923H554.231M604.615 251.923V302.308M604.615 251.923H655M554.231 251.923V302.308M554.231 251.923H503.846M604.615 302.308H554.231M604.615 302.308V352.692M604.615 302.308H655M554.231 302.308V352.692M554.231 302.308H503.846M604.615 352.692H554.231M604.615 352.692V403.077M604.615 352.692H655M554.231 352.692V403.077M554.231 352.692H503.846M604.615 403.077H554.231M604.615 403.077V453.462M604.615 403.077H655M554.231 403.077V453.462M554.231 403.077H503.846M604.615 453.462H554.231M604.615 453.462H655V403.077M554.231 453.462H503.846M655 100.769V151.154M655 151.154V201.538M655 201.538V251.923M655 251.923V302.308M655 302.308V352.692M655 352.692V403.077M50.3846 0H0V50.3846M50.3846 0V50.3846M50.3846 0H100.769M50.3846 50.3846H0M50.3846 50.3846H100.769M50.3846 50.3846V100.769M0 50.3846V100.769M100.769 0V50.3846M100.769 0H151.154M100.769 50.3846H151.154M100.769 50.3846V100.769M151.154 0V50.3846M151.154 0H201.538M151.154 50.3846H201.538M151.154 50.3846V100.769M201.538 0V50.3846M201.538 0H251.923M201.538 50.3846H251.923M201.538 50.3846V100.769M251.923 0V50.3846M251.923 0H302.308M251.923 50.3846H302.308M251.923 50.3846V100.769M302.308 0V50.3846M302.308 0H352.692M302.308 50.3846H352.692M302.308 50.3846V100.769M352.692 0V50.3846M352.692 0H403.077M352.692 50.3846H403.077M352.692 50.3846V100.769M403.077 0V50.3846M403.077 0H453.462M403.077 50.3846H453.462M403.077 50.3846V100.769M453.462 0V50.3846M453.462 0H503.846M453.462 50.3846H503.846M453.462 50.3846V100.769M503.846 0V50.3846M503.846 50.3846V100.769M50.3846 100.769H0M50.3846 100.769V151.154M50.3846 100.769H100.769M0 100.769V151.154M50.3846 151.154H0M50.3846 151.154V201.538M50.3846 151.154H100.769M0 151.154V201.538M50.3846 201.538H0M50.3846 201.538V251.923M50.3846 201.538H100.769M0 201.538V251.923M50.3846 251.923H0M50.3846 251.923V302.308M50.3846 251.923H100.769M0 251.923V302.308M50.3846 302.308H0M50.3846 302.308V352.692M50.3846 302.308H100.769M0 302.308V352.692M50.3846 352.692H0M50.3846 352.692V403.077M50.3846 352.692H100.769M0 352.692V403.077M50.3846 403.077H0M50.3846 403.077V453.462M50.3846 403.077H100.769M0 403.077V453.462H50.3846M50.3846 453.462H100.769M100.769 100.769V151.154M100.769 100.769H151.154M100.769 151.154V201.538M100.769 151.154H151.154M100.769 201.538V251.923M100.769 201.538H151.154M100.769 251.923V302.308M100.769 251.923H151.154M100.769 302.308V352.692M100.769 302.308H151.154M100.769 352.692V403.077M100.769 352.692H151.154M100.769 403.077V453.462M100.769 403.077H151.154M100.769 453.462H151.154M151.154 100.769V151.154M151.154 100.769H201.538M151.154 151.154V201.538M151.154 151.154H201.538M151.154 201.538V251.923M151.154 201.538H201.538M151.154 251.923V302.308M151.154 251.923H201.538M151.154 302.308V352.692M151.154 302.308H201.538M151.154 352.692V403.077M151.154 352.692H201.538M151.154 403.077V453.462M151.154 403.077H201.538M151.154 453.462H201.538M201.538 100.769V151.154M201.538 100.769H251.923M201.538 151.154V201.538M201.538 151.154H251.923M201.538 201.538V251.923M201.538 201.538H251.923M201.538 251.923V302.308M201.538 251.923H251.923M201.538 302.308V352.692M201.538 302.308H251.923M201.538 352.692V403.077M201.538 352.692H251.923M201.538 403.077V453.462M201.538 403.077H251.923M201.538 453.462H251.923M251.923 100.769V151.154M251.923 100.769H302.308M251.923 151.154V201.538M251.923 151.154H302.308M251.923 201.538V251.923M251.923 201.538H302.308M251.923 251.923V302.308M251.923 251.923H302.308M251.923 302.308V352.692M251.923 302.308H302.308M251.923 352.692V403.077M251.923 352.692H302.308M251.923 403.077V453.462M251.923 403.077H302.308M251.923 453.462H302.308M302.308 100.769V151.154M302.308 100.769H352.692M302.308 151.154V201.538M302.308 151.154H352.692M302.308 201.538V251.923M302.308 201.538H352.692M302.308 251.923V302.308M302.308 251.923H352.692M302.308 302.308V352.692M302.308 302.308H352.692M302.308 352.692V403.077M302.308 352.692H352.692M302.308 403.077V453.462M302.308 403.077H352.692M302.308 453.462H352.692M352.692 100.769V151.154M352.692 100.769H403.077M352.692 151.154V201.538M352.692 151.154H403.077M352.692 201.538V251.923M352.692 201.538H403.077M352.692 251.923V302.308M352.692 251.923H403.077M352.692 302.308V352.692M352.692 302.308H403.077M352.692 352.692V403.077M352.692 352.692H403.077M352.692 403.077V453.462M352.692 403.077H403.077M352.692 453.462H403.077M403.077 100.769V151.154M403.077 100.769H453.462M403.077 151.154V201.538M403.077 151.154H453.462M403.077 201.538V251.923M403.077 201.538H453.462M403.077 251.923V302.308M403.077 251.923H453.462M403.077 302.308V352.692M403.077 302.308H453.462M403.077 352.692V403.077M403.077 352.692H453.462M403.077 403.077V453.462M403.077 403.077H453.462M403.077 453.462H453.462M453.462 100.769V151.154M453.462 100.769H503.846M453.462 151.154V201.538M453.462 151.154H503.846M453.462 201.538V251.923M453.462 201.538H503.846M453.462 251.923V302.308M453.462 251.923H503.846M453.462 302.308V352.692M453.462 302.308H503.846M453.462 352.692V403.077M453.462 352.692H503.846M453.462 403.077V453.462M453.462 403.077H503.846M453.462 453.462H503.846M503.846 100.769V151.154M503.846 151.154V201.538M503.846 201.538V251.923M503.846 251.923V302.308M503.846 302.308V352.692M503.846 352.692V403.077M503.846 403.077V453.462"
            stroke="url(#paint1_linear_2122_77256)"
          />
          <path
            d="M1209.23 0H1259.62M1209.23 0V50.3846M1209.23 0H1158.85M1259.62 0V50.3846M1259.62 0H1310V50.3846M1259.62 50.3846H1209.23M1259.62 50.3846H1310M1259.62 50.3846V100.769M1209.23 50.3846V100.769M1209.23 50.3846H1158.85M1310 50.3846V100.769M1259.62 100.769H1209.23M1259.62 100.769V151.154M1259.62 100.769H1310M1209.23 100.769V151.154M1209.23 100.769H1158.85M1259.62 151.154H1209.23M1259.62 151.154V201.538M1259.62 151.154H1310M1209.23 151.154V201.538M1209.23 151.154H1158.85M1259.62 201.538H1209.23M1259.62 201.538V251.923M1259.62 201.538H1310M1209.23 201.538V251.923M1209.23 201.538H1158.85M1259.62 251.923H1209.23M1259.62 251.923V302.308M1259.62 251.923H1310M1209.23 251.923V302.308M1209.23 251.923H1158.85M1259.62 302.308H1209.23M1259.62 302.308V352.692M1259.62 302.308H1310M1209.23 302.308V352.692M1209.23 302.308H1158.85M1259.62 352.692H1209.23M1259.62 352.692V403.077M1259.62 352.692H1310M1209.23 352.692V403.077M1209.23 352.692H1158.85M1259.62 403.077H1209.23M1259.62 403.077V453.462M1259.62 403.077H1310M1209.23 403.077V453.462M1209.23 403.077H1158.85M1259.62 453.462H1209.23M1259.62 453.462H1310V403.077M1209.23 453.462H1158.85M1310 100.769V151.154M1310 151.154V201.538M1310 201.538V251.923M1310 251.923V302.308M1310 302.308V352.692M1310 352.692V403.077M705.385 0H655V50.3846M705.385 0V50.3846M705.385 0H755.769M705.385 50.3846H655M705.385 50.3846H755.769M705.385 50.3846V100.769M655 50.3846V100.769M755.769 0V50.3846M755.769 0H806.154M755.769 50.3846H806.154M755.769 50.3846V100.769M806.154 0V50.3846M806.154 0H856.538M806.154 50.3846H856.538M806.154 50.3846V100.769M856.538 0V50.3846M856.538 0H906.923M856.538 50.3846H906.923M856.538 50.3846V100.769M906.923 0V50.3846M906.923 0H957.308M906.923 50.3846H957.308M906.923 50.3846V100.769M957.308 0V50.3846M957.308 0H1007.69M957.308 50.3846H1007.69M957.308 50.3846V100.769M1007.69 0V50.3846M1007.69 0H1058.08M1007.69 50.3846H1058.08M1007.69 50.3846V100.769M1058.08 0V50.3846M1058.08 0H1108.46M1058.08 50.3846H1108.46M1058.08 50.3846V100.769M1108.46 0V50.3846M1108.46 0H1158.85M1108.46 50.3846H1158.85M1108.46 50.3846V100.769M1158.85 0V50.3846M1158.85 50.3846V100.769M705.385 100.769H655M705.385 100.769V151.154M705.385 100.769H755.769M655 100.769V151.154M705.385 151.154H655M705.385 151.154V201.538M705.385 151.154H755.769M655 151.154V201.538M705.385 201.538H655M705.385 201.538V251.923M705.385 201.538H755.769M655 201.538V251.923M705.385 251.923H655M705.385 251.923V302.308M705.385 251.923H755.769M655 251.923V302.308M705.385 302.308H655M705.385 302.308V352.692M705.385 302.308H755.769M655 302.308V352.692M705.385 352.692H655M705.385 352.692V403.077M705.385 352.692H755.769M655 352.692V403.077M705.385 403.077H655M705.385 403.077V453.462M705.385 403.077H755.769M655 403.077V453.462H705.385M705.385 453.462H755.769M755.769 100.769V151.154M755.769 100.769H806.154M755.769 151.154V201.538M755.769 151.154H806.154M755.769 201.538V251.923M755.769 201.538H806.154M755.769 251.923V302.308M755.769 251.923H806.154M755.769 302.308V352.692M755.769 302.308H806.154M755.769 352.692V403.077M755.769 352.692H806.154M755.769 403.077V453.462M755.769 403.077H806.154M755.769 453.462H806.154M806.154 100.769V151.154M806.154 100.769H856.538M806.154 151.154V201.538M806.154 151.154H856.538M806.154 201.538V251.923M806.154 201.538H856.538M806.154 251.923V302.308M806.154 251.923H856.538M806.154 302.308V352.692M806.154 302.308H856.538M806.154 352.692V403.077M806.154 352.692H856.538M806.154 403.077V453.462M806.154 403.077H856.538M806.154 453.462H856.538M856.538 100.769V151.154M856.538 100.769H906.923M856.538 151.154V201.538M856.538 151.154H906.923M856.538 201.538V251.923M856.538 201.538H906.923M856.538 251.923V302.308M856.538 251.923H906.923M856.538 302.308V352.692M856.538 302.308H906.923M856.538 352.692V403.077M856.538 352.692H906.923M856.538 403.077V453.462M856.538 403.077H906.923M856.538 453.462H906.923M906.923 100.769V151.154M906.923 100.769H957.308M906.923 151.154V201.538M906.923 151.154H957.308M906.923 201.538V251.923M906.923 201.538H957.308M906.923 251.923V302.308M906.923 251.923H957.308M906.923 302.308V352.692M906.923 302.308H957.308M906.923 352.692V403.077M906.923 352.692H957.308M906.923 403.077V453.462M906.923 403.077H957.308M906.923 453.462H957.308M957.308 100.769V151.154M957.308 100.769H1007.69M957.308 151.154V201.538M957.308 151.154H1007.69M957.308 201.538V251.923M957.308 201.538H1007.69M957.308 251.923V302.308M957.308 251.923H1007.69M957.308 302.308V352.692M957.308 302.308H1007.69M957.308 352.692V403.077M957.308 352.692H1007.69M957.308 403.077V453.462M957.308 403.077H1007.69M957.308 453.462H1007.69M1007.69 100.769V151.154M1007.69 100.769H1058.08M1007.69 151.154V201.538M1007.69 151.154H1058.08M1007.69 201.538V251.923M1007.69 201.538H1058.08M1007.69 251.923V302.308M1007.69 251.923H1058.08M1007.69 302.308V352.692M1007.69 302.308H1058.08M1007.69 352.692V403.077M1007.69 352.692H1058.08M1007.69 403.077V453.462M1007.69 403.077H1058.08M1007.69 453.462H1058.08M1058.08 100.769V151.154M1058.08 100.769H1108.46M1058.08 151.154V201.538M1058.08 151.154H1108.46M1058.08 201.538V251.923M1058.08 201.538H1108.46M1058.08 251.923V302.308M1058.08 251.923H1108.46M1058.08 302.308V352.692M1058.08 302.308H1108.46M1058.08 352.692V403.077M1058.08 352.692H1108.46M1058.08 403.077V453.462M1058.08 403.077H1108.46M1058.08 453.462H1108.46M1108.46 100.769V151.154M1108.46 100.769H1158.85M1108.46 151.154V201.538M1108.46 151.154H1158.85M1108.46 201.538V251.923M1108.46 201.538H1158.85M1108.46 251.923V302.308M1108.46 251.923H1158.85M1108.46 302.308V352.692M1108.46 302.308H1158.85M1108.46 352.692V403.077M1108.46 352.692H1158.85M1108.46 403.077V453.462M1108.46 403.077H1158.85M1108.46 453.462H1158.85M1158.85 100.769V151.154M1158.85 151.154V201.538M1158.85 201.538V251.923M1158.85 251.923V302.308M1158.85 302.308V352.692M1158.85 352.692V403.077M1158.85 403.077V453.462"
            stroke="url(#paint2_linear_2122_77256)"
          />
        </g>
        <defs>
          <radialGradient
            id="paint0_radial_2122_77256"
            cx="0"
            cy="0"
            r="1"
            gradientUnits="userSpaceOnUse"
            gradientTransform="translate(608 147) rotate(90) scale(210.044 590.516)"
          >
            <stop stop-color="#313131" />
            <stop offset="1" stop-color="#313131" stop-opacity="0" />
          </radialGradient>
          <linearGradient
            id="paint1_linear_2122_77256"
            x1="327.5"
            y1="0"
            x2="327.5"
            y2="453.462"
            gradientUnits="userSpaceOnUse"
          >
            <stop stop-color="#AEAEAE" />
            <stop offset="1" stop-color="#5D5D5D" stop-opacity="0" />
          </linearGradient>
          <linearGradient
            id="paint2_linear_2122_77256"
            x1="982.5"
            y1="0"
            x2="982.5"
            y2="453.462"
            gradientUnits="userSpaceOnUse"
          >
            <stop stop-color="#AEAEAE" />
            <stop offset="1" stop-color="#5D5D5D" stop-opacity="0" />
          </linearGradient>
        </defs>
      </svg>
    </div>
    """
  end

  defp cards_light(assigns) do
    ~H"""
    <div data-part="cards" data-style="light">
      <svg
        width="188"
        height="155"
        viewBox="0 0 188 155"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <g filter="url(#filter0_ddddi_2129_77281)">
          <path
            d="M9.50995 36.542C7.84753 31.9797 10.1993 26.9363 14.7628 25.2772L70.5377 4.99974C75.1012 3.34064 80.1483 5.69414 81.8107 10.2564L112.162 93.5524C113.825 98.1147 111.473 103.158 106.909 104.817L51.1345 125.095C46.571 126.754 41.5239 124.4 39.8615 119.838L9.50995 36.542Z"
            fill="#F9FAFA"
          />
        </g>
        <g clip-path="url(#clip0_2129_77281)">
          <path
            opacity="0.2"
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M43.7582 31.4887C44.9109 30.433 46.2605 29.6146 47.7299 29.0804C49.1993 28.5462 50.7598 28.3066 52.3222 28.3752C53.8846 28.4438 55.4184 28.8193 56.8359 29.4803C58.2534 30.1414 59.527 31.0749 60.5839 32.2277C61.6407 33.3804 62.4602 34.7298 62.9955 36.1989C63.5308 37.6679 63.7714 39.2278 63.7036 40.7894C63.6358 42.351 63.261 43.8839 62.6004 45.3004C62.4759 45.5675 62.3416 45.8295 62.198 46.0859C62.1766 46.1297 62.1524 46.1724 62.1254 46.2136C61.5186 47.2663 60.753 48.2216 59.8539 49.045C58.7012 50.1008 57.3516 50.9191 55.8822 51.4533C54.4128 51.9875 52.8523 52.2272 51.2899 52.1586C49.7275 52.0899 48.1938 51.7144 46.7762 51.0534C45.3587 50.3924 44.0851 49.4589 43.0283 48.3061C41.9714 47.1533 41.152 45.8039 40.6167 44.3349C40.0814 42.8659 39.8408 41.306 39.9085 39.7444C39.9763 38.1827 40.3512 36.6499 41.0117 35.2334C41.6722 33.8169 42.6055 32.5444 43.7582 31.4887ZM60.751 43.5492C61.0878 42.6312 61.2815 41.6651 61.3241 40.6849C61.3783 39.4356 61.1858 38.1877 60.7576 37.0125C60.3294 35.8372 59.6738 34.7577 58.8283 33.8355C57.9828 32.9133 56.964 32.1665 55.8299 31.6377C54.6959 31.1088 53.4689 30.8084 52.219 30.7535C50.9691 30.6986 49.7207 30.8903 48.5452 31.3177C47.3696 31.7451 46.29 32.3998 45.3678 33.2443C44.4456 34.0889 43.699 35.1069 43.1706 36.2401C42.6422 37.3733 42.3423 38.5995 42.288 39.8489C42.2338 41.0982 42.4263 42.3461 42.8545 43.5213C43.2828 44.6965 43.9383 45.776 44.7838 46.6982C45.4473 47.4219 46.2174 48.0375 47.0662 48.5246C47.2294 47.8996 47.4943 47.3014 47.8542 46.7551C48.5581 45.6866 49.588 44.8735 50.791 44.4364M49.3018 49.4531C49.3822 48.9603 49.5657 48.4869 49.8436 48.0651C50.266 47.4239 50.884 46.936 51.6059 46.6738L56.082 45.0465C56.8047 44.7835 57.5935 44.7605 58.3305 44.9813C58.8138 45.1261 59.258 45.3707 59.6361 45.6959C59.2338 46.2757 58.7673 46.8105 58.2444 47.2894C57.3222 48.134 56.2425 48.7887 55.067 49.216C53.8914 49.6434 52.6431 49.8351 51.3932 49.7802C50.6844 49.7491 49.983 49.639 49.3018 49.4531ZM60.751 43.5492C60.2251 43.1761 59.6388 42.8884 59.0132 42.701C57.7851 42.333 56.4712 42.371 55.2668 42.8092C55.2667 42.8093 55.2669 42.8092 55.2668 42.8092L50.791 44.4364M46.6731 36.0162C47.2067 34.8719 48.1733 33.9866 49.3604 33.555C50.5474 33.1234 51.8576 33.181 53.0028 33.715C54.1479 34.249 55.0342 35.2157 55.4666 36.4024C55.899 37.5891 55.8422 38.8987 55.3086 40.043C54.775 41.1873 53.8083 42.0726 52.6213 42.5042C51.4342 42.9357 50.124 42.8782 48.9789 42.3442C47.8338 41.8102 46.9475 40.8435 46.5151 39.6568C46.0827 38.4701 46.1395 37.1605 46.6731 36.0162ZM50.1756 35.7923C49.5821 36.0081 49.0988 36.4507 48.832 37.0229C48.5652 37.595 48.5367 38.2498 48.753 38.8432C48.9692 39.4366 49.4123 39.9199 49.9849 40.1869C50.5574 40.4539 51.2125 40.4827 51.8061 40.2669C52.3996 40.0511 52.8829 39.6084 53.1497 39.0363C53.4165 38.4641 53.4449 37.8093 53.2287 37.216C53.0125 36.6226 52.5694 36.1393 51.9968 35.8723C51.4242 35.6053 50.7691 35.5765 50.1756 35.7923Z"
            fill="#B3BAC1"
          />
        </g>
        <path
          opacity="0.2"
          d="M67.2573 70.8942C66.7032 69.3734 67.4871 67.6923 69.0083 67.1393L86.9113 60.6305C88.4325 60.0774 90.1149 60.8619 90.669 62.3827C91.2231 63.9035 90.4392 65.5846 88.918 66.1376L71.015 72.6464C69.4938 73.1995 67.8115 72.415 67.2573 70.8942Z"
          fill="#B3BAC1"
        />
        <path
          opacity="0.2"
          d="M40.2203 90.8551C39.6661 89.3344 40.4501 87.6532 41.9712 87.1002L90.1717 69.5765C91.6929 69.0235 93.3753 69.808 93.9294 71.3287C94.4835 72.8495 93.6996 74.5306 92.1784 75.0837L43.978 92.6074C42.4568 93.1604 40.7744 92.3759 40.2203 90.8551Z"
          fill="#B3BAC1"
        />
        <path
          opacity="0.2"
          d="M43.4814 99.8083C42.9273 98.2875 43.7112 96.6064 45.2324 96.0533L66.5783 88.2928C68.0995 87.7398 69.7819 88.5243 70.336 90.0451C70.8901 91.5658 70.1062 93.247 68.585 93.8L47.2391 101.561C45.718 102.114 44.0356 101.329 43.4814 99.8083Z"
          fill="#B3BAC1"
        />
        <path
          opacity="0.2"
          d="M46.7418 108.754C46.1876 107.233 46.9716 105.552 48.4927 104.999L96.6932 87.4749C98.2144 86.9219 99.8967 87.7064 100.451 89.2272C101.005 90.7479 100.221 92.4291 98.6999 92.9821L50.4994 110.506C48.9783 111.059 47.2959 110.274 46.7418 108.754Z"
          fill="#B3BAC1"
        />
        <g filter="url(#filter1_ddddi_2129_77281)">
          <path
            d="M106.199 10.2608C107.861 5.69847 112.908 3.34497 117.472 5.00407L173.247 25.2815C177.81 26.9406 180.162 31.984 178.499 36.5463L148.148 119.842C146.485 124.405 141.438 126.758 136.875 125.099L81.1 104.822C76.5365 103.162 74.1847 98.119 75.8471 93.5567L106.199 10.2608Z"
            fill="#F9FAFA"
          />
        </g>
        <g clip-path="url(#clip1_2129_77281)">
          <path
            opacity="0.2"
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M135.688 28.3784C137.25 28.3098 138.811 28.5494 140.28 29.0836C141.75 29.6178 143.099 30.4362 144.252 31.4919C145.405 32.5476 146.338 33.8201 146.998 35.2366C147.659 36.6531 148.034 38.1859 148.102 39.7476C148.169 41.3092 147.929 42.8691 147.393 44.3381C146.858 45.8071 146.039 47.1565 144.982 48.3093C143.925 49.4621 142.651 50.3956 141.234 51.0566C140.967 51.1812 140.695 51.2957 140.42 51.4C140.376 51.4198 140.33 51.4369 140.282 51.4512C139.14 51.868 137.939 52.1082 136.72 52.1618C135.158 52.2304 133.597 51.9907 132.128 51.4565C130.659 50.9223 129.309 50.104 128.156 49.0482C127.004 47.9925 126.07 46.7201 125.41 45.3036C124.749 43.8871 124.374 42.3542 124.307 40.7926C124.239 39.231 124.479 37.6711 125.015 36.2021C125.55 34.733 126.369 33.3836 127.426 32.2309C128.483 31.0781 129.757 30.1446 131.174 29.4835C132.592 28.8225 134.126 28.447 135.688 28.3784ZM140.944 48.5277C141.793 48.0406 142.563 47.425 143.226 46.7014C144.072 45.7792 144.727 44.6997 145.156 43.5245C145.584 42.3493 145.776 41.1014 145.722 39.8521C145.668 38.6027 145.368 37.3765 144.84 36.2433C144.311 35.1101 143.565 34.0921 142.642 33.2475C141.72 32.403 140.641 31.7483 139.465 31.3209C138.289 30.8935 137.041 30.7018 135.791 30.7567C134.541 30.8116 133.314 31.112 132.18 31.6409C131.046 32.1697 130.027 32.9165 129.182 33.8387C128.336 34.7609 127.681 35.8404 127.253 37.0157C126.824 38.1909 126.632 39.4388 126.686 40.6881C126.729 41.6684 126.922 42.6345 127.259 43.5526C127.786 43.1786 128.374 42.8904 129.001 42.703C130.228 42.3364 131.541 42.3748 132.743 42.8124M128.374 45.6992C128.753 45.3734 129.198 45.1286 129.682 44.9838C130.419 44.7639 131.206 44.7869 131.928 45.0496L136.404 46.6769C137.127 46.9394 137.746 47.4283 138.168 48.0706C138.445 48.4919 138.628 48.9644 138.709 49.4563C138.027 49.6422 137.326 49.7523 136.617 49.7834C135.367 49.8383 134.119 49.6466 132.943 49.2192C131.768 48.7919 130.688 48.1372 129.766 47.2926C129.243 46.8137 128.776 46.279 128.374 45.6992ZM140.944 48.5277C140.781 47.9042 140.517 47.3074 140.159 46.7621C139.455 45.6917 138.424 44.8772 137.219 44.4396C137.219 44.4396 137.219 44.4397 137.219 44.4396L132.743 42.8124M135.007 33.7182C136.153 33.1842 137.463 33.1266 138.65 33.5582C139.837 33.9898 140.803 34.8751 141.337 36.0194C141.871 37.1637 141.927 38.4733 141.495 39.66C141.063 40.8467 140.176 41.8134 139.031 42.3474C137.886 42.8814 136.576 42.9389 135.389 42.5074C134.202 42.0758 133.235 41.1905 132.702 40.0462C132.168 38.9019 132.111 37.5923 132.544 36.4056C132.976 35.2189 133.862 34.2522 135.007 33.7182ZM137.835 35.7955C137.241 35.5797 136.586 35.6085 136.013 35.8755C135.441 36.1425 134.998 36.6258 134.781 37.2192C134.565 37.8125 134.594 38.4673 134.86 39.0395C135.127 39.6116 135.611 40.0543 136.204 40.2701C136.798 40.4859 137.453 40.4571 138.025 40.1901C138.598 39.9231 139.041 39.4398 139.257 38.8464C139.473 38.253 139.445 37.5982 139.178 37.0261C138.911 36.4539 138.428 36.0113 137.835 35.7955Z"
            fill="#B3BAC1"
          />
        </g>
        <path
          opacity="0.2"
          d="M128.327 73.6598C128.881 72.1391 130.564 71.3546 132.085 71.9076L149.988 78.4164C151.509 78.9694 152.293 80.6506 151.739 82.1714C151.185 83.6921 149.502 84.4766 147.981 83.9236L130.078 77.4148C128.557 76.8617 127.773 75.1806 128.327 73.6598Z"
          fill="#B3BAC1"
        />
        <path
          opacity="0.2"
          d="M94.7684 71.5973C95.3226 70.0766 97.0049 69.2921 98.5261 69.8451L146.727 87.3688C148.248 87.9219 149.032 89.603 148.478 91.1238C147.923 92.6445 146.241 93.429 144.72 92.876L96.5194 75.3523C94.9982 74.7992 94.2143 73.1181 94.7684 71.5973Z"
          fill="#B3BAC1"
        />
        <path
          opacity="0.2"
          d="M91.5073 80.5426C92.0614 79.0219 93.7438 78.2374 95.2649 78.7904L116.611 86.5509C118.132 87.104 118.916 88.7851 118.362 90.3059C117.808 91.8266 116.125 92.6111 114.604 92.0581L93.2582 84.2976C91.7371 83.7446 90.9531 82.0634 91.5073 80.5426Z"
          fill="#B3BAC1"
        />
        <path
          opacity="0.2"
          d="M88.2461 89.488C88.8002 87.9672 90.4826 87.1827 92.0038 87.7357L140.204 105.259C141.725 105.812 142.509 107.494 141.955 109.014C141.401 110.535 139.719 111.32 138.198 110.767L89.9971 93.2429C88.4759 92.6899 87.692 91.0087 88.2461 89.488Z"
          fill="#B3BAC1"
        />
        <g filter="url(#filter2_ddddi_2129_77281)">
          <path
            d="M50.4725 11.956C50.4725 6.45746 54.9299 2 60.4285 2H127.632C133.13 2 137.588 6.45747 137.588 11.956V112.346C137.588 117.845 133.13 122.302 127.632 122.302H60.4285C54.9299 122.302 50.4725 117.845 50.4725 112.346V11.956Z"
            fill="#F9FAFA"
          />
        </g>
        <path
          opacity="0.2"
          fill-rule="evenodd"
          clip-rule="evenodd"
          d="M88.8707 19.8231C90.5064 19.1456 92.2596 18.7969 94.0301 18.7969C95.8006 18.7969 97.5538 19.1456 99.1895 19.8231C100.825 20.5007 102.311 21.4938 103.563 22.7457C104.815 23.9976 105.808 25.4839 106.486 27.1196C107.163 28.7553 107.512 30.5085 107.512 32.279C107.512 34.0495 107.163 35.8027 106.486 37.4384C105.808 39.0741 104.815 40.5604 103.563 41.8123C103.327 42.0484 103.083 42.2753 102.831 42.4926C102.791 42.5309 102.749 42.567 102.704 42.6004C101.65 43.4859 100.465 44.2064 99.1895 44.7349C97.5538 45.4124 95.8006 45.7611 94.0301 45.7611C92.2596 45.7611 90.5064 45.4124 88.8707 44.7349C87.235 44.0573 85.7487 43.0642 84.4968 41.8123C83.2449 40.5604 82.2518 39.0741 81.5742 37.4384C80.8967 35.8027 80.548 34.0495 80.548 32.279C80.548 30.5085 80.8967 28.7553 81.5742 27.1196C82.2518 25.4839 83.2449 23.9976 84.4968 22.7457C85.7487 21.4938 87.235 20.5007 88.8707 19.8231ZM102.275 39.2331C102.989 38.3864 103.569 37.4332 103.995 36.4065C104.537 35.0979 104.816 33.6954 104.816 32.279C104.816 30.8626 104.537 29.4601 103.995 28.1515C103.453 26.8429 102.658 25.6539 101.657 24.6524C100.655 23.6508 99.4662 22.8563 98.1576 22.3143C96.849 21.7723 95.4465 21.4933 94.0301 21.4933C92.6137 21.4933 91.2112 21.7723 89.9026 22.3143C88.594 22.8563 87.405 23.6508 86.4035 24.6524C85.4019 25.6539 84.6074 26.8429 84.0654 28.1515C83.5234 29.4601 83.2444 30.8626 83.2444 32.279C83.2444 33.6954 83.5234 35.0979 84.0654 36.4065C84.4907 37.4333 85.0715 38.3865 85.7857 39.2333C86.2016 38.6313 86.7154 38.0971 87.3101 37.655C88.4733 36.7901 89.8842 36.3233 91.3337 36.3236M87.8043 41.0864C88.0809 40.593 88.4597 40.1602 88.9189 39.8188C89.6169 39.2999 90.4635 39.0198 91.3333 39.0201H96.7265C97.5974 39.0198 98.4456 39.3005 99.144 39.8207C99.6021 40.1618 99.98 40.5939 100.256 41.0863C99.6033 41.5477 98.8997 41.9363 98.1576 42.2437C96.849 42.7857 95.4465 43.0647 94.0301 43.0647C92.6137 43.0647 91.2112 42.7857 89.9026 42.2437C89.1606 41.9363 88.457 41.5478 87.8043 41.0864ZM102.275 39.2331C101.86 38.6326 101.347 38.0995 100.754 37.658C99.5905 36.7912 98.1778 36.3232 96.7265 36.3236C96.7264 36.3236 96.7267 36.3236 96.7265 36.3236H91.3337M90.2168 25.7693C91.2281 24.7579 92.5998 24.1897 94.0301 24.1897C95.4604 24.1897 96.8321 24.7579 97.8434 25.7693C98.8548 26.7806 99.4229 28.1523 99.4229 29.5826C99.4229 31.0128 98.8548 32.3845 97.8434 33.3959C96.8321 34.4072 95.4604 34.9754 94.0301 34.9754C92.5998 34.9754 91.2281 34.4072 90.2168 33.3959C89.2054 32.3845 88.6372 31.0128 88.6372 29.5826C88.6372 28.1523 89.2054 26.7806 90.2168 25.7693ZM94.0301 26.8861C93.315 26.8861 92.6291 27.1702 92.1234 27.6759C91.6178 28.1816 91.3337 28.8674 91.3337 29.5826C91.3337 30.2977 91.6178 30.9836 92.1234 31.4892C92.6291 31.9949 93.315 32.279 94.0301 32.279C94.7452 32.279 95.4311 31.9949 95.9368 31.4892C96.4424 30.9836 96.7265 30.2977 96.7265 29.5826C96.7265 28.8674 96.4424 28.1816 95.9368 27.6759C95.4311 27.1702 94.7452 26.8861 94.0301 26.8861Z"
          fill="#B3BAC1"
        />
        <path
          opacity="0.2"
          d="M98.5932 70.8656C98.5932 69.0327 100.079 67.5469 101.912 67.5469H123.483C125.316 67.5469 126.802 69.0327 126.802 70.8656C126.802 72.6984 125.316 74.1842 123.483 74.1842H101.912C100.079 74.1842 98.5932 72.6984 98.5932 70.8656Z"
          fill="#B3BAC1"
        />
        <path
          opacity="0.2"
          d="M62.0878 81.6546C62.0878 79.8218 63.5736 78.3359 65.4064 78.3359H123.483C125.316 78.3359 126.802 79.8218 126.802 81.6546C126.802 83.4875 125.316 84.9733 123.483 84.9733H65.4064C63.5736 84.9733 62.0878 83.4875 62.0878 81.6546Z"
          fill="#B3BAC1"
        />
        <path
          opacity="0.2"
          d="M62.0878 92.4359C62.0878 90.603 63.5736 89.1172 65.4064 89.1172H91.1262C92.959 89.1172 94.4449 90.603 94.4449 92.4359C94.4449 94.2687 92.959 95.7545 91.1262 95.7545H65.4064C63.5736 95.7545 62.0878 94.2687 62.0878 92.4359Z"
          fill="#B3BAC1"
        />
        <path
          opacity="0.2"
          d="M62.0878 103.225C62.0878 101.392 63.5736 99.9062 65.4064 99.9062H123.483C125.316 99.9062 126.802 101.392 126.802 103.225C126.802 105.058 125.316 106.544 123.483 106.544H65.4064C63.5736 106.544 62.0878 105.058 62.0878 103.225Z"
          fill="#B3BAC1"
        />
        <defs>
          <filter
            id="filter0_ddddi_2129_77281"
            x="0.701483"
            y="2.91721"
            width="120.269"
            height="151.153"
            filterUnits="userSpaceOnUse"
            color-interpolation-filters="sRGB"
          >
            <feFlood flood-opacity="0" result="BackgroundImageFix" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="1.03436" />
            <feGaussianBlur stdDeviation="1.29295" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.12 0"
            />
            <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_2129_77281" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="5.17181" />
            <feGaussianBlur stdDeviation="2.58591" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.1 0"
            />
            <feBlend
              mode="normal"
              in2="effect1_dropShadow_2129_77281"
              result="effect2_dropShadow_2129_77281"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="11.378" />
            <feGaussianBlur stdDeviation="3.36168" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.06 0"
            />
            <feBlend
              mode="normal"
              in2="effect2_dropShadow_2129_77281"
              result="effect3_dropShadow_2129_77281"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="20.1701" />
            <feGaussianBlur stdDeviation="4.13745" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.02 0"
            />
            <feBlend
              mode="normal"
              in2="effect3_dropShadow_2129_77281"
              result="effect4_dropShadow_2129_77281"
            />
            <feBlend
              mode="normal"
              in="SourceGraphic"
              in2="effect4_dropShadow_2129_77281"
              result="shape"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="-0.517181" />
            <feGaussianBlur stdDeviation="0.258591" />
            <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.25 0"
            />
            <feBlend mode="normal" in2="shape" result="effect5_innerShadow_2129_77281" />
          </filter>
          <filter
            id="filter1_ddddi_2129_77281"
            x="67.0386"
            y="2.91721"
            width="120.269"
            height="151.161"
            filterUnits="userSpaceOnUse"
            color-interpolation-filters="sRGB"
          >
            <feFlood flood-opacity="0" result="BackgroundImageFix" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="1.03436" />
            <feGaussianBlur stdDeviation="1.29295" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.12 0"
            />
            <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_2129_77281" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="5.17181" />
            <feGaussianBlur stdDeviation="2.58591" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.1 0"
            />
            <feBlend
              mode="normal"
              in2="effect1_dropShadow_2129_77281"
              result="effect2_dropShadow_2129_77281"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="11.378" />
            <feGaussianBlur stdDeviation="3.36168" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.06 0"
            />
            <feBlend
              mode="normal"
              in2="effect2_dropShadow_2129_77281"
              result="effect3_dropShadow_2129_77281"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="20.1701" />
            <feGaussianBlur stdDeviation="4.13745" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.02 0"
            />
            <feBlend
              mode="normal"
              in2="effect3_dropShadow_2129_77281"
              result="effect4_dropShadow_2129_77281"
            />
            <feBlend
              mode="normal"
              in="SourceGraphic"
              in2="effect4_dropShadow_2129_77281"
              result="shape"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="-0.517181" />
            <feGaussianBlur stdDeviation="0.258591" />
            <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.25 0"
            />
            <feBlend mode="normal" in2="shape" result="effect5_innerShadow_2129_77281" />
          </filter>
          <filter
            id="filter2_ddddi_2129_77281"
            x="41.1021"
            y="0.243054"
            width="105.856"
            height="154.272"
            filterUnits="userSpaceOnUse"
            color-interpolation-filters="sRGB"
          >
            <feFlood flood-opacity="0" result="BackgroundImageFix" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="1.1713" />
            <feGaussianBlur stdDeviation="1.46412" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.12 0"
            />
            <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_2129_77281" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="5.85649" />
            <feGaussianBlur stdDeviation="2.92824" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.1 0"
            />
            <feBlend
              mode="normal"
              in2="effect1_dropShadow_2129_77281"
              result="effect2_dropShadow_2129_77281"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="12.8843" />
            <feGaussianBlur stdDeviation="3.80672" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.06 0"
            />
            <feBlend
              mode="normal"
              in2="effect2_dropShadow_2129_77281"
              result="effect3_dropShadow_2129_77281"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="22.8403" />
            <feGaussianBlur stdDeviation="4.68519" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.02 0"
            />
            <feBlend
              mode="normal"
              in2="effect3_dropShadow_2129_77281"
              result="effect4_dropShadow_2129_77281"
            />
            <feBlend
              mode="normal"
              in="SourceGraphic"
              in2="effect4_dropShadow_2129_77281"
              result="shape"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="-0.585649" />
            <feGaussianBlur stdDeviation="0.292824" />
            <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.25 0"
            />
            <feBlend mode="normal" in2="shape" result="effect5_innerShadow_2129_77281" />
          </filter>
          <clipPath id="clip0_2129_77281">
            <rect
              width="28.5743"
              height="28.5743"
              fill="white"
              transform="matrix(0.939817 -0.341679 0.342362 0.939568 33.4873 31.7266)"
            />
          </clipPath>
          <clipPath id="clip1_2129_77281">
            <rect
              width="28.5743"
              height="28.5743"
              fill="white"
              transform="matrix(0.939817 0.341679 -0.342362 0.939568 127.668 21.9609)"
            />
          </clipPath>
        </defs>
      </svg>
    </div>
    """
  end

  defp background_grid_dark(assigns) do
    ~H"""
    <div data-part="background" data-style="dark">
      <svg
        width="1216"
        height="294"
        viewBox="0 0 1216 294"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <mask
          id="mask0_2122_72765"
          style="mask-type:alpha"
          maskUnits="userSpaceOnUse"
          x="0"
          y="0"
          width="1216"
          height="294"
        >
          <rect width="1216" height="294" fill="url(#paint0_radial_2122_72765)" fill-opacity="0.25" />
        </mask>
        <g mask="url(#mask0_2122_72765)">
          <path
            d="M554.231 0H604.615M554.231 0V50.3846M554.231 0H503.846M604.615 0V50.3846M604.615 0H655V50.3846M604.615 50.3846H554.231M604.615 50.3846H655M604.615 50.3846V100.769M554.231 50.3846V100.769M554.231 50.3846H503.846M655 50.3846V100.769M604.615 100.769H554.231M604.615 100.769V151.154M604.615 100.769H655M554.231 100.769V151.154M554.231 100.769H503.846M604.615 151.154H554.231M604.615 151.154V201.538M604.615 151.154H655M554.231 151.154V201.538M554.231 151.154H503.846M604.615 201.538H554.231M604.615 201.538V251.923M604.615 201.538H655M554.231 201.538V251.923M554.231 201.538H503.846M604.615 251.923H554.231M604.615 251.923V302.308M604.615 251.923H655M554.231 251.923V302.308M554.231 251.923H503.846M604.615 302.308H554.231M604.615 302.308V352.692M604.615 302.308H655M554.231 302.308V352.692M554.231 302.308H503.846M604.615 352.692H554.231M604.615 352.692V403.077M604.615 352.692H655M554.231 352.692V403.077M554.231 352.692H503.846M604.615 403.077H554.231M604.615 403.077V453.462M604.615 403.077H655M554.231 403.077V453.462M554.231 403.077H503.846M604.615 453.462H554.231M604.615 453.462H655V403.077M554.231 453.462H503.846M655 100.769V151.154M655 151.154V201.538M655 201.538V251.923M655 251.923V302.308M655 302.308V352.692M655 352.692V403.077M50.3846 0H0V50.3846M50.3846 0V50.3846M50.3846 0H100.769M50.3846 50.3846H0M50.3846 50.3846H100.769M50.3846 50.3846V100.769M0 50.3846V100.769M100.769 0V50.3846M100.769 0H151.154M100.769 50.3846H151.154M100.769 50.3846V100.769M151.154 0V50.3846M151.154 0H201.538M151.154 50.3846H201.538M151.154 50.3846V100.769M201.538 0V50.3846M201.538 0H251.923M201.538 50.3846H251.923M201.538 50.3846V100.769M251.923 0V50.3846M251.923 0H302.308M251.923 50.3846H302.308M251.923 50.3846V100.769M302.308 0V50.3846M302.308 0H352.692M302.308 50.3846H352.692M302.308 50.3846V100.769M352.692 0V50.3846M352.692 0H403.077M352.692 50.3846H403.077M352.692 50.3846V100.769M403.077 0V50.3846M403.077 0H453.462M403.077 50.3846H453.462M403.077 50.3846V100.769M453.462 0V50.3846M453.462 0H503.846M453.462 50.3846H503.846M453.462 50.3846V100.769M503.846 0V50.3846M503.846 50.3846V100.769M50.3846 100.769H0M50.3846 100.769V151.154M50.3846 100.769H100.769M0 100.769V151.154M50.3846 151.154H0M50.3846 151.154V201.538M50.3846 151.154H100.769M0 151.154V201.538M50.3846 201.538H0M50.3846 201.538V251.923M50.3846 201.538H100.769M0 201.538V251.923M50.3846 251.923H0M50.3846 251.923V302.308M50.3846 251.923H100.769M0 251.923V302.308M50.3846 302.308H0M50.3846 302.308V352.692M50.3846 302.308H100.769M0 302.308V352.692M50.3846 352.692H0M50.3846 352.692V403.077M50.3846 352.692H100.769M0 352.692V403.077M50.3846 403.077H0M50.3846 403.077V453.462M50.3846 403.077H100.769M0 403.077V453.462H50.3846M50.3846 453.462H100.769M100.769 100.769V151.154M100.769 100.769H151.154M100.769 151.154V201.538M100.769 151.154H151.154M100.769 201.538V251.923M100.769 201.538H151.154M100.769 251.923V302.308M100.769 251.923H151.154M100.769 302.308V352.692M100.769 302.308H151.154M100.769 352.692V403.077M100.769 352.692H151.154M100.769 403.077V453.462M100.769 403.077H151.154M100.769 453.462H151.154M151.154 100.769V151.154M151.154 100.769H201.538M151.154 151.154V201.538M151.154 151.154H201.538M151.154 201.538V251.923M151.154 201.538H201.538M151.154 251.923V302.308M151.154 251.923H201.538M151.154 302.308V352.692M151.154 302.308H201.538M151.154 352.692V403.077M151.154 352.692H201.538M151.154 403.077V453.462M151.154 403.077H201.538M151.154 453.462H201.538M201.538 100.769V151.154M201.538 100.769H251.923M201.538 151.154V201.538M201.538 151.154H251.923M201.538 201.538V251.923M201.538 201.538H251.923M201.538 251.923V302.308M201.538 251.923H251.923M201.538 302.308V352.692M201.538 302.308H251.923M201.538 352.692V403.077M201.538 352.692H251.923M201.538 403.077V453.462M201.538 403.077H251.923M201.538 453.462H251.923M251.923 100.769V151.154M251.923 100.769H302.308M251.923 151.154V201.538M251.923 151.154H302.308M251.923 201.538V251.923M251.923 201.538H302.308M251.923 251.923V302.308M251.923 251.923H302.308M251.923 302.308V352.692M251.923 302.308H302.308M251.923 352.692V403.077M251.923 352.692H302.308M251.923 403.077V453.462M251.923 403.077H302.308M251.923 453.462H302.308M302.308 100.769V151.154M302.308 100.769H352.692M302.308 151.154V201.538M302.308 151.154H352.692M302.308 201.538V251.923M302.308 201.538H352.692M302.308 251.923V302.308M302.308 251.923H352.692M302.308 302.308V352.692M302.308 302.308H352.692M302.308 352.692V403.077M302.308 352.692H352.692M302.308 403.077V453.462M302.308 403.077H352.692M302.308 453.462H352.692M352.692 100.769V151.154M352.692 100.769H403.077M352.692 151.154V201.538M352.692 151.154H403.077M352.692 201.538V251.923M352.692 201.538H403.077M352.692 251.923V302.308M352.692 251.923H403.077M352.692 302.308V352.692M352.692 302.308H403.077M352.692 352.692V403.077M352.692 352.692H403.077M352.692 403.077V453.462M352.692 403.077H403.077M352.692 453.462H403.077M403.077 100.769V151.154M403.077 100.769H453.462M403.077 151.154V201.538M403.077 151.154H453.462M403.077 201.538V251.923M403.077 201.538H453.462M403.077 251.923V302.308M403.077 251.923H453.462M403.077 302.308V352.692M403.077 302.308H453.462M403.077 352.692V403.077M403.077 352.692H453.462M403.077 403.077V453.462M403.077 403.077H453.462M403.077 453.462H453.462M453.462 100.769V151.154M453.462 100.769H503.846M453.462 151.154V201.538M453.462 151.154H503.846M453.462 201.538V251.923M453.462 201.538H503.846M453.462 251.923V302.308M453.462 251.923H503.846M453.462 302.308V352.692M453.462 302.308H503.846M453.462 352.692V403.077M453.462 352.692H503.846M453.462 403.077V453.462M453.462 403.077H503.846M453.462 453.462H503.846M503.846 100.769V151.154M503.846 151.154V201.538M503.846 201.538V251.923M503.846 251.923V302.308M503.846 302.308V352.692M503.846 352.692V403.077M503.846 403.077V453.462"
            stroke="url(#paint1_linear_2122_72765)"
          />
          <path
            d="M1209.23 0H1259.62M1209.23 0V50.3846M1209.23 0H1158.85M1259.62 0V50.3846M1259.62 0H1310V50.3846M1259.62 50.3846H1209.23M1259.62 50.3846H1310M1259.62 50.3846V100.769M1209.23 50.3846V100.769M1209.23 50.3846H1158.85M1310 50.3846V100.769M1259.62 100.769H1209.23M1259.62 100.769V151.154M1259.62 100.769H1310M1209.23 100.769V151.154M1209.23 100.769H1158.85M1259.62 151.154H1209.23M1259.62 151.154V201.538M1259.62 151.154H1310M1209.23 151.154V201.538M1209.23 151.154H1158.85M1259.62 201.538H1209.23M1259.62 201.538V251.923M1259.62 201.538H1310M1209.23 201.538V251.923M1209.23 201.538H1158.85M1259.62 251.923H1209.23M1259.62 251.923V302.308M1259.62 251.923H1310M1209.23 251.923V302.308M1209.23 251.923H1158.85M1259.62 302.308H1209.23M1259.62 302.308V352.692M1259.62 302.308H1310M1209.23 302.308V352.692M1209.23 302.308H1158.85M1259.62 352.692H1209.23M1259.62 352.692V403.077M1259.62 352.692H1310M1209.23 352.692V403.077M1209.23 352.692H1158.85M1259.62 403.077H1209.23M1259.62 403.077V453.462M1259.62 403.077H1310M1209.23 403.077V453.462M1209.23 403.077H1158.85M1259.62 453.462H1209.23M1259.62 453.462H1310V403.077M1209.23 453.462H1158.85M1310 100.769V151.154M1310 151.154V201.538M1310 201.538V251.923M1310 251.923V302.308M1310 302.308V352.692M1310 352.692V403.077M705.385 0H655V50.3846M705.385 0V50.3846M705.385 0H755.769M705.385 50.3846H655M705.385 50.3846H755.769M705.385 50.3846V100.769M655 50.3846V100.769M755.769 0V50.3846M755.769 0H806.154M755.769 50.3846H806.154M755.769 50.3846V100.769M806.154 0V50.3846M806.154 0H856.538M806.154 50.3846H856.538M806.154 50.3846V100.769M856.538 0V50.3846M856.538 0H906.923M856.538 50.3846H906.923M856.538 50.3846V100.769M906.923 0V50.3846M906.923 0H957.308M906.923 50.3846H957.308M906.923 50.3846V100.769M957.308 0V50.3846M957.308 0H1007.69M957.308 50.3846H1007.69M957.308 50.3846V100.769M1007.69 0V50.3846M1007.69 0H1058.08M1007.69 50.3846H1058.08M1007.69 50.3846V100.769M1058.08 0V50.3846M1058.08 0H1108.46M1058.08 50.3846H1108.46M1058.08 50.3846V100.769M1108.46 0V50.3846M1108.46 0H1158.85M1108.46 50.3846H1158.85M1108.46 50.3846V100.769M1158.85 0V50.3846M1158.85 50.3846V100.769M705.385 100.769H655M705.385 100.769V151.154M705.385 100.769H755.769M655 100.769V151.154M705.385 151.154H655M705.385 151.154V201.538M705.385 151.154H755.769M655 151.154V201.538M705.385 201.538H655M705.385 201.538V251.923M705.385 201.538H755.769M655 201.538V251.923M705.385 251.923H655M705.385 251.923V302.308M705.385 251.923H755.769M655 251.923V302.308M705.385 302.308H655M705.385 302.308V352.692M705.385 302.308H755.769M655 302.308V352.692M705.385 352.692H655M705.385 352.692V403.077M705.385 352.692H755.769M655 352.692V403.077M705.385 403.077H655M705.385 403.077V453.462M705.385 403.077H755.769M655 403.077V453.462H705.385M705.385 453.462H755.769M755.769 100.769V151.154M755.769 100.769H806.154M755.769 151.154V201.538M755.769 151.154H806.154M755.769 201.538V251.923M755.769 201.538H806.154M755.769 251.923V302.308M755.769 251.923H806.154M755.769 302.308V352.692M755.769 302.308H806.154M755.769 352.692V403.077M755.769 352.692H806.154M755.769 403.077V453.462M755.769 403.077H806.154M755.769 453.462H806.154M806.154 100.769V151.154M806.154 100.769H856.538M806.154 151.154V201.538M806.154 151.154H856.538M806.154 201.538V251.923M806.154 201.538H856.538M806.154 251.923V302.308M806.154 251.923H856.538M806.154 302.308V352.692M806.154 302.308H856.538M806.154 352.692V403.077M806.154 352.692H856.538M806.154 403.077V453.462M806.154 403.077H856.538M806.154 453.462H856.538M856.538 100.769V151.154M856.538 100.769H906.923M856.538 151.154V201.538M856.538 151.154H906.923M856.538 201.538V251.923M856.538 201.538H906.923M856.538 251.923V302.308M856.538 251.923H906.923M856.538 302.308V352.692M856.538 302.308H906.923M856.538 352.692V403.077M856.538 352.692H906.923M856.538 403.077V453.462M856.538 403.077H906.923M856.538 453.462H906.923M906.923 100.769V151.154M906.923 100.769H957.308M906.923 151.154V201.538M906.923 151.154H957.308M906.923 201.538V251.923M906.923 201.538H957.308M906.923 251.923V302.308M906.923 251.923H957.308M906.923 302.308V352.692M906.923 302.308H957.308M906.923 352.692V403.077M906.923 352.692H957.308M906.923 403.077V453.462M906.923 403.077H957.308M906.923 453.462H957.308M957.308 100.769V151.154M957.308 100.769H1007.69M957.308 151.154V201.538M957.308 151.154H1007.69M957.308 201.538V251.923M957.308 201.538H1007.69M957.308 251.923V302.308M957.308 251.923H1007.69M957.308 302.308V352.692M957.308 302.308H1007.69M957.308 352.692V403.077M957.308 352.692H1007.69M957.308 403.077V453.462M957.308 403.077H1007.69M957.308 453.462H1007.69M1007.69 100.769V151.154M1007.69 100.769H1058.08M1007.69 151.154V201.538M1007.69 151.154H1058.08M1007.69 201.538V251.923M1007.69 201.538H1058.08M1007.69 251.923V302.308M1007.69 251.923H1058.08M1007.69 302.308V352.692M1007.69 302.308H1058.08M1007.69 352.692V403.077M1007.69 352.692H1058.08M1007.69 403.077V453.462M1007.69 403.077H1058.08M1007.69 453.462H1058.08M1058.08 100.769V151.154M1058.08 100.769H1108.46M1058.08 151.154V201.538M1058.08 151.154H1108.46M1058.08 201.538V251.923M1058.08 201.538H1108.46M1058.08 251.923V302.308M1058.08 251.923H1108.46M1058.08 302.308V352.692M1058.08 302.308H1108.46M1058.08 352.692V403.077M1058.08 352.692H1108.46M1058.08 403.077V453.462M1058.08 403.077H1108.46M1058.08 453.462H1108.46M1108.46 100.769V151.154M1108.46 100.769H1158.85M1108.46 151.154V201.538M1108.46 151.154H1158.85M1108.46 201.538V251.923M1108.46 201.538H1158.85M1108.46 251.923V302.308M1108.46 251.923H1158.85M1108.46 302.308V352.692M1108.46 302.308H1158.85M1108.46 352.692V403.077M1108.46 352.692H1158.85M1108.46 403.077V453.462M1108.46 403.077H1158.85M1108.46 453.462H1158.85M1158.85 100.769V151.154M1158.85 151.154V201.538M1158.85 201.538V251.923M1158.85 251.923V302.308M1158.85 302.308V352.692M1158.85 352.692V403.077M1158.85 403.077V453.462"
            stroke="url(#paint2_linear_2122_72765)"
          />
        </g>
        <defs>
          <radialGradient
            id="paint0_radial_2122_72765"
            cx="0"
            cy="0"
            r="1"
            gradientUnits="userSpaceOnUse"
            gradientTransform="translate(608 147) rotate(90) scale(210.044 590.516)"
          >
            <stop stop-color="#313131" stop-opacity="0.5" />
            <stop offset="1" stop-color="#313131" stop-opacity="0" />
          </radialGradient>
          <linearGradient
            id="paint1_linear_2122_72765"
            x1="327.5"
            y1="0"
            x2="327.5"
            y2="453.462"
            gradientUnits="userSpaceOnUse"
          >
            <stop stop-color="#AEAEAE" />
            <stop offset="1" stop-color="#5D5D5D" stop-opacity="0" />
          </linearGradient>
          <linearGradient
            id="paint2_linear_2122_72765"
            x1="982.5"
            y1="0"
            x2="982.5"
            y2="453.462"
            gradientUnits="userSpaceOnUse"
          >
            <stop stop-color="#AEAEAE" />
            <stop offset="1" stop-color="#5D5D5D" stop-opacity="0" />
          </linearGradient>
        </defs>
      </svg>
    </div>
    """
  end

  defp cards_dark(assigns) do
    ~H"""
    <div data-part="cards" data-style="dark">
      <svg
        width="188"
        height="155"
        viewBox="0 0 188 155"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <g filter="url(#filter0_ddddi_2129_72779)">
          <path
            d="M9.50983 36.542C7.84741 31.9797 10.1992 26.9363 14.7627 25.2772L70.5376 4.99974C75.1011 3.34064 80.1482 5.69414 81.8106 10.2564L112.162 93.5524C113.825 98.1147 111.473 103.158 106.909 104.817L51.1344 125.095C46.5709 126.754 41.5238 124.4 39.8614 119.838L9.50983 36.542Z"
            fill="#1F2126"
          />
        </g>
        <g clip-path="url(#clip0_2129_72779)">
          <path
            opacity="0.2"
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M43.7582 31.4887C44.9109 30.433 46.2605 29.6146 47.7299 29.0804C49.1993 28.5462 50.7598 28.3066 52.3222 28.3752C53.8846 28.4438 55.4184 28.8193 56.8359 29.4803C58.2534 30.1414 59.527 31.0749 60.5839 32.2277C61.6407 33.3804 62.4602 34.7298 62.9955 36.1989C63.5308 37.6679 63.7714 39.2278 63.7036 40.7894C63.6358 42.351 63.261 43.8839 62.6004 45.3004C62.4759 45.5675 62.3416 45.8295 62.198 46.0859C62.1766 46.1297 62.1524 46.1724 62.1254 46.2136C61.5186 47.2663 60.753 48.2216 59.8539 49.045C58.7012 50.1008 57.3516 50.9191 55.8822 51.4533C54.4128 51.9875 52.8523 52.2272 51.2899 52.1586C49.7275 52.0899 48.1938 51.7144 46.7762 51.0534C45.3587 50.3924 44.0851 49.4589 43.0283 48.3061C41.9714 47.1533 41.152 45.8039 40.6167 44.3349C40.0814 42.8659 39.8408 41.306 39.9085 39.7444C39.9763 38.1827 40.3512 36.6499 41.0117 35.2334C41.6722 33.8169 42.6055 32.5444 43.7582 31.4887ZM60.751 43.5492C61.0878 42.6312 61.2815 41.6651 61.3241 40.6849C61.3783 39.4356 61.1858 38.1877 60.7576 37.0125C60.3294 35.8372 59.6738 34.7577 58.8283 33.8355C57.9828 32.9133 56.964 32.1665 55.8299 31.6377C54.6959 31.1088 53.4689 30.8084 52.219 30.7535C50.9691 30.6986 49.7207 30.8903 48.5452 31.3177C47.3696 31.7451 46.29 32.3998 45.3678 33.2443C44.4456 34.0889 43.699 35.1069 43.1706 36.2401C42.6422 37.3733 42.3423 38.5995 42.288 39.8489C42.2338 41.0982 42.4263 42.3461 42.8545 43.5213C43.2828 44.6965 43.9383 45.776 44.7838 46.6982C45.4473 47.4219 46.2174 48.0375 47.0662 48.5246C47.2294 47.8996 47.4943 47.3014 47.8542 46.7551C48.5581 45.6866 49.588 44.8735 50.791 44.4364M49.3018 49.4531C49.3822 48.9603 49.5657 48.4869 49.8436 48.0651C50.266 47.4239 50.884 46.936 51.6059 46.6738L56.082 45.0465C56.8047 44.7835 57.5935 44.7605 58.3305 44.9813C58.8138 45.1261 59.258 45.3707 59.6361 45.6959C59.2338 46.2757 58.7673 46.8105 58.2444 47.2894C57.3222 48.134 56.2425 48.7887 55.067 49.216C53.8914 49.6434 52.6431 49.8351 51.3932 49.7802C50.6844 49.7491 49.983 49.639 49.3018 49.4531ZM60.751 43.5492C60.2251 43.1761 59.6388 42.8884 59.0132 42.701C57.7851 42.333 56.4712 42.371 55.2668 42.8092C55.2667 42.8093 55.2669 42.8092 55.2668 42.8092L50.791 44.4364M46.6731 36.0162C47.2067 34.8719 48.1733 33.9866 49.3604 33.555C50.5474 33.1234 51.8576 33.181 53.0028 33.715C54.1479 34.249 55.0342 35.2157 55.4666 36.4024C55.899 37.5891 55.8422 38.8987 55.3086 40.043C54.775 41.1873 53.8083 42.0726 52.6213 42.5042C51.4342 42.9357 50.124 42.8782 48.9789 42.3442C47.8338 41.8102 46.9475 40.8435 46.5151 39.6568C46.0827 38.4701 46.1395 37.1605 46.6731 36.0162ZM50.1756 35.7923C49.5821 36.0081 49.0988 36.4507 48.832 37.0229C48.5652 37.595 48.5367 38.2498 48.753 38.8432C48.9692 39.4366 49.4123 39.9199 49.9849 40.1869C50.5574 40.4539 51.2125 40.4827 51.8061 40.2669C52.3996 40.0511 52.8829 39.6084 53.1497 39.0363C53.4165 38.4641 53.4449 37.8093 53.2287 37.216C53.0125 36.6226 52.5694 36.1393 51.9968 35.8723C51.4242 35.6053 50.7691 35.5765 50.1756 35.7923Z"
            fill="#85888E"
          />
        </g>
        <path
          opacity="0.2"
          d="M67.2573 70.8942C66.7031 69.3734 67.4871 67.6923 69.0082 67.1393L86.9113 60.6305C88.4324 60.0774 90.1148 60.8619 90.6689 62.3827C91.2231 63.9035 90.4391 65.5846 88.918 66.1376L71.0149 72.6464C69.4938 73.1995 67.8114 72.415 67.2573 70.8942Z"
          fill="#85888E"
        />
        <path
          opacity="0.2"
          d="M40.2202 90.8551C39.666 89.3344 40.4499 87.6532 41.9711 87.1002L90.1716 69.5765C91.6928 69.0235 93.3751 69.808 93.9293 71.3287C94.4834 72.8495 93.6995 74.5306 92.1783 75.0837L43.9778 92.6074C42.4567 93.1604 40.7743 92.3759 40.2202 90.8551Z"
          fill="#85888E"
        />
        <path
          opacity="0.2"
          d="M43.4814 99.8083C42.9272 98.2875 43.7112 96.6064 45.2323 96.0533L66.5783 88.2928C68.0994 87.7398 69.7818 88.5243 70.3359 90.0451C70.8901 91.5658 70.1062 93.247 68.585 93.8L47.2391 101.561C45.7179 102.114 44.0355 101.329 43.4814 99.8083Z"
          fill="#85888E"
        />
        <path
          opacity="0.2"
          d="M46.7416 108.754C46.1875 107.233 46.9714 105.552 48.4926 104.999L96.6931 87.4749C98.2142 86.9219 99.8966 87.7064 100.451 89.2272C101.005 90.7479 100.221 92.4291 98.6998 92.9821L50.4993 110.506C48.9781 111.059 47.2958 110.274 46.7416 108.754Z"
          fill="#85888E"
        />
        <g filter="url(#filter1_ddddi_2129_72779)">
          <path
            d="M106.199 10.2608C107.861 5.69847 112.908 3.34497 117.472 5.00407L173.247 25.2815C177.81 26.9406 180.162 31.984 178.499 36.5463L148.148 119.842C146.485 124.405 141.438 126.758 136.875 125.099L81.1 104.822C76.5365 103.162 74.1847 98.119 75.8471 93.5567L106.199 10.2608Z"
            fill="#1F2126"
          />
        </g>
        <g clip-path="url(#clip1_2129_72779)">
          <path
            opacity="0.2"
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M135.688 28.3784C137.251 28.3098 138.811 28.5494 140.28 29.0836C141.75 29.6178 143.099 30.4362 144.252 31.4919C145.405 32.5476 146.338 33.8201 146.999 35.2366C147.659 36.6531 148.034 38.1859 148.102 39.7476C148.17 41.3092 147.929 42.8691 147.394 44.3381C146.858 45.8071 146.039 47.1565 144.982 48.3093C143.925 49.4621 142.652 50.3956 141.234 51.0566C140.967 51.1812 140.695 51.2957 140.42 51.4C140.376 51.4198 140.33 51.4369 140.283 51.4512C139.14 51.868 137.939 52.1082 136.72 52.1618C135.158 52.2304 133.598 51.9907 132.128 51.4565C130.659 50.9223 129.309 50.104 128.156 49.0482C127.004 47.9925 126.07 46.7201 125.41 45.3036C124.749 43.8871 124.375 42.3542 124.307 40.7926C124.239 39.231 124.48 37.6711 125.015 36.2021C125.55 34.733 126.37 33.3836 127.427 32.2309C128.483 31.0781 129.757 30.1446 131.174 29.4835C132.592 28.8225 134.126 28.447 135.688 28.3784ZM140.944 48.5277C141.793 48.0406 142.563 47.425 143.227 46.7014C144.072 45.7792 144.728 44.6997 145.156 43.5245C145.584 42.3493 145.777 41.1014 145.722 39.8521C145.668 38.6027 145.368 37.3765 144.84 36.2433C144.311 35.1101 143.565 34.0921 142.643 33.2475C141.72 32.403 140.641 31.7483 139.465 31.3209C138.29 30.8935 137.041 30.7018 135.791 30.7567C134.541 30.8116 133.314 31.112 132.18 31.6409C131.046 32.1697 130.028 32.9165 129.182 33.8387C128.337 34.7609 127.681 35.8404 127.253 37.0157C126.825 38.1909 126.632 39.4388 126.686 40.6881C126.729 41.6684 126.923 42.6345 127.259 43.5526C127.787 43.1786 128.374 42.8904 129.002 42.703C130.229 42.3364 131.541 42.3748 132.744 42.8124M128.374 45.6992C128.753 45.3734 129.198 45.1286 129.683 44.9838C130.419 44.7639 131.206 44.7869 131.928 45.0496L136.404 46.6769C137.127 46.9394 137.746 47.4283 138.168 48.0706C138.446 48.4919 138.628 48.9644 138.709 49.4563C138.028 49.6422 137.326 49.7523 136.617 49.7834C135.367 49.8383 134.119 49.6466 132.943 49.2192C131.768 48.7919 130.688 48.1372 129.766 47.2926C129.243 46.8137 128.777 46.279 128.374 45.6992ZM140.944 48.5277C140.782 47.9042 140.518 47.3074 140.159 46.7621C139.455 45.6917 138.424 44.8772 137.219 44.4396C137.219 44.4396 137.219 44.4397 137.219 44.4396L132.744 42.8124M135.008 33.7182C136.153 33.1842 137.463 33.1266 138.65 33.5582C139.837 33.9898 140.804 34.8751 141.337 36.0194C141.871 37.1637 141.928 38.4733 141.495 39.66C141.063 40.8467 140.177 41.8134 139.031 42.3474C137.886 42.8814 136.576 42.9389 135.389 42.5074C134.202 42.0758 133.235 41.1905 132.702 40.0462C132.168 38.9019 132.111 37.5923 132.544 36.4056C132.976 35.2189 133.862 34.2522 135.008 33.7182ZM137.835 35.7955C137.241 35.5797 136.586 35.6085 136.014 35.8755C135.441 36.1425 134.998 36.6258 134.782 37.2192C134.565 37.8125 134.594 38.4673 134.861 39.0395C135.127 39.6116 135.611 40.0543 136.204 40.2701C136.798 40.4859 137.453 40.4571 138.026 40.1901C138.598 39.9231 139.041 39.4398 139.257 38.8464C139.474 38.253 139.445 37.5982 139.178 37.0261C138.912 36.4539 138.428 36.0113 137.835 35.7955Z"
            fill="#85888E"
          />
        </g>
        <path
          opacity="0.2"
          d="M128.327 73.6598C128.881 72.1391 130.563 71.3546 132.085 71.9076L149.988 78.4164C151.509 78.9694 152.293 80.6506 151.739 82.1714C151.184 83.6921 149.502 84.4766 147.981 83.9236L130.078 77.4148C128.557 76.8617 127.773 75.1806 128.327 73.6598Z"
          fill="#85888E"
        />
        <path
          opacity="0.2"
          d="M94.7684 71.5973C95.3225 70.0766 97.0049 69.2921 98.526 69.8451L146.727 87.3688C148.248 87.9219 149.032 89.603 148.477 91.1238C147.923 92.6445 146.241 93.429 144.72 92.876L96.5193 75.3523C94.9982 74.7992 94.2142 73.1181 94.7684 71.5973Z"
          fill="#85888E"
        />
        <path
          opacity="0.2"
          d="M91.5074 80.5426C92.0615 79.0219 93.7439 78.2374 95.2651 78.7904L116.611 86.5509C118.132 87.104 118.916 88.7851 118.362 90.3059C117.808 91.8266 116.125 92.6111 114.604 92.0581L93.2583 84.2976C91.7372 83.7446 90.9532 82.0634 91.5074 80.5426Z"
          fill="#85888E"
        />
        <path
          opacity="0.2"
          d="M88.2462 89.488C88.8003 87.9672 90.4827 87.1827 92.0038 87.7357L140.204 105.259C141.725 105.812 142.509 107.494 141.955 109.014C141.401 110.535 139.719 111.32 138.198 110.767L89.9971 93.2429C88.476 92.6899 87.692 91.0087 88.2462 89.488Z"
          fill="#85888E"
        />
        <g filter="url(#filter2_ddddi_2129_72779)">
          <path
            d="M50.4724 11.956C50.4724 6.45746 54.9299 2 60.4284 2H127.632C133.13 2 137.588 6.45747 137.588 11.956V112.346C137.588 117.845 133.13 122.302 127.632 122.302H60.4284C54.9299 122.302 50.4724 117.845 50.4724 112.346V11.956Z"
            fill="#1F2126"
          />
        </g>
        <path
          opacity="0.2"
          fill-rule="evenodd"
          clip-rule="evenodd"
          d="M88.8708 19.8231C90.5066 19.1456 92.2597 18.7969 94.0302 18.7969C95.8007 18.7969 97.5539 19.1456 99.1896 19.8231C100.825 20.5007 102.312 21.4938 103.564 22.7457C104.815 23.9976 105.809 25.4839 106.486 27.1196C107.164 28.7553 107.512 30.5085 107.512 32.279C107.512 34.0495 107.164 35.8027 106.486 37.4384C105.809 39.0741 104.815 40.5604 103.564 41.8123C103.327 42.0484 103.083 42.2753 102.831 42.4926C102.791 42.5309 102.749 42.567 102.704 42.6004C101.65 43.4859 100.465 44.2064 99.1896 44.7349C97.5539 45.4124 95.8007 45.7611 94.0302 45.7611C92.2597 45.7611 90.5066 45.4124 88.8708 44.7349C87.2351 44.0573 85.7488 43.0642 84.4969 41.8123C83.245 40.5604 82.2519 39.0741 81.5744 37.4384C80.8968 35.8027 80.5481 34.0495 80.5481 32.279C80.5481 30.5085 80.8968 28.7553 81.5744 27.1196C82.2519 25.4839 83.245 23.9976 84.4969 22.7457C85.7488 21.4938 87.2351 20.5007 88.8708 19.8231ZM102.275 39.2331C102.989 38.3864 103.57 37.4332 103.995 36.4065C104.537 35.0979 104.816 33.6954 104.816 32.279C104.816 30.8626 104.537 29.4601 103.995 28.1515C103.453 26.8429 102.658 25.6539 101.657 24.6524C100.655 23.6508 99.4663 22.8563 98.1577 22.3143C96.8491 21.7723 95.4466 21.4933 94.0302 21.4933C92.6138 21.4933 91.2113 21.7723 89.9027 22.3143C88.5941 22.8563 87.4051 23.6508 86.4036 24.6524C85.402 25.6539 84.6076 26.8429 84.0655 28.1515C83.5235 29.4601 83.2445 30.8626 83.2445 32.279C83.2445 33.6954 83.5235 35.0979 84.0655 36.4065C84.4908 37.4333 85.0716 38.3865 85.7859 39.2333C86.2017 38.6313 86.7155 38.0971 87.3102 37.655C88.4734 36.7901 89.8843 36.3233 91.3338 36.3236M87.8044 41.0864C88.0811 40.593 88.4598 40.1602 88.919 39.8188C89.617 39.2999 90.4636 39.0198 91.3334 39.0201H96.7266C97.5975 39.0198 98.4457 39.3005 99.1442 39.8207C99.6022 40.1618 99.9801 40.5939 100.256 41.0863C99.6034 41.5477 98.8998 41.9363 98.1577 42.2437C96.8491 42.7857 95.4466 43.0647 94.0302 43.0647C92.6138 43.0647 91.2113 42.7857 89.9027 42.2437C89.1607 41.9363 88.4571 41.5478 87.8044 41.0864ZM102.275 39.2331C101.86 38.6326 101.348 38.0995 100.755 37.658C99.5906 36.7912 98.1779 36.3232 96.7266 36.3236C96.7265 36.3236 96.7268 36.3236 96.7266 36.3236H91.3338M90.2169 25.7693C91.2283 24.7579 92.5999 24.1897 94.0302 24.1897C95.4605 24.1897 96.8322 24.7579 97.8435 25.7693C98.8549 26.7806 99.4231 28.1523 99.4231 29.5826C99.4231 31.0128 98.8549 32.3845 97.8435 33.3959C96.8322 34.4072 95.4605 34.9754 94.0302 34.9754C92.5999 34.9754 91.2283 34.4072 90.2169 33.3959C89.2055 32.3845 88.6374 31.0128 88.6374 29.5826C88.6374 28.1523 89.2055 26.7806 90.2169 25.7693ZM94.0302 26.8861C93.3151 26.8861 92.6292 27.1702 92.1236 27.6759C91.6179 28.1816 91.3338 28.8674 91.3338 29.5826C91.3338 30.2977 91.6179 30.9836 92.1236 31.4892C92.6292 31.9949 93.3151 32.279 94.0302 32.279C94.7454 32.279 95.4312 31.9949 95.9369 31.4892C96.4426 30.9836 96.7266 30.2977 96.7266 29.5826C96.7266 28.8674 96.4426 28.1816 95.9369 27.6759C95.4312 27.1702 94.7454 26.8861 94.0302 26.8861Z"
          fill="#85888E"
        />
        <path
          opacity="0.2"
          d="M98.5933 70.8656C98.5933 69.0327 100.079 67.5469 101.912 67.5469H123.483C125.316 67.5469 126.802 69.0327 126.802 70.8656C126.802 72.6984 125.316 74.1842 123.483 74.1842H101.912C100.079 74.1842 98.5933 72.6984 98.5933 70.8656Z"
          fill="#85888E"
        />
        <path
          opacity="0.2"
          d="M62.0879 81.6546C62.0879 79.8218 63.5737 78.3359 65.4066 78.3359H123.483C125.316 78.3359 126.802 79.8218 126.802 81.6546C126.802 83.4875 125.316 84.9733 123.483 84.9733H65.4066C63.5737 84.9733 62.0879 83.4875 62.0879 81.6546Z"
          fill="#85888E"
        />
        <path
          opacity="0.2"
          d="M62.0879 92.4359C62.0879 90.603 63.5737 89.1172 65.4066 89.1172H91.1263C92.9592 89.1172 94.445 90.603 94.445 92.4359C94.445 94.2687 92.9592 95.7545 91.1263 95.7545H65.4066C63.5737 95.7545 62.0879 94.2687 62.0879 92.4359Z"
          fill="#85888E"
        />
        <path
          opacity="0.2"
          d="M62.0879 103.225C62.0879 101.392 63.5737 99.9062 65.4066 99.9062H123.483C125.316 99.9062 126.802 101.392 126.802 103.225C126.802 105.058 125.316 106.544 123.483 106.544H65.4066C63.5737 106.544 62.0879 105.058 62.0879 103.225Z"
          fill="#85888E"
        />
        <defs>
          <filter
            id="filter0_ddddi_2129_72779"
            x="0.701422"
            y="2.91721"
            width="120.269"
            height="151.153"
            filterUnits="userSpaceOnUse"
            color-interpolation-filters="sRGB"
          >
            <feFlood flood-opacity="0" result="BackgroundImageFix" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="1.03436" />
            <feGaussianBlur stdDeviation="1.29295" />
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0 0.192157 0 0 0 0.12 0"
            />
            <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_2129_72779" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="5.17181" />
            <feGaussianBlur stdDeviation="2.58591" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.1 0" />
            <feBlend
              mode="normal"
              in2="effect1_dropShadow_2129_72779"
              result="effect2_dropShadow_2129_72779"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="11.378" />
            <feGaussianBlur stdDeviation="3.36168" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.06 0" />
            <feBlend
              mode="normal"
              in2="effect2_dropShadow_2129_72779"
              result="effect3_dropShadow_2129_72779"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="20.1701" />
            <feGaussianBlur stdDeviation="4.13745" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.02 0" />
            <feBlend
              mode="normal"
              in2="effect3_dropShadow_2129_72779"
              result="effect4_dropShadow_2129_72779"
            />
            <feBlend
              mode="normal"
              in="SourceGraphic"
              in2="effect4_dropShadow_2129_72779"
              result="shape"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="-0.517181" />
            <feGaussianBlur stdDeviation="0.258591" />
            <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0" />
            <feBlend mode="normal" in2="shape" result="effect5_innerShadow_2129_72779" />
          </filter>
          <filter
            id="filter1_ddddi_2129_72779"
            x="67.0386"
            y="2.91721"
            width="120.269"
            height="151.161"
            filterUnits="userSpaceOnUse"
            color-interpolation-filters="sRGB"
          >
            <feFlood flood-opacity="0" result="BackgroundImageFix" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="1.03436" />
            <feGaussianBlur stdDeviation="1.29295" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.12 0" />
            <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_2129_72779" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="5.17181" />
            <feGaussianBlur stdDeviation="2.58591" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.1 0" />
            <feBlend
              mode="normal"
              in2="effect1_dropShadow_2129_72779"
              result="effect2_dropShadow_2129_72779"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="11.378" />
            <feGaussianBlur stdDeviation="3.36168" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.06 0" />
            <feBlend
              mode="normal"
              in2="effect2_dropShadow_2129_72779"
              result="effect3_dropShadow_2129_72779"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="20.1701" />
            <feGaussianBlur stdDeviation="4.13745" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.02 0" />
            <feBlend
              mode="normal"
              in2="effect3_dropShadow_2129_72779"
              result="effect4_dropShadow_2129_72779"
            />
            <feBlend
              mode="normal"
              in="SourceGraphic"
              in2="effect4_dropShadow_2129_72779"
              result="shape"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="-0.517181" />
            <feGaussianBlur stdDeviation="0.258591" />
            <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0" />
            <feBlend mode="normal" in2="shape" result="effect5_innerShadow_2129_72779" />
          </filter>
          <filter
            id="filter2_ddddi_2129_72779"
            x="41.102"
            y="0.243054"
            width="105.856"
            height="154.272"
            filterUnits="userSpaceOnUse"
            color-interpolation-filters="sRGB"
          >
            <feFlood flood-opacity="0" result="BackgroundImageFix" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="1.1713" />
            <feGaussianBlur stdDeviation="1.46412" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.12 0" />
            <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_2129_72779" />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="5.85649" />
            <feGaussianBlur stdDeviation="2.92824" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.1 0" />
            <feBlend
              mode="normal"
              in2="effect1_dropShadow_2129_72779"
              result="effect2_dropShadow_2129_72779"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="12.8843" />
            <feGaussianBlur stdDeviation="3.80672" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.06 0" />
            <feBlend
              mode="normal"
              in2="effect2_dropShadow_2129_72779"
              result="effect3_dropShadow_2129_72779"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="22.8403" />
            <feGaussianBlur stdDeviation="4.68519" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.02 0" />
            <feBlend
              mode="normal"
              in2="effect3_dropShadow_2129_72779"
              result="effect4_dropShadow_2129_72779"
            />
            <feBlend
              mode="normal"
              in="SourceGraphic"
              in2="effect4_dropShadow_2129_72779"
              result="shape"
            />
            <feColorMatrix
              in="SourceAlpha"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
              result="hardAlpha"
            />
            <feOffset dy="-0.585649" />
            <feGaussianBlur stdDeviation="0.292824" />
            <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
            <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0" />
            <feBlend mode="normal" in2="shape" result="effect5_innerShadow_2129_72779" />
          </filter>
          <clipPath id="clip0_2129_72779">
            <rect
              width="28.5743"
              height="28.5743"
              fill="white"
              transform="matrix(0.939817 -0.341679 0.342362 0.939568 33.4873 31.7266)"
            />
          </clipPath>
          <clipPath id="clip1_2129_72779">
            <rect
              width="28.5743"
              height="28.5743"
              fill="white"
              transform="matrix(0.939817 0.341679 -0.342362 0.939568 127.668 21.9609)"
            />
          </clipPath>
        </defs>
      </svg>
    </div>
    """
  end
end
