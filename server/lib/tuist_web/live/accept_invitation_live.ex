defmodule TuistWeb.AcceptInvitationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.AppAuthComponents

  alias Tuist.Accounts
  alias TuistWeb.Authentication

  def mount(%{"token" => token}, _session, socket) do
    session_user = Authentication.current_user(socket)

    case Accounts.get_invitation_by_token(token) do
      {:ok, invitation} ->
        {:ok, organization} = Accounts.get_organization_by_id(invitation.organization_id)
        account = Accounts.get_account_from_organization(organization)
        invitee = resolve_invitee(session_user, invitation)

        socket =
          assign(socket,
            token: token,
            invitation: invitation,
            organization_name: account.name,
            invitee: invitee,
            mismatched_session_user: mismatched?(session_user, invitation)
          )

        {:ok, socket}

      {:error, :not_found} ->
        socket =
          assign(socket,
            token: token,
            invitation: nil,
            invitee: nil,
            mismatched_session_user: false
          )

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
            <%= cond do %>
              <% is_nil(@invitation) -> %>
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
              <% @mismatched_session_user -> %>
                <div data-part="header">
                  <h1 data-part="title">
                    {dgettext("dashboard_account", "Wrong account")}
                  </h1>
                  <span data-part="subtitle">
                    {dgettext(
                      "dashboard_account",
                      "This invitation is addressed to %{email}. Log out and sign in with that account to accept it.",
                      email: @invitation.invitee_email
                    )}
                  </span>
                </div>
              <% is_nil(@invitee) -> %>
                <div data-part="header">
                  <h1 data-part="title">
                    {dgettext("dashboard_account", "You have been invited")}
                  </h1>
                  <span data-part="subtitle">
                    {dgettext(
                      "dashboard_account",
                      "%{inviter} has invited %{email} to join the %{organization} organization. Create a Tuist account with that email to accept.",
                      inviter: @invitation.inviter.account.name,
                      email: @invitation.invitee_email,
                      organization: @organization_name
                    )}
                  </span>
                </div>
                <div data-part="actions">
                  <.link_button
                    navigate={~p"/users/register"}
                    variant="primary"
                    size="large"
                    label={dgettext("dashboard_account", "Create an account")}
                  />
                </div>
              <% true -> %>
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
                  <form
                    action={~p"/auth/invitations/#{@token}/accept"}
                    method="post"
                    style="display: contents;"
                  >
                    <input
                      type="hidden"
                      name="_csrf_token"
                      value={Phoenix.Controller.get_csrf_token()}
                    />
                    <.button
                      variant="primary"
                      size="large"
                      label={dgettext("dashboard_account", "Accept invitation")}
                    />
                  </form>
                  <form
                    action={~p"/auth/invitations/#{@token}/decline"}
                    method="post"
                    style="display: contents;"
                  >
                    <input
                      type="hidden"
                      name="_csrf_token"
                      value={Phoenix.Controller.get_csrf_token()}
                    />
                    <.button
                      variant="secondary"
                      size="large"
                      label={dgettext("dashboard_account", "Decline")}
                    />
                  </form>
                </div>
            <% end %>

            <div :if={is_nil(@invitation) or @mismatched_session_user} data-part="actions">
              <.link_button
                navigate={~p"/users/log_in"}
                variant="primary"
                size="large"
                label={dgettext("dashboard_account", "Back to login")}
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

  defp resolve_invitee(%{email: email} = user, %{invitee_email: email}), do: user

  defp resolve_invitee(nil, invitation) do
    case Accounts.get_user_by_email(invitation.invitee_email) do
      {:ok, user} -> user
      {:error, :not_found} -> nil
    end
  end

  defp resolve_invitee(_session_user, _invitation), do: nil

  defp mismatched?(nil, _invitation), do: false
  defp mismatched?(%{email: email}, %{invitee_email: email}), do: false
  defp mismatched?(_user, _invitation), do: true
end
