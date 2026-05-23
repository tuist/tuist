defmodule SlackWeb.Admin.InvitationsLive do
  @moduledoc """
  Admin LiveView listing invitation requests and offering a button to
  mark each pending invitation as accepted.
  """
  use SlackWeb, :live_view
  use Noora

  alias Slack.Invitations

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Invitations")
     |> load_invitations()}
  end

  @impl true
  def handle_event("accept", %{"id" => id}, socket) do
    invitation = Invitations.get_invitation!(id)

    case Invitations.accept_invitation(invitation) do
      {:ok, _accepted} ->
        {:noreply,
         socket
         |> load_invitations()
         |> put_flash(:info, "Invitation marked as accepted.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to accept invitation.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="admin-invitations">
      <div data-part="content">
        <header data-part="header">
          <h1>Invitation requests</h1>
          <span>{length(@invitations)} total</span>
        </header>

        <p :if={@invitations == []} id="admin-empty-state" data-part="empty">
          No invitation requests yet.
        </p>

        <ul :if={@invitations != []} id="admin-invitations-list" data-part="list">
          <li :for={invitation <- @invitations} id={"invitation-#{invitation.id}"} data-part="row">
            <div data-part="email">
              <span data-part="email-address">{invitation.email}</span>
              <span data-part="email-reason">{invitation.reason}</span>
              <span data-part="timestamp">
                requested {Calendar.strftime(invitation.inserted_at, "%Y-%m-%d %H:%M UTC")}
              </span>
            </div>

            <div data-part="actions">
              <.tag
                :if={invitation.status == :pending}
                id={"invitation-#{invitation.id}-status"}
                label="pending"
                type="secondary"
              />
              <.tag
                :if={invitation.status == :accepted}
                id={"invitation-#{invitation.id}-status"}
                label="accepted"
                type="primary"
              />
              <.button
                :if={invitation.status == :pending}
                type="button"
                variant="primary"
                size="small"
                label="Accept"
                phx-click="accept"
                phx-value-id={invitation.id}
                data-role="accept-invitation"
              />
            </div>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  defp load_invitations(socket) do
    assign(socket, :invitations, Invitations.list_invitations())
  end
end
