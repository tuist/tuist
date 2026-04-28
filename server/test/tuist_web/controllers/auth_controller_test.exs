defmodule TuistWeb.AuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.OAuth2.SSOClient
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias Ueberauth.Auth.Info

  describe "GET /auth/cli/:device_code" do
    test "redirects to log in when the user is not logged in", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"

      # When
      conn = get(conn, "/auth/cli/#{device_code}")

      # Then
      assert redirected_to(conn) == "/users/log_in"
    end

    test "redirects to the CLI success page when the user is logged in", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"
      user = AccountsFixtures.user_fixture()

      conn = log_in_user(conn, user)

      # When
      conn = get(conn, "/auth/device_codes/#{device_code}?type=cli")

      # Then
      assert redirected_to(conn) == "/auth/device_codes/#{device_code}/success?type=cli"
    end
  end

  describe "GET /auth/device_codes/:device_code" do
    test "redirects to log in when the user is not logged in", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"

      # When
      conn = get(conn, "/auth/device_codes/#{device_code}?type=cli")

      # Then
      assert redirected_to(conn) == "/users/log_in"
    end

    test "redirects to the CLI success page when the user is logged in", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"
      user = AccountsFixtures.user_fixture()

      conn = log_in_user(conn, user)

      # When
      conn = get(conn, "/auth/device_codes/#{device_code}?type=cli")

      # Then
      assert redirected_to(conn) == "/auth/device_codes/#{device_code}/success?type=cli"
    end

    test "redirects to the app success page when the user is logged in", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"
      user = AccountsFixtures.user_fixture()

      conn = log_in_user(conn, user)

      # When
      conn = get(conn, "/auth/device_codes/#{device_code}?type=app")

      # Then
      assert redirected_to(conn) == "/auth/device_codes/#{device_code}/success?type=app"
    end
  end

  describe "GET /users/auth/okta" do
    test "redirects to Okta OAuth when organization is found and configured", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "dev-123456",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate()
        )

      conn = get(conn, "/users/auth/okta?organization_id=#{organization.id}")

      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://dev-123456/oauth2/v1/authorize"
      assert redirect_url =~ "response_type=code"
      assert redirect_url =~ "scope=openid+email+profile"
      assert redirect_url =~ "client_id=#{organization.oauth2_client_id}"
      assert redirect_url =~ "redirect_uri="
      assert redirect_url =~ "state="
    end

    test "includes login_hint in Okta OAuth redirect when provided", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "dev-123456",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate()
        )

      login_hint = "user@example.com"

      conn = get(conn, "/users/auth/okta?organization_id=#{organization.id}&login_hint=#{login_hint}")

      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://dev-123456/oauth2/v1/authorize"
      assert redirect_url =~ "login_hint=user%40example.com"
    end

    test "raises unauthorized error when organization not found", %{conn: conn} do
      assert_error_sent 401, fn ->
        get(conn, "/users/auth/okta?organization_id=999")
      end
    end

    test "raises unauthorized error when organization not configured for Okta", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com"
        )

      assert_error_sent 401, fn ->
        get(conn, "/users/auth/okta?organization_id=#{organization.id}")
      end
    end
  end

  describe "GET /users/auth/okta/callback" do
    test "links the Okta identity to an existing user and logs them in", %{conn: conn} do
      existing_user = AccountsFixtures.user_fixture(email: "existing-okta@example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: existing_user,
          sso_provider: :okta,
          sso_organization_id: "dev-123456",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate()
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "okta-user-123", "email" => existing_user.email, "name" => "Existing User"}}
      end)

      conn =
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :okta
        })
        |> get("/users/auth/okta/callback?code=auth-code&state=expected-state")

      assert redirected_to(conn) =~ "/#{existing_user.account.name}"

      {:ok, oauth_identity} =
        Tuist.Accounts.get_oauth2_identity(:okta, "okta-user-123", "dev-123456")

      assert oauth_identity.user.id == existing_user.id
      assert oauth_identity.provider_organization_id == "dev-123456"
    end

    test "raises unauthorized error when organization is not configured for SSO", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com"
        )

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{sso_organization_id: organization.id, sso_state: "state"})
        |> get("/users/auth/okta/callback?state=state")
      end
    end

    test "raises unauthorized error when session is missing", %{conn: conn} do
      assert_error_sent 401, fn ->
        get(conn, "/users/auth/okta/callback")
      end
    end
  end

  describe "GET /users/auth/oauth2" do
    test "redirects to the custom OAuth2 provider when organization is found and configured", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
        )

      conn = get(conn, "/users/auth/oauth2?organization_id=#{organization.id}")

      assert redirected_to(conn) =~ "https://auth.example.com/oauth2/authorize"
    end

    test "includes login_hint in the custom OAuth2 redirect when provided", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
        )

      login_hint = "user@example.com"
      conn = get(conn, "/users/auth/oauth2?organization_id=#{organization.id}&login_hint=#{login_hint}")

      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://auth.example.com/oauth2/authorize"
      assert redirect_url =~ "login_hint=user%40example.com"
    end

    test "raises unauthorized error when organization is not configured for custom OAuth2", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com"
        )

      assert_error_sent 401, fn ->
        get(conn, "/users/auth/oauth2?organization_id=#{organization.id}")
      end
    end
  end

  describe "GET /users/auth/oauth2/callback" do
    test "links the custom OAuth2 identity to an existing user and logs them in", %{conn: conn} do
      existing_user = AccountsFixtures.user_fixture(email: "existing@example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: existing_user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "custom-oauth2-user-123", "email" => existing_user.email, "name" => "Existing User"}}
      end)

      conn =
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")

      assert redirected_to(conn) =~ "/#{existing_user.account.name}"

      {:ok, oauth_identity} =
        Tuist.Accounts.get_oauth2_identity(:oauth2, "custom-oauth2-user-123", "https://auth.example.com")

      assert oauth_identity.user.id == existing_user.id
      assert oauth_identity.provider_organization_id == "https://auth.example.com"
    end

    test "raises unauthorized error when the callback state does not match", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
        )

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=wrong-state")
      end
    end

    test "raises unauthorized error when the callback session is missing", %{conn: conn} do
      assert_error_sent 401, fn ->
        get(conn, "/users/auth/oauth2/callback?code=auth-code&state=expected-state")
      end
    end

    test "raises unauthorized error when the IdP redirects back with an error parameter", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
        )

      # The IdP must never reach the token endpoint when reporting an error,
      # so any get_token/get call here would indicate the precondition is broken.
      reject(&SSOClient.exchange_token/5)
      reject(&SSOClient.fetch_userinfo/2)

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get(
          "/users/auth/oauth2/callback?error=access_denied&error_description=User+denied+access&state=expected-state"
        )
      end
    end

    test "raises unauthorized error when the callback request has neither code nor error", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
        )

      reject(&SSOClient.exchange_token/5)
      reject(&SSOClient.fetch_userinfo/2)

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?state=expected-state")
      end
    end

    test "raises unauthorized error when the token exchange fails", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:error, :invalid_grant}
      end)

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")
      end
    end

    test "raises unauthorized error when user info does not include an email", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "custom-oauth2-user-123", "name" => "Missing Email User"}}
      end)

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")
      end
    end

    test "refuses to auto-link an existing user who is not a member of the SSO organization", %{conn: conn} do
      # An attacker org admin configures custom OAuth2 endpoints they control
      # and returns a victim's email from /userinfo. The login must be refused
      # because the victim does not belong to the attacker's organization.
      attacker = AccountsFixtures.user_fixture(email: "attacker@example.com")
      victim = AccountsFixtures.user_fixture(email: "victim@example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: attacker,
          sso_provider: :oauth2,
          sso_organization_id: "https://evil.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://evil.example.com/oauth2/authorize",
          oauth2_token_url: "https://evil.example.com/oauth2/token",
          oauth2_user_info_url: "https://evil.example.com/oauth2/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "spoofed-uid", "email" => victim.email, "name" => "Spoofed Victim"}}
      end)

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")
      end

      # The victim's account must remain unlinked from the attacker's IdP
      assert {:error, :not_found} =
               Tuist.Accounts.get_oauth2_identity(:oauth2, "spoofed-uid", "https://evil.example.com")
    end

    test "redirects to the invitation accept page when SSO finds a pending invitation",
         %{conn: conn} do
      # An admin invites a Tuist user whose account predates the org's SSO
      # configuration (e.g. originally signed up via Google). On their next
      # SSO login we don't auto-accept — we redirect them to the invitation
      # page so they can review and accept explicitly. Membership only
      # changes after the user clicks Accept.
      admin = AccountsFixtures.user_fixture(email: "inviter-via-sso@example.com")
      invitee = AccountsFixtures.user_fixture(email: "redirected-to-invite@example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://idp.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://idp.example.com/oauth2/authorize",
          oauth2_token_url: "https://idp.example.com/oauth2/token",
          oauth2_user_info_url: "https://idp.example.com/oauth2/userinfo"
        )

      {:ok, invitation} =
        Tuist.Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: admin, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "invitee-sub", "email" => invitee.email, "name" => "Invitee"}}
      end)

      conn =
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")

      assert redirected_to(conn) == "/auth/invitations/#{invitation.token}"

      # nothing has changed yet — no session, no membership, no oauth link,
      # invitation still pending. The user must explicitly click Accept.
      refute get_session(conn, :user_token)
      refute Tuist.Accounts.organization_user?(invitee, organization)

      assert {:error, :not_found} =
               Tuist.Accounts.get_oauth2_identity(:oauth2, "invitee-sub", "https://idp.example.com")

      assert %Tuist.Accounts.Invitation{} =
               Tuist.Accounts.get_invitation_by_invitee_email_and_organization(invitee.email, organization)
    end

    test "refuses cross-tenant account takeover when two custom OAuth2 IdPs return the same sub",
         %{conn: conn} do
      # Customer A has a legitimate user whose identity came from their IdP.
      # Their OIDC `sub` is some value, say "shared-sub".
      victim = AccountsFixtures.user_fixture(email: "victim@customer-a.example")

      _customer_a_org =
        AccountsFixtures.organization_fixture(
          creator: victim,
          sso_provider: :oauth2,
          sso_organization_id: "https://idp-a.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://idp-a.example.com/oauth2/authorize",
          oauth2_token_url: "https://idp-a.example.com/oauth2/token",
          oauth2_user_info_url: "https://idp-a.example.com/oauth2/userinfo"
        )

      {:ok, _victim_identity} =
        Tuist.Repo.insert(
          Oauth2Identity.create_changeset(%Oauth2Identity{}, %{
            provider: :oauth2,
            id_in_provider: "shared-sub",
            user_id: victim.id,
            provider_organization_id: "https://idp-a.example.com"
          })
        )

      # Customer B (the attacker) configures a different IdP they control.
      # Their IdP is going to return `sub = "shared-sub"` from /userinfo.
      attacker = AccountsFixtures.user_fixture(email: "attacker@customer-b.example")

      attacker_org =
        AccountsFixtures.organization_fixture(
          creator: attacker,
          sso_provider: :oauth2,
          sso_organization_id: "https://idp-b.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://idp-b.example.com/oauth2/authorize",
          oauth2_token_url: "https://idp-b.example.com/oauth2/token",
          oauth2_user_info_url: "https://idp-b.example.com/oauth2/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "shared-sub", "email" => "attacker@customer-b.example", "name" => "Attacker"}}
      end)

      # The callback must NOT log the attacker in as the victim. Because the
      # victim's identity row is scoped to customer A's issuer and the
      # attacker is authenticating against customer B's issuer, the lookup
      # for `(:oauth2, "shared-sub", "https://idp-b.example.com")` returns
      # :not_found — so we fall through to the email-based path and link
      # the attacker to THEIR OWN existing user (which they're allowed to,
      # since they're a member of the attacker org).
      conn =
        conn
        |> init_test_session(%{
          sso_organization_id: attacker_org.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")

      # Critical: attacker is NOT logged in as the victim.
      refute redirected_to(conn) =~ "/#{victim.account.name}"

      # The victim's identity row is still intact and still points at the victim.
      assert {:ok, victim_identity_after} =
               Tuist.Accounts.get_oauth2_identity(:oauth2, "shared-sub", "https://idp-a.example.com")

      assert victim_identity_after.user_id == victim.id

      # A new, separate identity row was created for the attacker against their
      # own issuer — proving the per-issuer uniqueness key allows both rows to
      # coexist with the same `sub`.
      assert {:ok, attacker_identity} =
               Tuist.Accounts.get_oauth2_identity(:oauth2, "shared-sub", "https://idp-b.example.com")

      assert attacker_identity.user_id == attacker.id
      refute attacker_identity.user_id == victim.id
    end

    test "raises unauthorized error when the user info request fails", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:error, {:userinfo_request_failed, 401, %{"error" => "unauthorized"}}}
      end)

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")
      end
    end
  end

  describe "callback/2 with OAuth" do
    test "links OAuth identity to existing user with same email and logs them in", %{conn: conn} do
      # Given: A user already exists with a specific email
      existing_user = AccountsFixtures.user_fixture(email: "existing@example.com")

      # Simulate OAuth callback with the same email but new OAuth identity
      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-uid-123",
        info: %Info{email: "existing@example.com"},
        extra: %{raw_info: %{user: %{"hd" => nil}}}
      }

      # When: OAuth callback is triggered (call controller directly to bypass Ueberauth middleware)
      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> TuistWeb.AuthController.callback(%{})

      # Then: User should be logged in (redirected to their dashboard, not choose-username)
      assert redirected_to(conn) =~ "/#{existing_user.account.name}"

      # And: OAuth identity should be linked to the existing user
      {:ok, oauth_identity} = Tuist.Accounts.get_oauth2_identity(:google, "google-uid-123")
      assert oauth_identity.user.id == existing_user.id
    end

    test "redirects to choose-username for new OAuth user without existing email", %{conn: conn} do
      # Simulate OAuth callback with a new email
      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-uid-456",
        info: %Info{email: "newuser@example.com"},
        extra: %{raw_info: %{user: %{"hd" => nil}}}
      }

      # When: OAuth callback is triggered (call controller directly to bypass Ueberauth middleware)
      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> TuistWeb.AuthController.callback(%{})

      # Then: Should redirect to choose-username
      assert redirected_to(conn) == "/users/choose-username"

      # And: Session should have pending OAuth signup data
      assert get_session(conn, :pending_oauth_signup)
    end

    test "logs in existing OAuth user directly", %{conn: conn} do
      # Given: A user with an existing OAuth identity
      user = AccountsFixtures.user_fixture(email: "oauth-user@example.com")

      # Create OAuth identity for the user
      {:ok, _oauth_identity} =
        Tuist.Repo.insert(
          Oauth2Identity.create_changeset(%Oauth2Identity{}, %{
            provider: :google,
            id_in_provider: "google-uid-existing",
            user_id: user.id
          })
        )

      # Simulate OAuth callback with the same OAuth identity
      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-uid-existing",
        info: %Info{email: "oauth-user@example.com"},
        extra: %{raw_info: %{user: %{"hd" => nil}}}
      }

      # When: OAuth callback is triggered (call controller directly to bypass Ueberauth middleware)
      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> TuistWeb.AuthController.callback(%{})

      # Then: User should be logged in directly
      assert redirected_to(conn) =~ "/#{user.account.name}"
    end
  end

  describe "GET /auth/complete-signup" do
    test "logs in user and redirects when token is valid", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      token = Phoenix.Token.sign(TuistWeb.Endpoint, "signup_completion", %{user_id: user.id, oauth_return_url: nil})

      # When
      conn = get(conn, "/auth/complete-signup?token=#{token}")

      # Then
      assert redirected_to(conn) == "/organizations/new"
    end

    test "redirects to oauth_return_url when provided in token", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      return_url = "/some/return/path"

      token =
        Phoenix.Token.sign(TuistWeb.Endpoint, "signup_completion", %{user_id: user.id, oauth_return_url: return_url})

      # When
      conn = get(conn, "/auth/complete-signup?token=#{token}")

      # Then
      assert redirected_to(conn) == return_url
    end

    test "redirects to login with error when token is invalid", %{conn: conn} do
      # When
      conn = get(conn, "/auth/complete-signup?token=invalid-token")

      # Then
      assert redirected_to(conn) == "/users/log_in"
    end

    test "redirects to login with error when token is expired", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      # Create an expired token (max_age is 300 seconds, so we simulate by using a very old timestamp)
      token =
        Phoenix.Token.sign(TuistWeb.Endpoint, "signup_completion", %{user_id: user.id, oauth_return_url: nil},
          signed_at: System.system_time(:second) - 400
        )

      # When
      conn = get(conn, "/auth/complete-signup?token=#{token}")

      # Then
      assert redirected_to(conn) == "/users/log_in"
    end

    test "redirects to login with error when token is missing", %{conn: conn} do
      # When
      conn = get(conn, "/auth/complete-signup")

      # Then
      assert redirected_to(conn) == "/users/log_in"
    end

    test "redirects to login with error when user does not exist", %{conn: conn} do
      # Given
      non_existent_user_id = 999_999_999

      token =
        Phoenix.Token.sign(TuistWeb.Endpoint, "signup_completion", %{user_id: non_existent_user_id, oauth_return_url: nil})

      # When
      conn = get(conn, "/auth/complete-signup?token=#{token}")

      # Then
      assert redirected_to(conn) == "/users/log_in"
    end
  end
end
