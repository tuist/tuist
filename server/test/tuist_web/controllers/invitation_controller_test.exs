defmodule TuistWeb.InvitationControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.OAuth2.SSOClient
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

  describe "end-to-end: SSO callback → invitation page → accept → SSO retry" do
    test "an existing user invited to an SSO org can complete the full flow", %{conn: conn} do
      # Setup: an admin runs an org that has Okta-style SSO. A user with a
      # pre-existing Tuist account (e.g. originally signed up via Google) is
      # invited.
      admin = AccountsFixtures.user_fixture(email: "e2e-inviter@example.com")
      invitee = AccountsFixtures.user_fixture(email: "e2e-invitee@example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://idp.e2e.example",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://idp.e2e.example/oauth2/authorize",
          oauth2_token_url: "https://idp.e2e.example/oauth2/token",
          oauth2_user_info_url: "https://idp.e2e.example/oauth2/userinfo"
        )

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: admin, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      # Leg 1: invitee runs `tuist auth login`, picks SSO. The IdP returns
      # their email. Server detects pending invitation and redirects to the
      # accept page; nothing has changed in the DB yet.
      stub(SSOClient, :exchange_token, fn _, _, _, _, _ ->
        {:ok, %{"access_token" => "tok", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      stub(SSOClient, :fetch_userinfo, fn _, "tok" ->
        {:ok, %{"sub" => "e2e-sub", "email" => invitee.email, "name" => "E2E"}}
      end)

      sso_conn =
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")

      assert redirected_to(sso_conn) == "/auth/invitations/#{invitation.token}"
      refute Accounts.organization_user?(invitee, organization)

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "e2e-sub", "https://idp.e2e.example")

      # Leg 2: invitee follows the redirect. The accept page renders even
      # though they're not logged in.
      live_conn = get(build_conn(), "/auth/invitations/#{invitation.token}")
      assert html_response(live_conn, 200) =~ "Accept invitation"

      # Leg 3: invitee clicks Accept. The controller logs them in (via the
      # invitation token), adds them to the org, and deletes the invitation.
      accept_conn = post(build_conn(), ~p"/auth/invitations/#{invitation.token}/accept")
      assert get_session(accept_conn, :user_token)
      assert Accounts.organization_user?(invitee, organization)
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)

      # Leg 4: invitee retries `tuist auth login` SSO. They're a member now,
      # so linking the Okta identity succeeds and they're logged in to the
      # dashboard.
      retry_conn =
        build_conn()
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")

      assert redirected_to(retry_conn) =~ ~r{^/}
      assert get_session(retry_conn, :user_token)

      assert {:ok, oauth_identity} =
               Accounts.get_oauth2_identity(:oauth2, "e2e-sub", "https://idp.e2e.example")

      assert oauth_identity.user.id == invitee.id
    end
  end
end
