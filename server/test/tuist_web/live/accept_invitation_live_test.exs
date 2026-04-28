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

    test "redirects to post_invitation_return_to after Accept when set", %{conn: conn} do
      # When SSO bounced the user here it stashed the original return target
      # (e.g. the device-code URL) under :post_invitation_return_to so we
      # can resume that flow once they accept.
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "resume-invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      device_code_url = "/auth/device_codes/AOKJ-1234?type=cli"

      conn =
        conn
        |> log_in_user(invitee)
        |> Plug.Test.init_test_session(%{post_invitation_return_to: device_code_url})

      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert {:error, {:redirect, %{to: ^device_code_url}}} =
               lv |> element("button", "Accept invitation") |> render_click()

      assert Accounts.organization_user?(invitee, organization)
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

    test "ignores accept_invitation pushed from a not-found state", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/invalid-token")

      # Buttons aren't rendered in the not-found state, but a crafted client
      # could still push the event. The handler must reject it server-side
      # rather than crash on `nil` assigns.
      assert render_hook(lv, "accept_invitation", %{}) =~ "Invitation not found"
      assert render_hook(lv, "decline_invitation", %{}) =~ "Invitation not found"
    end

    test "ignores accept_invitation pushed from the wrong-account state", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      _invitee = AccountsFixtures.user_fixture(email: "real-invitee@example.com")
      other_user = AccountsFixtures.user_fixture(email: "other@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          "real-invitee@example.com",
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, other_user)
      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert render_hook(lv, "accept_invitation", %{}) =~ "Wrong account"
      assert render_hook(lv, "decline_invitation", %{}) =~ "Wrong account"

      # Neither user has been added to the org, and the invitation survives.
      refute Accounts.organization_user?(other_user, organization)
      assert {:ok, _} = Accounts.get_invitation_by_token(invitation.token)
    end
  end
end
