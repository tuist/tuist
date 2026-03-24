defmodule TuistWeb.AuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias OAuth2.AccessToken
  alias Tuist.Accounts.Oauth2Identity
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

      assert redirected_to(conn) =~ "https://dev-123456/oauth2/v1/authorize"
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

      expect(OAuth2.Client, :get_token, fn _client, [code: "auth-code"] ->
        {:ok,
         %OAuth2.Client{
           token:
             AccessToken.new(%{
               "access_token" => "access-token",
               "token_type" => "Bearer",
               "scope" => "openid email profile"
             })
         }}
      end)

      expect(OAuth2.Client, :get, fn %OAuth2.Client{}, "https://dev-123456/oauth2/v1/userinfo" ->
        {:ok,
         %{
           status_code: 200,
           body: %{
             "sub" => "okta-user-123",
             "email" => existing_user.email,
             "name" => "Existing User"
           }
         }}
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
        Tuist.Accounts.get_oauth2_identity(:okta, "okta-user-123")

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

  describe "GET /users/auth/custom_oauth2" do
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

      conn = get(conn, "/users/auth/custom_oauth2?organization_id=#{organization.id}")

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
      conn = get(conn, "/users/auth/custom_oauth2?organization_id=#{organization.id}&login_hint=#{login_hint}")

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
        get(conn, "/users/auth/custom_oauth2?organization_id=#{organization.id}")
      end
    end
  end

  describe "GET /users/auth/custom_oauth2/callback" do
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

      expect(OAuth2.Client, :get_token, fn _client, [code: "auth-code"] ->
        {:ok,
         %OAuth2.Client{
           token:
             AccessToken.new(%{
               "access_token" => "access-token",
               "token_type" => "Bearer",
               "scope" => "openid email profile"
             })
         }}
      end)

      expect(OAuth2.Client, :get, fn %OAuth2.Client{}, "https://auth.example.com/oauth2/userinfo" ->
        {:ok,
         %{
           status_code: 200,
           body: %{
             "sub" => "custom-oauth2-user-123",
             "email" => existing_user.email,
             "name" => "Existing User"
           }
         }}
      end)

      conn =
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/custom_oauth2/callback?code=auth-code&state=expected-state")

      assert redirected_to(conn) =~ "/#{existing_user.account.name}"

      {:ok, oauth_identity} =
        Tuist.Accounts.get_oauth2_identity(:oauth2, "custom-oauth2-user-123")

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
        |> get("/users/auth/custom_oauth2/callback?code=auth-code&state=wrong-state")
      end
    end

    test "raises unauthorized error when the callback session is missing", %{conn: conn} do
      assert_error_sent 401, fn ->
        get(conn, "/users/auth/custom_oauth2/callback?code=auth-code&state=expected-state")
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

      expect(OAuth2.Client, :get_token, fn _client, [code: "auth-code"] ->
        {:error, :invalid_grant}
      end)

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/custom_oauth2/callback?code=auth-code&state=expected-state")
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

      expect(OAuth2.Client, :get_token, fn _client, [code: "auth-code"] ->
        {:ok,
         %OAuth2.Client{
           token:
             AccessToken.new(%{
               "access_token" => "access-token",
               "token_type" => "Bearer",
               "scope" => "openid email profile"
             })
         }}
      end)

      expect(OAuth2.Client, :get, fn %OAuth2.Client{}, "https://auth.example.com/oauth2/userinfo" ->
        {:ok,
         %{
           status_code: 200,
           body: %{
             "sub" => "custom-oauth2-user-123",
             "name" => "Missing Email User"
           }
         }}
      end)

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/custom_oauth2/callback?code=auth-code&state=expected-state")
      end
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

      expect(OAuth2.Client, :get_token, fn _client, [code: "auth-code"] ->
        {:ok,
         %OAuth2.Client{
           token:
             AccessToken.new(%{
               "access_token" => "access-token",
               "token_type" => "Bearer",
               "scope" => "openid email profile"
             })
         }}
      end)

      expect(OAuth2.Client, :get, fn %OAuth2.Client{}, "https://auth.example.com/oauth2/userinfo" ->
        {:ok, %{status_code: 401, body: %{"error" => "unauthorized"}}}
      end)

      assert_error_sent 401, fn ->
        conn
        |> init_test_session(%{
          sso_organization_id: organization.id,
          sso_state: "expected-state",
          sso_route_provider: :oauth2
        })
        |> get("/users/auth/custom_oauth2/callback?code=auth-code&state=expected-state")
      end
    end
  end
end
