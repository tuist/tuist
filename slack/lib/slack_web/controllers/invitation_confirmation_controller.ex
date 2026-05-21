defmodule SlackWeb.InvitationConfirmationController do
  use SlackWeb, :controller

  alias Slack.Invitations

  def confirm(conn, %{"token" => token}) do
    case Invitations.get_invitation_by_token(token) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(SlackWeb.InvitationConfirmationHTML)
        |> render(:not_found)

      invitation ->
        case Invitations.confirm_invitation(invitation) do
          {:ok, _confirmed} ->
            conn
            |> put_view(SlackWeb.InvitationConfirmationHTML)
            |> render(:confirmed)

          {:error, _changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> put_view(SlackWeb.InvitationConfirmationHTML)
            |> render(:error)
        end
    end
  end
end
