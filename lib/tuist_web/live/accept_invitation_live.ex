defmodule TuistWeb.AcceptInvitationLive do
  use TuistWeb, :live_view
  alias Tuist.Accounts

  def mount(%{"token" => token}, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])

    case Accounts.get_invitation_by_token(token, user) do
      {:ok, invitation} ->
        organization = Accounts.get_organization_by_id(invitation.organization_id)
        account = Accounts.get_account_from_organization(organization)

        if connected?(socket) do
          Accounts.accept_invitation(%{
            invitation: invitation,
            invitee: user,
            organization: organization
          })
        end

        {:ok,
         socket
         |> assign(organization_name: account.name)}

      {:error, _} ->
        {:ok, socket |> assign(error: gettext("Invitation not found or expired"))}
    end
  end

  def render(assigns) do
    ~H"""
    <.stack class="auth-page" gap="4xl">
      <%= if assigns[:error] do %>
        <.auth_header
          title={gettext("Invitation not found or expired")}
          subtitle={
            gettext("We could not find the invitation you are trying to accept. Please, try again.")
          }
        />
      <% else %>
        <.auth_header
          title={gettext("Invitation accepted 🎉")}
          subtitle={
            gettext("You are now a part of the %{organization_name} organization",
              organization_name: @organization_name
            )
          }
        />
      <% end %>
      <div>
        <.legacy_button>
          <a href={~p"/"} class="color--text-primary">
            {gettext("Dashboard")}
          </a>
        </.legacy_button>
      </div>
    </.stack>
    """
  end
end
