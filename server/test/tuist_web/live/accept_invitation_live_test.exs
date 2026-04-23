defmodule TuistWeb.AcceptInvitationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "/auth/invitations/:token" do
    test "shows accept form to an unauthenticated visitor whose email matches an existing user", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      {:ok, _lv, html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert html =~ "You have been invited"
      assert html =~ ~s(action="/auth/invitations/#{invitation.token}/accept")
      assert html =~ ~s(action="/auth/invitations/#{invitation.token}/decline")
    end

    test "prompts an unauthenticated visitor with no matching Tuist account to sign up", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          "nobody-yet@example.com",
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      {:ok, _lv, html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert html =~ "Create an account"
      refute html =~ ~s(action="/auth/invitations/#{invitation.token}/accept")
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
      refute html =~ ~s(action="/auth/invitations/#{invitation.token}/accept")
    end

    test "shows a not-found message when the token is invalid", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/auth/invitations/invalid-token")

      assert html =~ "Invitation not found"
    end
  end
end
