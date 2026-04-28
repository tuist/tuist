defmodule TuistWeb.AcceptInvitationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "/auth/invitations/:token" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               live(conn, ~p"/auth/invitations/#{invitation.token}")
    end

    test "shows the accept form when the signed-in user matches the invitee", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, invitee)
      {:ok, _lv, html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert html =~ "You have been invited"
      assert html =~ "Accept invitation"
      assert html =~ "Decline"
    end

    test "accepts the invitation when the user clicks Accept", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, invitee)
      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      html = lv |> element("button", "Accept invitation") |> render_click()

      assert html =~ "Invitation accepted!"
      assert Accounts.organization_user?(invitee, organization)
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "declines the invitation when the user clicks Decline", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, invitee)
      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      html = lv |> element("button", "Decline") |> render_click()

      assert html =~ "Invitation rejected"
      refute Accounts.organization_user?(invitee, organization)
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "shows a wrong-account error when the session user doesn't match the invitee", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      _invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")
      other_user = AccountsFixtures.user_fixture(email: "someone-else@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          "invitee@example.com",
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, other_user)
      {:ok, _lv, html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert html =~ "Wrong account"
      assert html =~ "invitee@example.com"
      refute html =~ "Accept invitation"
    end

    test "shows a not-found message when the token is invalid", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/auth/invitations/invalid-token")

      assert html =~ "Invitation not found"
    end
  end
end
