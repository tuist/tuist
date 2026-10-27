defmodule SlackWeb.InvitationConfirmationControllerTest do
  use SlackWeb.ConnCase, async: true

  alias Slack.Invitations

  @valid_reason "We use Tuist to speed up our CI builds and want to chat with other users."

  test "confirms an invitation with a valid token", %{conn: conn} do
    {:ok, invitation} =
      Invitations.request_invitation(
        %{"email" => "confirm@tuist.dev", "reason" => @valid_reason, "code_of_conduct_accepted" => "true"},
        fn _ -> "https://example.test/confirm" end
      )

    conn = get(conn, ~p"/invitations/confirm/#{invitation.confirmation_token}")

    assert response(conn, 200) =~ "email is confirmed"
    assert %{status: :pending} = Invitations.get_invitation!(invitation.id)
  end

  test "returns a helpful error for an unknown token", %{conn: conn} do
    conn = get(conn, ~p"/invitations/confirm/#{"does-not-exist"}")

    assert response(conn, 404) =~ "Invitation not found"
  end
end
