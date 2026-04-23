defmodule TuistWeb.InvitationControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "POST /auth/invitations/:token/accept" do
    test "accepts and logs the invitee in when not signed in but a matching user exists", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "new-teammate@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = post(conn, ~p"/auth/invitations/#{invitation.token}/accept")

      assert redirected_to(conn) =~ ~r{^/}
      assert get_session(conn, :user_token)
      assert Accounts.organization_user?(invitee, organization)
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "accepts when the signed-in user matches the invitation", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn =
        conn
        |> log_in_user(invitee)
        |> post(~p"/auth/invitations/#{invitation.token}/accept")

      assert redirected_to(conn) =~ ~r{^/}
      assert Accounts.organization_user?(invitee, organization)
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "redirects to registration when no matching user exists", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          "nobody-yet@example.com",
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = post(conn, ~p"/auth/invitations/#{invitation.token}/accept")

      assert redirected_to(conn) == ~p"/users/register"
      refute get_session(conn, :user_token)
      # invitation must survive so the user can still accept after signing up
      assert {:ok, _} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "rejects when the signed-in user does not match the invitee_email", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      _invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")
      other_user = AccountsFixtures.user_fixture(email: "someone-else@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          "invitee@example.com",
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn =
        conn
        |> log_in_user(other_user)
        |> post(~p"/auth/invitations/#{invitation.token}/accept")

      assert redirected_to(conn) == ~p"/users/log_in"
      # invitation must survive so the original invitee can still accept
      assert {:ok, _} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "redirects to login when the token is invalid", %{conn: conn} do
      conn = post(conn, ~p"/auth/invitations/not-a-real-token/accept")

      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "POST /auth/invitations/:token/decline" do
    test "deletes the invitation", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = post(conn, ~p"/auth/invitations/#{invitation.token}/decline")

      assert redirected_to(conn) == ~p"/users/log_in"
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
      refute Accounts.organization_user?(invitee, organization)
    end

    test "redirects when the token is invalid", %{conn: conn} do
      conn = post(conn, ~p"/auth/invitations/not-a-real-token/decline")

      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end
end
