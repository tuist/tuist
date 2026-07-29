defmodule TuistWeb.AuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Accounts.Invitation
  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.OAuth2.SSOClient
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.NotFoundError
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

    test "links and enrolls an existing user without redirecting through a pending invitation", %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "customer-admin@customer.example")
      existing_user = AccountsFixtures.user_fixture(email: "member@customer.example")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.vendor.example",
          sso_login_domain: "customer.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          sso_automatic_enrollment: true,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        )

      {:ok, invitation} =
        Tuist.Accounts.invite_user_to_organization(
          existing_user.email,
          %{inviter: admin, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "verified-domain-member", "email" => existing_user.email, "name" => "Member"}}
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
      refute redirected_to(conn) =~ invitation.token
      assert Tuist.Accounts.belongs_to_organization?(existing_user, organization)

      assert {:ok, identity} =
               Tuist.Accounts.get_oauth2_identity(
                 :oauth2,
                 "verified-domain-member",
                 "https://login.vendor.example"
               )

      assert identity.user_id == existing_user.id
    end

    test "preserves new-user onboarding for a legacy custom-provider organization", %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "legacy-admin@customer.example")
      new_user_email = "new-user@consultancy.example"

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.vendor.example",
          sso_automatic_enrollment: true,
          sso_legacy_email_domain_fallback: true,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "legacy-new-user", "email" => new_user_email, "name" => "New User"}}
      end)

      conn =
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")

      assert redirected_to(conn) == "/users/choose-username"
      assert get_session(conn, :pending_oauth_signup)["email"] == new_user_email
    end

    test "rejects a new user when automatic enrollment is disabled and no invitation exists", %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "customer-admin@customer.example")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.vendor.example",
          sso_login_domain: "customer.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          sso_automatic_enrollment: false,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "new-user", "email" => "new@customer.example", "name" => "New User"}}
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

    test "links an existing user from a verified domain without automatically enrolling them", %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "identity-admin@customer.example")
      existing_user = AccountsFixtures.user_fixture(email: "identity-only@customer.example")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.vendor.example",
          sso_login_domain: "customer.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          sso_automatic_enrollment: false,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "identity-only", "email" => existing_user.email, "name" => "Existing User"}}
      end)

      conn =
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")

      assert get_session(conn, :user_token)
      refute Tuist.Accounts.belongs_to_organization?(existing_user, organization)

      assert {:ok, identity} =
               Tuist.Accounts.get_oauth2_identity(
                 :oauth2,
                 "identity-only",
                 "https://login.vendor.example"
               )

      assert identity.user_id == existing_user.id
    end

    test "rejects an invited new user when the custom provider has no verified login domain",
         %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "invitation-admin@customer.example")
      invitee_email = "new-invitee@consultancy.example"

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.vendor.example",
          sso_automatic_enrollment: false,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        )

      {:ok, _invitation} =
        Tuist.Accounts.invite_user_to_organization(
          invitee_email,
          %{inviter: admin, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "invited-new-user", "email" => invitee_email, "name" => "Invited User"}}
      end)

      assert {401, _headers, body} =
               assert_error_sent(401, fn ->
                 conn
                 |> init_test_session(%{
                   sso_organization_id: organization.id,
                   sso_state: "expected-state",
                   sso_route_provider: :oauth2
                 })
                 |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")
               end)

      assert body =~ "must verify a login email domain"
      assert {:error, :not_found} = Tuist.Accounts.get_user_by_email(invitee_email)
    end

    test "allows an invited new user from a verified domain without treating the invitation as identity proof",
         %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "verified-invitation-admin@customer.example")
      invitee_email = "new-invitee@customer.example"

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.vendor.example",
          sso_login_domain: "customer.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          sso_automatic_enrollment: false,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        )

      {:ok, invitation} =
        Tuist.Accounts.invite_user_to_organization(
          invitee_email,
          %{inviter: admin, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "verified-invited-new-user", "email" => invitee_email, "name" => "Invited User"}}
      end)

      conn =
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")

      assert redirected_to(conn) == "/users/choose-username"

      assert %{"invitation_token" => token} = get_session(conn, :pending_oauth_signup)
      assert token == invitation.token
    end

    test "redirects to the invitation accept page when SSO finds a pending invitation",
         %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "inviter-via-sso@example.com")
      invitee = AccountsFixtures.user_fixture(email: "redirected-to-invite@example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://idp.example.com",
          sso_automatic_enrollment: false,
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

      refute get_session(conn, :user_token)
      refute Tuist.Accounts.organization_user?(invitee, organization)

      assert {:error, :not_found} =
               Tuist.Accounts.get_oauth2_identity(:oauth2, "invitee-sub", "https://idp.example.com")

      assert %Invitation{} =
               Tuist.Accounts.get_invitation_by_invitee_email_and_organization(invitee.email, organization)
    end

    test "does not redirect to the invitation accept page when the pending invitation expired",
         %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "expired-sso-inviter@example.com")
      invitee = AccountsFixtures.user_fixture(email: "expired-sso-invitee@example.com")

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

      expired_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-(Invitation.validity_days() + 1) * 24 * 60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      Tuist.Repo.update_all(
        from(i in Invitation, where: i.id == ^invitation.id),
        set: [updated_at: expired_at]
      )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "invitee-sub", "email" => invitee.email, "name" => "Invitee"}}
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

    test "preserves the original return URL while redirecting an unlinked invitee",
         %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "preserve-return-inviter@example.com")
      invitee = AccountsFixtures.user_fixture(email: "preserve-return-invitee@example.com")

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
        {:ok, %{"sub" => "invitee-sub-2", "email" => invitee.email, "name" => "Invitee"}}
      end)

      device_code_url = "/auth/device_codes/AOKJ-1234?type=cli"

      conn =
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2,
          user_return_to: device_code_url
        })
        |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")

      assert redirected_to(conn) == "/auth/invitations/#{invitation.token}"
      assert get_session(conn, :post_invitation_return_to) == device_code_url
      assert get_session(conn, :post_invitation_user_id) == invitee.id
      assert get_session(conn, :post_invitation_token) == invitation.token
      refute get_session(conn, :user_token)

      conn =
        conn
        |> recycle()
        |> get("/auth/invitations/#{invitation.token}")

      assert redirected_to(conn) == "/users/log_in"

      conn =
        conn
        |> recycle()
        |> post("/users/log_in", %{
          "user" => %{
            "email" => invitee.email,
            "password" => AccountsFixtures.valid_user_password()
          }
        })

      assert redirected_to(conn) == "/auth/invitations/#{invitation.token}"
      assert get_session(conn, :post_invitation_return_to) == device_code_url
      assert get_session(conn, :post_invitation_user_id) == invitee.id
      assert get_session(conn, :post_invitation_token) == invitation.token

      assert {:error, :not_found} =
               Tuist.Accounts.get_oauth2_identity(
                 :oauth2,
                 "invitee-sub-2",
                 "https://idp.example.com"
               )
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

    test "rejects the GitHub callback when GitHub auth is disabled", %{conn: conn} do
      stub(Tuist.Environment, :github_auth_enabled?, fn -> false end)

      auth = %Ueberauth.Auth{
        provider: :github,
        uid: "github-uid-123",
        info: %Info{email: "github-user@example.com"},
        extra: %{raw_info: %{user: %{}}}
      }

      conn = conn |> init_test_session(%{}) |> assign(:ueberauth_auth, auth)

      assert_raise NotFoundError, fn ->
        TuistWeb.AuthController.callback(conn, %{})
      end
    end

    test "rejects the Google callback when Google auth is disabled", %{conn: conn} do
      stub(Tuist.Environment, :google_auth_enabled?, fn -> false end)

      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-uid-123",
        info: %Info{email: "google-user@example.com"},
        extra: %{raw_info: %{user: %{"hd" => nil}}}
      }

      conn = conn |> init_test_session(%{}) |> assign(:ueberauth_auth, auth)

      assert_raise NotFoundError, fn ->
        TuistWeb.AuthController.callback(conn, %{})
      end
    end

    test "rejects the Apple callback when Apple auth is disabled", %{conn: conn} do
      stub(Tuist.Environment, :apple_auth_enabled?, fn -> false end)

      auth = %Ueberauth.Auth{
        provider: :apple,
        uid: "apple-uid-123",
        info: %Info{email: "apple-user@example.com"},
        extra: %{raw_info: %{user: %{}}}
      }

      conn = conn |> init_test_session(%{}) |> assign(:ueberauth_auth, auth)

      assert_raise NotFoundError, fn ->
        TuistWeb.AuthController.callback(conn, %{})
      end
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

    test "logs in an invited SSO user and redirects to the invitation", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      invitation_token = "invitation-token"

      token =
        Phoenix.Token.sign(TuistWeb.Endpoint, "signup_completion", %{
          user_id: user.id,
          oauth_return_url: "/auth/invitations/#{invitation_token}"
        })

      conn =
        conn
        |> init_test_session(%{
          pending_oauth_signup: %{
            "provider" => "oauth2",
            "invitation_token" => invitation_token
          }
        })
        |> get("/auth/complete-signup?token=#{token}")

      assert redirected_to(conn) == "/auth/invitations/#{invitation_token}"
      assert get_session(conn, :user_token)
    end

    test "preserves the device-code return URL after an invited SSO user completes signup", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      invitation_token = "invitation-token"
      device_code_url = "/auth/device_codes/AOKJ-1234?type=cli"

      token =
        Phoenix.Token.sign(TuistWeb.Endpoint, "signup_completion", %{
          user_id: user.id,
          oauth_return_url: device_code_url
        })

      conn =
        conn
        |> init_test_session(%{
          pending_oauth_signup: %{
            "provider" => "oauth2",
            "invitation_token" => invitation_token
          }
        })
        |> get("/auth/complete-signup?token=#{token}")

      assert redirected_to(conn) == "/auth/invitations/#{invitation_token}"
      assert get_session(conn, :post_invitation_return_to) == device_code_url
      assert get_session(conn, :post_invitation_user_id) == user.id
      assert get_session(conn, :post_invitation_token) == invitation_token
      assert get_session(conn, :user_token)
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
