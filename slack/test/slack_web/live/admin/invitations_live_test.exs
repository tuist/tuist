defmodule SlackWeb.Admin.InvitationsLiveTest do
  use SlackWeb.ConnCase, async: false

  alias Slack.Invitations

  @valid_reason "We use Tuist to speed up our CI builds and want to chat with other users."

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "authorization", "Basic " <> Base.encode64("admin:admin"))}
  end

  describe "authentication" do
    test "returns 401 without credentials" do
      conn = Phoenix.ConnTest.build_conn()
      conn = get(conn, ~p"/admin/invitations")
      assert conn.status == 401
    end

    test "lets requests through with the configured credentials", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/invitations")
      assert html =~ "Invitation requests"
    end
  end

  describe "listing and accepting" do
    test "shows an empty state when there are no invitations", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/invitations")
      assert html =~ "No invitation requests yet."
    end

    test "only shows confirmed invitations", %{conn: conn} do
      {:ok, _unconfirmed} =
        Invitations.request_invitation(
          %{"email" => "unconfirmed@tuist.dev", "reason" => @valid_reason, "code_of_conduct_accepted" => "true"},
          fn _ -> "https://example.test/confirm" end
        )

      {:ok, confirmed_request} =
        Invitations.request_invitation(
          %{"email" => "confirmed@tuist.dev", "reason" => @valid_reason, "code_of_conduct_accepted" => "true"},
          fn _ -> "https://example.test/confirm" end
        )

      {:ok, _confirmed} = Invitations.confirm_invitation(confirmed_request)

      {:ok, _view, html} = live(conn, ~p"/admin/invitations")
      assert html =~ "confirmed@tuist.dev"
      refute html =~ "unconfirmed@tuist.dev"
    end

    test "lists confirmed invitations and can mark one as accepted", %{conn: conn} do
      {:ok, request} =
        Invitations.request_invitation(
          %{"email" => "admin-flow@tuist.dev", "reason" => @valid_reason, "code_of_conduct_accepted" => "true"},
          fn _ -> "https://example.test/confirm" end
        )

      {:ok, invitation} = Invitations.confirm_invitation(request)

      {:ok, view, html} = live(conn, ~p"/admin/invitations")
      assert html =~ "admin-flow@tuist.dev"
      assert html =~ "pending"

      html =
        view
        |> element(~s(#invitation-#{invitation.id} [data-role="accept-invitation"]))
        |> render_click()

      assert html =~ "accepted"
      refute html =~ ~s(data-role="accept-invitation")

      assert %{status: :accepted} = Invitations.get_invitation!(invitation.id)
    end
  end
end
