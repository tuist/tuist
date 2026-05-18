defmodule TuistWeb.AcceptInvitationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.AppAuthComponents

  alias Tuist.Accounts
  alias TuistWeb.Authentication

  def mount(%{"token" => token}, session, socket) do
    user = Authentication.current_user(socket)

    socket =
      assign(socket,
        accepted: false,
        declined: false,
        invitation: nil,
        organization: nil,
        organization_name: nil,
        invitee_state: resolve(token, user),
        post_accept_return_to: session["post_invitation_return_to"]
      )

    {:ok, hydrate_invitation(socket, token)}
  end

  defp resolve(token, user) do
    case Accounts.get_invitation_by_token(token) do
      {:ok, invitation} ->
        if user.email == invitation.invitee_email do
          {:ok, invitation}
        else
          {:mismatched, invitation.invitee_email}
        end

      {:error, :not_found} ->
        :not_found
    end
  end

  defp hydrate_invitation(socket, _token) do
    case socket.assigns.invitee_state do
      {:ok, invitation} ->
        {:ok, organization} = Accounts.get_organization_by_id(invitation.organization_id)
        account = Accounts.get_account_from_organization(organization)

        assign(socket,
          invitation: invitation,
          organization: organization,
          organization_name: account.name
        )

      _ ->
        socket
    end
  end

  def render(assigns) do
    ~H"""
    <.noora_accept_invitation {assigns} />
    """
  end

  def noora_accept_invitation(assigns) do
    ~H"""
    <div id="accept-invitation">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <img
              src="/images/tuist_logo_32x32@2x.png"
              alt={dgettext("dashboard_account", "Tuist Logo")}
              data-part="logo"
            />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <%= cond do %>
              <% @accepted -> %>
                <div data-part="header">
                  <h1 data-part="title">
                    {dgettext("dashboard_account", "Invitation accepted!")}
                  </h1>
                  <span data-part="subtitle">
                    {dgettext(
                      "dashboard_account",
                      "You have accepted the invite to join the organization"
                    )}
                  </span>
                </div>
                <.alert
                  id="invitation-accepted"
                  type="secondary"
                  status="success"
                  size="small"
                  title={
                    dgettext(
                      "dashboard_account",
                      "You are now a part of %{organization} organization",
                      organization: @organization_name
                    )
                  }
                />
              <% @declined -> %>
                <div data-part="header">
                  <h1 data-part="title">
                    {dgettext("dashboard_account", "Invitation rejected")}
                  </h1>
                  <span data-part="subtitle">
                    {dgettext(
                      "dashboard_account",
                      "You have rejected the invite to join the organization"
                    )}
                  </span>
                </div>
                <.alert
                  id="invitation-declined"
                  type="secondary"
                  status="error"
                  size="small"
                  title={
                    dgettext(
                      "dashboard_account",
                      "You won’t be able to access this organization unless invited again."
                    )
                  }
                />
              <% match?({:ok, _}, @invitee_state) -> %>
                <div data-part="header">
                  <h1 data-part="title">
                    {dgettext("dashboard_account", "You have been invited")}
                  </h1>
                  <span data-part="subtitle">
                    {dgettext(
                      "dashboard_account",
                      "%{inviter} has invited you to join the %{organization} organization",
                      inviter: @invitation.inviter.account.name,
                      organization: @organization_name
                    )}
                  </span>
                </div>
                <div data-part="actions">
                  <.button
                    variant="primary"
                    size="large"
                    label={dgettext("dashboard_account", "Accept invitation")}
                    phx-click="accept_invitation"
                  />
                  <.button
                    variant="secondary"
                    size="large"
                    label={dgettext("dashboard_account", "Decline")}
                    phx-click="decline_invitation"
                  />
                </div>
              <% match?({:mismatched, _}, @invitee_state) -> %>
                <div data-part="header">
                  <h1 data-part="title">
                    {dgettext("dashboard_account", "Wrong account")}
                  </h1>
                  <span data-part="subtitle">
                    {dgettext(
                      "dashboard_account",
                      "This invitation is addressed to %{email}. Log out and sign in with that account to accept it.",
                      email: elem(@invitee_state, 1)
                    )}
                  </span>
                </div>
              <% true -> %>
                <div data-part="header">
                  <h1 data-part="title">
                    {dgettext("dashboard_account", "Invitation not found")}
                  </h1>
                </div>
                <.alert
                  id="invitation-not-found"
                  type="secondary"
                  status="error"
                  size="small"
                  title={
                    dgettext(
                      "dashboard_account",
                      "We could not find the invitation you are trying to accept. Please ask the inviter to send a new invitation."
                    )
                  }
                />
            <% end %>

            <div
              :if={
                @invitee_state == :not_found or match?({:mismatched, _}, @invitee_state) or @accepted or
                  @declined
              }
              data-part="actions"
            >
              <.button
                variant="primary"
                size="large"
                label={dgettext("dashboard_account", "Dashboard")}
                href={
                  TuistWeb.Authentication.signed_in_path(
                    TuistWeb.Authentication.current_user(assigns)
                  )
                }
              />
            </div>
          </div>
        </div>
      </div>

      <div data-part="background">
        <div data-part="top-right-gradient"></div>
        <div data-part="bottom-left-gradient"></div>
        <div data-part="shell"><.shell /></div>
      </div>
      <.terms_and_privacy />
    </div>
    """
  end

  # Both event handlers re-check `@invitee_state` on the server before
  # mutating. The Accept/Decline buttons are only rendered in the
  # `{:ok, invitation}` state, but a crafted client could still push the
  # event from the not-found / mismatched / declined / accepted states.
  # In those cases `@invitation` and `@organization` are nil and the
  # `Accounts.*` functions would crash on a pattern-match guard.
  def handle_event("accept_invitation", _params, %{assigns: %{invitee_state: {:ok, _}}} = socket) do
    user = Authentication.current_user(socket)

    Accounts.accept_invitation(%{
      invitation: socket.assigns.invitation,
      invitee: user,
      organization: socket.assigns.organization
    })

    case socket.assigns.post_accept_return_to do
      nil ->
        {:noreply, assign(socket, accepted: true)}

      path when is_binary(path) ->
        # Resume whatever flow brought the user here — e.g. the device-code
        # URL from `tuist auth login`. The session key
        # `:post_invitation_return_to` is only read here; subsequent SSO
        # redirects overwrite it, so leaving it behind is harmless.
        {:noreply, redirect(socket, to: path)}
    end
  end

  def handle_event("accept_invitation", _params, socket), do: {:noreply, socket}

  def handle_event("decline_invitation", _params, %{assigns: %{invitee_state: {:ok, _}}} = socket) do
    Accounts.delete_invitation(%{invitation: socket.assigns.invitation})
    {:noreply, assign(socket, declined: true)}
  end

  def handle_event("decline_invitation", _params, socket), do: {:noreply, socket}
end
