defmodule TuistWeb.AcceptInvitationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts

  def mount(params, session, socket) do
    mount_noora(params, session, socket)
  end

  def mount_noora(%{"token" => token}, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])

    case Accounts.get_invitation_by_token(token, user) do
      {:ok, invitation} ->
        {:ok, organization} = Accounts.get_organization_by_id(invitation.organization_id)
        account = Accounts.get_account_from_organization(organization)

        socket =
          assign(socket,
            user: user,
            invitation: invitation,
            organization: organization,
            organization_name: account.name,
            accepted: false,
            declined: false
          )

        {:ok, socket}

      {:error, _} ->
        socket = assign(socket, invitation: nil, accepted: false, declined: false)
        {:ok, socket}
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
            <%= if not is_nil(@invitation) and !@declined and !@accepted do %>
              <div data-part="header">
                <h1 data-part="title">{dgettext("dashboard_account", "You have been invited")}</h1>
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
            <% end %>
            <%= if is_nil(@invitation) do %>
              <div data-part="header">
                <h1 data-part="title">{dgettext("dashboard_account", "Invitation not found")}</h1>
              </div>
              <.alert
                id="invitation-not-found"
                type="secondary"
                status="error"
                size="small"
                title={
                  dgettext(
                    "dashboard_account",
                    "We could not find the invitation you are trying to accept. Please try again."
                  )
                }
              />
            <% end %>
            <%= if @accepted do %>
              <div data-part="header">
                <h1 data-part="title">{dgettext("dashboard_account", "Invitation accepted!")}</h1>
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
                  dgettext("dashboard_account", "You are now a part of %{organization} organization",
                    organization: @organization_name
                  )
                }
              />
            <% end %>
            <%= if @declined do %>
              <div data-part="header">
                <h1 data-part="title">{dgettext("dashboard_account", "Invitation rejected")}</h1>
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
            <% end %>

            <div :if={is_nil(@invitation) or @accepted or @declined} data-part="actions">
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
    </div>
    """
  end

  def handle_event("accept_invitation", _, socket) do
    Accounts.accept_invitation(%{
      invitation: socket.assigns.invitation,
      invitee: socket.assigns.user,
      organization: socket.assigns.organization
    })

    {:noreply, assign(socket, accepted: true)}
  end

  def handle_event("decline_invitation", _, socket) do
    Accounts.delete_invitation(%{invitation: socket.assigns.invitation})

    {:noreply, assign(socket, declined: true)}
  end
end
