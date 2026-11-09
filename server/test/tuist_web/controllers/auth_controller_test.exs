defmodule TuistWeb.AuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Accounts.Invitation
  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.Accounts.User
  alias Tuist.OAuth2.SSOClient
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Errors.UnauthorizedError
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

    test "redirects to the device code confirmation when the user is logged in", %{conn: conn} do
      conn = conn |> log_in_user(AccountsFixtures.user_fixture()) |> get("/auth/cli/AOKJ-1234")

      assert redirected_to(conn) == "/auth/device_codes/AOKJ-1234?type=cli"
    end
  end

  describe "device code approval with SSO enforcement" do
    setup do
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      :ok = Accounts.add_user_to_organization(user, organization, role: :user)
      %{user: user, organization: enforce_sso(organization, :google, "authctl-example.com")}
    end

    test "sends a session that did not sign in with the organization's provider to it first", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)

      conn = get(conn, "/auth/device_codes/SSO-1234?type=cli")

      assert redirected_to(conn) == "/users/auth/google"
      assert get_session(conn, :user_return_to) == "/auth/device_codes/SSO-1234?type=cli"
    end

    test "shows the confirmation to a session signed in with the provider", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_session(
          :user_token,
          Accounts.generate_user_session_token(user, %{
            auth_method: :google,
            provider_organization_id: "authctl-example.com"
          })
        )

      conn = get(conn, "/auth/device_codes/SSO-1234?type=cli")

      assert html_response(conn, 200) =~ "SSO-1234"
    end

    test "confirming records the SSO sign-in that approved the device code", %{conn: conn, user: user} do
      Accounts.create_device_code("SSO-9012")

      token =
        Accounts.generate_user_session_token(user, %{
          auth_method: :google,
          provider_organization_id: "authctl-example.com"
        })

      conn = conn |> init_test_session(%{}) |> put_session(:user_token, token)

      conn = post(conn, "/auth/device_codes/SSO-9012", %{"type" => "cli"})

      assert redirected_to(conn) == "/auth/device_codes/SSO-9012/success?type=cli"

      assert %{authenticated: true, auth_provider: "google", auth_provider_organization_id: "authctl-example.com"} =
               Accounts.get_device_code("SSO-9012")
    end

    test "confirming does not approve the device code for a session the route would refuse", %{
      conn: conn,
      user: user
    } do
      Accounts.create_device_code("SSO-5678")
      conn = conn |> log_in_user(user) |> post("/auth/device_codes/SSO-5678", %{"type" => "cli"})

      assert redirected_to(conn) == "/users/auth/google"
      refute Accounts.get_device_code("SSO-5678").authenticated
    end

    test "refuses a session that several SSO-enforcing organizations cannot all accept", %{
      conn: conn,
      user: user
    } do
      okta = AccountsFixtures.organization_fixture()
      :ok = Accounts.add_user_to_organization(user, okta, role: :user)
      enforce_sso(okta, :okta, "https://okta.authctl-example.com")

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(
          :user_token,
          Accounts.generate_user_session_token(user, %{
            auth_method: :google,
            provider_organization_id: "authctl-example.com"
          })
        )

      assert_error_sent 401, fn -> get(conn, "/auth/device_codes/SSO-1234?type=cli") end
    end
  end

  describe "device code approval consent" do
    test "visiting an approval link signed in does not hand the user's tokens to whoever polls the code", %{
      conn: conn
    } do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      # A signed-in user opens a link to a code chosen by someone else, and
      # renders every page the server sends them to.
      conn = get(conn, "/auth/device_codes/ATTACKER-CODE?type=cli")
      assert {:ok, _view, _html} = live(recycle(conn), "/auth/device_codes/ATTACKER-CODE/success?type=cli")

      poll = get(build_conn(), "/api/auth/device_code/ATTACKER-CODE")
      assert json_response(poll, :accepted) == %{}
    end

    test "the confirmation page posts the code back to approve it", %{conn: conn} do
      conn = conn |> log_in_user(AccountsFixtures.user_fixture()) |> get("/auth/device_codes/CLI-CODE?type=app")

      html = html_response(conn, 200)
      document = Floki.parse_document!(html)
      assert [form] = Floki.find(document, ~s(form[method="post"][action="/auth/device_codes/CLI-CODE?type=app"]))
      assert [_] = Floki.find(form, ~s(input[name="_csrf_token"]))
    end

    test "confirming approves the code once and the poll consumes it", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      conn = log_in_user(conn, user)
      Accounts.create_device_code("CLI-CODE")

      assert conn |> post("/auth/device_codes/CLI-CODE", %{"type" => "cli"}) |> redirected_to() ==
               "/auth/device_codes/CLI-CODE/success?type=cli"

      assert json_response(get(build_conn(), "/api/auth/device_code/CLI-CODE"), :ok)["token"] == user.token
      assert %{"message" => _} = json_response(get(build_conn(), "/api/auth/device_code/CLI-CODE"), :bad_request)
    end

    test "opening a used code's link again cannot approve it a second time", %{conn: conn} do
      conn = log_in_user(conn, AccountsFixtures.user_fixture())
      Accounts.create_device_code("CLI-CODE")
      post(conn, "/auth/device_codes/CLI-CODE", %{"type" => "cli"})
      assert json_response(get(build_conn(), "/api/auth/device_code/CLI-CODE"), :ok)

      assert html_response(get(conn, "/auth/device_codes/CLI-CODE?type=cli"), 410)
      assert html_response(post(conn, "/auth/device_codes/CLI-CODE", %{"type" => "cli"}), 410)
      assert json_response(get(build_conn(), "/api/auth/device_code/CLI-CODE"), :bad_request)
    end

    test "a code another user already approved cannot be approved again", %{conn: conn} do
      first = AccountsFixtures.user_fixture()
      Accounts.create_device_code("CLI-CODE")
      {:ok, _} = Accounts.authenticate_device_code("CLI-CODE", first)

      conn = log_in_user(conn, AccountsFixtures.user_fixture())

      assert html_response(get(conn, "/auth/device_codes/CLI-CODE?type=cli"), 410)
      assert html_response(post(conn, "/auth/device_codes/CLI-CODE", %{"type" => "cli"}), 410)
      assert Accounts.get_device_code("CLI-CODE").user_id == first.id
    end

    test "an expired code cannot be approved", %{conn: conn} do
      Accounts.create_device_code("OLD-CODE", created_at: DateTime.add(DateTime.utc_now(), -6, :minute))
      conn = log_in_user(conn, AccountsFixtures.user_fixture())

      assert html_response(get(conn, "/auth/device_codes/OLD-CODE?type=cli"), 410)
      assert html_response(post(conn, "/auth/device_codes/OLD-CODE", %{"type" => "cli"}), 410)
      refute Accounts.get_device_code("OLD-CODE").authenticated
    end
  end

  describe "standard device flow" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      {:ok, device_code} = Accounts.create_device_authorization()
      %{conn: log_in_user(conn, user), user: user, device_code: device_code}
    end

    test "the page asks for the code without showing one", %{conn: conn, device_code: device_code} do
      assert {:ok, _view, html} = live(conn, "/auth/device")

      document = Floki.parse_document!(html)
      assert [form] = Floki.find(document, ~s(form[method="post"][action="/auth/device"]))
      assert [_] = Floki.find(form, ~s(input[name="_csrf_token"]))
      assert [_] = Floki.find(form, ~s(input[type="hidden"][name="user_code"]))
      refute html =~ device_code.code
      refute html =~ device_code.user_code
    end

    test "typing the user code approves it once, however it is written", %{
      conn: conn,
      user: user,
      device_code: device_code
    } do
      typed = device_code.user_code |> Accounts.format_user_code() |> String.downcase()

      assert conn |> post("/auth/device", %{"user_code" => typed}) |> redirected_to() ==
               "/auth/device/success?type=cli"

      assert json_response(get(build_conn(), "/api/auth/device_code/#{device_code.code}"), :ok)["token"] == user.token
      assert json_response(get(build_conn(), "/api/auth/device_code/#{device_code.code}"), :bad_request)
      assert conn |> post("/auth/device", %{"user_code" => typed}) |> redirected_to() == "/auth/device"
    end

    test "a wrong or expired user code approves nothing", %{conn: conn, device_code: device_code} do
      conn = post(conn, "/auth/device", %{"user_code" => "BBBB-BBBB"})

      assert redirected_to(conn) == "/auth/device"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "incorrect or has expired"
      refute Accounts.get_device_code(device_code.code).authenticated

      device_code |> Ecto.Changeset.change(created_at: ~N[2020-01-01 00:00:00]) |> Repo.update!()
      post(conn, "/auth/device", %{"user_code" => device_code.user_code})
      refute Accounts.get_device_code(device_code.code).authenticated
    end

    test "the link-based flow cannot approve a code that has a user code", %{conn: conn, device_code: device_code} do
      assert html_response(get(conn, "/auth/device_codes/#{device_code.code}?type=cli"), 410)
      assert html_response(post(conn, "/auth/device_codes/#{device_code.code}", %{"type" => "cli"}), 410)
      refute Accounts.get_device_code(device_code.code).authenticated
    end

    test "limits how many codes one account can try", %{conn: conn, device_code: device_code} do
      for _ <- 1..10, do: post(conn, "/auth/device", %{"user_code" => "BBBB-BBBB"})

      conn = post(conn, "/auth/device", %{"user_code" => device_code.user_code})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
      refute Accounts.get_device_code(device_code.code).authenticated
    end

    test "approving needs the organization's single sign-on like the link-based flow", %{
      conn: conn,
      user: user,
      device_code: device_code
    } do
      organization = AccountsFixtures.organization_fixture()
      :ok = Accounts.add_user_to_organization(user, organization, role: :user)
      enforce_sso(organization, :google, "authctl-example.com")

      conn = post(conn, "/auth/device", %{"user_code" => device_code.user_code})

      assert redirected_to(conn) == "/users/auth/google"
      refute Accounts.get_device_code(device_code.code).authenticated
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

    test "shows the confirmation without approving the code when the user is logged in", %{conn: conn} do
      conn = conn |> log_in_user(AccountsFixtures.user_fixture()) |> get("/auth/device_codes/AOKJ-1234?type=cli")

      assert html_response(conn, 200) =~ "AOKJ-1234"
      refute Accounts.get_device_code("AOKJ-1234").authenticated
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

      login_hint = "user@authctl-example.com"

      conn = get(conn, "/users/auth/okta?organization_id=#{organization.id}&login_hint=#{login_hint}")

      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://dev-123456/oauth2/v1/authorize"
      assert redirect_url =~ "login_hint=user%40authctl-example.com"
    end

    test "raises unauthorized error when organization not found", %{conn: conn} do
      assert_error_sent 401, fn ->
        get(conn, "/users/auth/okta?organization_id=999")
      end
    end

    test "raises unauthorized error when organization_id is not a valid integer", %{conn: conn} do
      assert_error_sent 401, fn ->
        get(conn, "/users/auth/okta?organization_id=1%2C%60")
      end

      assert_error_sent 401, fn ->
        get(conn, "/users/auth/okta?organization_id=not-a-number")
      end
    end

    test "raises unauthorized error when organization not configured for Okta", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "authctl-example.com"
        )

      assert_error_sent 401, fn ->
        get(conn, "/users/auth/okta?organization_id=#{organization.id}")
      end
    end
  end

  describe "GET /users/auth/okta/callback" do
    test "links the Okta identity to an existing user and logs them in", %{conn: conn} do
      existing_user = AccountsFixtures.user_fixture(email: "existing-okta@authctl-example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: existing_user,
          sso_provider: :okta,
          sso_organization_id: "dev-123456",
          sso_login_domain: "authctl-example.com",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
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
        Accounts.get_oauth2_identity(:okta, "okta-user-123", "dev-123456")

      assert oauth_identity.user.id == existing_user.id
      assert oauth_identity.provider_organization_id == "dev-123456"
    end

    test "raises unauthorized error when organization is not configured for SSO", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "authctl-example.com"
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
          sso_organization_id: "https://auth.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.authctl-example.com/oauth2/userinfo"
        )

      conn = get(conn, "/users/auth/oauth2?organization_id=#{organization.id}")

      assert redirected_to(conn) =~ "https://auth.authctl-example.com/oauth2/authorize"
    end

    test "includes login_hint in the custom OAuth2 redirect when provided", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.authctl-example.com/oauth2/userinfo"
        )

      login_hint = "user@authctl-example.com"
      conn = get(conn, "/users/auth/oauth2?organization_id=#{organization.id}&login_hint=#{login_hint}")

      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://auth.authctl-example.com/oauth2/authorize"
      assert redirect_url =~ "login_hint=user%40authctl-example.com"
    end

    test "raises unauthorized error when organization is not configured for custom OAuth2", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "authctl-example.com"
        )

      assert_error_sent 401, fn ->
        get(conn, "/users/auth/oauth2?organization_id=#{organization.id}")
      end
    end
  end

  describe "GET /users/auth/oauth2/callback" do
    test "links the custom OAuth2 identity to an existing user and logs them in", %{conn: conn} do
      existing_user = AccountsFixtures.user_fixture(email: "existing@authctl-example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: existing_user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.authctl-example.com",
          sso_login_domain: "authctl-example.com",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.authctl-example.com/oauth2/userinfo"
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
        Accounts.get_oauth2_identity(:oauth2, "custom-oauth2-user-123", "https://auth.authctl-example.com")

      assert oauth_identity.user.id == existing_user.id
      assert oauth_identity.provider_organization_id == "https://auth.authctl-example.com"
    end

    test "raises unauthorized error when the callback state does not match", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.authctl-example.com/oauth2/userinfo"
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
          sso_organization_id: "https://auth.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.authctl-example.com/oauth2/userinfo"
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
          sso_organization_id: "https://auth.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.authctl-example.com/oauth2/userinfo"
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
          sso_organization_id: "https://auth.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.authctl-example.com/oauth2/userinfo"
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
          sso_organization_id: "https://auth.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.authctl-example.com/oauth2/userinfo"
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
      attacker = AccountsFixtures.user_fixture(email: "attacker@authctl-example.com")
      victim = AccountsFixtures.user_fixture(email: "victim@authctl-example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: attacker,
          sso_provider: :oauth2,
          sso_organization_id: "https://evil.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://evil.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://evil.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://evil.authctl-example.com/oauth2/userinfo"
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
               Accounts.get_oauth2_identity(:oauth2, "spoofed-uid", "https://evil.authctl-example.com")
    end

    test "links and enrolls an existing user without redirecting through a pending invitation", %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "customer-admin@authctl-customer.example")
      existing_user = AccountsFixtures.user_fixture(email: "member@authctl-customer.example")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.authctl-vendor.example",
          sso_login_domain: "authctl-customer.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          sso_automatic_enrollment: true,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.authctl-vendor.example/authorize",
          oauth2_token_url: "https://login.authctl-vendor.example/token",
          oauth2_user_info_url: "https://login.authctl-vendor.example/userinfo"
        )

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
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
      assert Accounts.belongs_to_organization?(existing_user, organization)

      assert {:ok, identity} =
               Accounts.get_oauth2_identity(
                 :oauth2,
                 "verified-domain-member",
                 "https://login.authctl-vendor.example"
               )

      assert identity.user_id == existing_user.id
    end

    test "rejects new-user onboarding for a former compatibility-mode organization", %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "legacy-admin@authctl-customer.example")
      new_user_email = "new-user@authctl-consultancy.example"

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.authctl-vendor.example",
          sso_automatic_enrollment: true,
          existing_sso_configuration: true,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.authctl-vendor.example/authorize",
          oauth2_token_url: "https://login.authctl-vendor.example/token",
          oauth2_user_info_url: "https://login.authctl-vendor.example/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "legacy-new-user", "email" => new_user_email, "name" => "New User"}}
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

      assert {:error, :not_found} = Accounts.get_user_by_email(new_user_email)
    end

    test "rejects a new user when automatic enrollment is disabled and no invitation exists", %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "customer-admin@authctl-customer.example")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.authctl-vendor.example",
          sso_login_domain: "authctl-customer.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          sso_automatic_enrollment: false,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.authctl-vendor.example/authorize",
          oauth2_token_url: "https://login.authctl-vendor.example/token",
          oauth2_user_info_url: "https://login.authctl-vendor.example/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "new-user", "email" => "new@authctl-customer.example", "name" => "New User"}}
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
      admin = AccountsFixtures.user_fixture(email: "identity-admin@authctl-customer.example")
      existing_user = AccountsFixtures.user_fixture(email: "identity-only@authctl-customer.example")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.authctl-vendor.example",
          sso_login_domain: "authctl-customer.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          sso_automatic_enrollment: false,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.authctl-vendor.example/authorize",
          oauth2_token_url: "https://login.authctl-vendor.example/token",
          oauth2_user_info_url: "https://login.authctl-vendor.example/userinfo"
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
      refute Accounts.belongs_to_organization?(existing_user, organization)

      assert {:ok, identity} =
               Accounts.get_oauth2_identity(
                 :oauth2,
                 "identity-only",
                 "https://login.authctl-vendor.example"
               )

      assert identity.user_id == existing_user.id
    end

    test "rejects an invited new user when the custom provider has no verified login domain",
         %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "invitation-admin@authctl-customer.example")
      invitee_email = "new-invitee@authctl-consultancy.example"

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.authctl-vendor.example",
          sso_automatic_enrollment: false,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.authctl-vendor.example/authorize",
          oauth2_token_url: "https://login.authctl-vendor.example/token",
          oauth2_user_info_url: "https://login.authctl-vendor.example/userinfo"
        )

      {:ok, _invitation} =
        Accounts.invite_user_to_organization(
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

      assert body =~ "verified a login email domain that matches your email"
      assert {:error, :not_found} = Accounts.get_user_by_email(invitee_email)
    end

    test "allows an invited new user from a verified domain without treating the invitation as identity proof",
         %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "verified-invitation-admin@authctl-customer.example")
      invitee_email = "new-invitee@authctl-customer.example"

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://login.authctl-vendor.example",
          sso_login_domain: "authctl-customer.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          sso_automatic_enrollment: false,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.authctl-vendor.example/authorize",
          oauth2_token_url: "https://login.authctl-vendor.example/token",
          oauth2_user_info_url: "https://login.authctl-vendor.example/userinfo"
        )

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
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
      admin = AccountsFixtures.user_fixture(email: "inviter-via-sso@authctl-example.com")
      invitee = AccountsFixtures.user_fixture(email: "redirected-to-invite@authctl-example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://idp.authctl-example.com",
          sso_automatic_enrollment: false,
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://idp.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://idp.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://idp.authctl-example.com/oauth2/userinfo"
        )

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
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
      refute Accounts.organization_user?(invitee, organization)

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "invitee-sub", "https://idp.authctl-example.com")

      assert %Invitation{} =
               Accounts.get_invitation_by_invitee_email_and_organization(invitee.email, organization)
    end

    test "does not redirect to the invitation accept page when the pending invitation expired",
         %{conn: conn} do
      admin = AccountsFixtures.user_fixture(email: "expired-sso-inviter@authctl-example.com")
      invitee = AccountsFixtures.user_fixture(email: "expired-sso-invitee@authctl-example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://idp.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://idp.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://idp.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://idp.authctl-example.com/oauth2/userinfo"
        )

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: admin, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      expired_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-(Invitation.validity_days() + 1) * 24 * 60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      Repo.update_all(
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
      admin = AccountsFixtures.user_fixture(email: "preserve-return-inviter@authctl-example.com")
      invitee = AccountsFixtures.user_fixture(email: "preserve-return-invitee@authctl-example.com")

      organization =
        AccountsFixtures.organization_fixture(
          creator: admin,
          sso_provider: :oauth2,
          sso_organization_id: "https://idp.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://idp.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://idp.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://idp.authctl-example.com/oauth2/userinfo"
        )

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
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
               Accounts.get_oauth2_identity(
                 :oauth2,
                 "invitee-sub-2",
                 "https://idp.authctl-example.com"
               )
    end

    test "refuses cross-tenant account takeover when two custom OAuth2 IdPs return the same sub",
         %{conn: conn} do
      # Customer A has a legitimate user whose identity came from their IdP.
      # Their OIDC `sub` is some value, say "shared-sub".
      victim = AccountsFixtures.user_fixture(email: "victim@authctl-customer-a.example")

      _customer_a_org =
        AccountsFixtures.organization_fixture(
          creator: victim,
          sso_provider: :oauth2,
          sso_organization_id: "https://idp-a.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://idp-a.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://idp-a.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://idp-a.authctl-example.com/oauth2/userinfo"
        )

      {:ok, _victim_identity} =
        Repo.insert(
          Oauth2Identity.create_changeset(%Oauth2Identity{}, %{
            provider: :oauth2,
            id_in_provider: "shared-sub",
            user_id: victim.id,
            provider_organization_id: "https://idp-a.authctl-example.com"
          })
        )

      # Customer B (the attacker) configures a different IdP they control.
      # Their IdP is going to return `sub = "shared-sub"` from /userinfo.
      attacker = AccountsFixtures.user_fixture(email: "attacker@authctl-customer-b.example")

      attacker_org =
        AccountsFixtures.organization_fixture(
          creator: attacker,
          sso_provider: :oauth2,
          sso_organization_id: "https://idp-b.authctl-example.com",
          sso_login_domain: "authctl-customer-b.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://idp-b.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://idp-b.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://idp-b.authctl-example.com/oauth2/userinfo"
        )

      expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
        {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
      end)

      expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
        {:ok, %{"sub" => "shared-sub", "email" => "attacker@authctl-customer-b.example", "name" => "Attacker"}}
      end)

      # The callback must NOT log the attacker in as the victim. Because the
      # victim's identity row is scoped to customer A's issuer and the
      # attacker is authenticating against customer B's issuer, the lookup
      # for `(:oauth2, "shared-sub", "https://idp-b.authctl-example.com")` returns
      # :not_found — so we fall through to the email-based path and link
      # the attacker to THEIR OWN existing user (which they're allowed to,
      # since their email is on the attacker org's verified domain).
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
               Accounts.get_oauth2_identity(:oauth2, "shared-sub", "https://idp-a.authctl-example.com")

      assert victim_identity_after.user_id == victim.id

      # A new, separate identity row was created for the attacker against their
      # own issuer — proving the per-issuer uniqueness key allows both rows to
      # coexist with the same `sub`.
      assert {:ok, attacker_identity} =
               Accounts.get_oauth2_identity(:oauth2, "shared-sub", "https://idp-b.authctl-example.com")

      assert attacker_identity.user_id == attacker.id
      refute attacker_identity.user_id == victim.id
    end

    test "raises unauthorized error when the user info request fails", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :oauth2,
          sso_organization_id: "https://auth.authctl-example.com",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://auth.authctl-example.com/oauth2/authorize",
          oauth2_token_url: "https://auth.authctl-example.com/oauth2/token",
          oauth2_user_info_url: "https://auth.authctl-example.com/oauth2/userinfo"
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

  describe "current SSO issuer provenance" do
    @tag :sso_boundary
    test "a linked member authenticated at another issuer must authenticate at the target issuer", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      [target, other] =
        for issuer <- ["https://idp-a.authctl-example.com", "https://idp-b.authctl-example.com"] do
          organization =
            custom_provider_organization(
              creator: user,
              sso_organization_id: issuer,
              existing_sso_configuration: true,
              oauth2_authorize_url: issuer <> "/authorize",
              oauth2_token_url: issuer <> "/token",
              oauth2_user_info_url: issuer <> "/userinfo"
            )

          AccountsFixtures.oauth2_identity_fixture(
            user: user,
            provider: :oauth2,
            id_in_provider: "linked-user",
            provider_organization_id: issuer
          )

          organization |> Ecto.Changeset.change(sso_enforced: true) |> Repo.update!()
        end

      stub_sso_userinfo("linked-user", user.email)
      conn = sso_callback(conn, other)
      assert Accounts.belongs_to_organization?(user, target)
      assert conn |> recycle() |> get(~p"/#{other.account.name}/projects") |> html_response(200)

      protected_path = ~p"/#{target.account.name}/projects"
      expected = ~p"/users/auth/oauth2?organization_id=#{target.id}"
      assert conn |> recycle() |> get(protected_path) |> redirected_to() == expected

      {:ok, view, _} = live(recycle(conn), ~p"/#{other.account.name}/projects")
      assert {:error, {:redirect, %{to: ^protected_path}}} = live_redirect(view, to: protected_path)
      assert conn |> recycle() |> get(protected_path) |> redirected_to() == expected

      stub_sso_userinfo("linked-user", user.email)
      correct_conn = sso_callback(build_conn(), target)
      assert {:ok, _, _} = live(recycle(correct_conn), protected_path)

      session = Accounts.get_user_session(get_session(correct_conn, :user_token))
      {:ok, factor} = Accounts.UserMFA.begin_enrollment(user, session)
      code = NimbleTOTP.verification_code(factor.secret, time: Tuist.Time.utc_now())
      {:ok, %{recovery_codes: [other_code, target_code | _]}} = Accounts.UserMFA.confirm_enrollment(user, session, code)

      for {organization, recovery} <- [{other, other_code}, {target, target_code}] do
        stub_sso_userinfo("linked-user", user.email)
        pending = sso_callback(build_conn(), organization)
        assert redirected_to(pending) == ~p"/users/mfa"
        refute get_session(pending, :user_token)
        verified = pending |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => recovery})

        if organization.id == target.id do
          assert {:ok, _, _} = live(recycle(verified), protected_path)
        else
          assert verified |> recycle() |> get(protected_path) |> redirected_to() == expected
          {:ok, view, _} = live(recycle(verified), ~p"/#{other.account.name}/projects")
          assert {:error, {:redirect, %{to: ^protected_path}}} = live_redirect(view, to: protected_path)
          assert verified |> recycle() |> get(protected_path) |> redirected_to() == expected
        end
      end
    end
  end

  describe "linking an existing account through a custom provider" do
    test "keeps linked members signing in after compatibility mode is retired", %{conn: conn} do
      member = AccountsFixtures.user_fixture(email: "linked@authctl-customer.example")

      organization =
        custom_provider_organization(
          creator: member,
          existing_sso_configuration: true,
          sso_automatic_enrollment: true
        )

      organization = organization |> Ecto.Changeset.change(sso_enforced: true) |> Repo.update!()

      Accounts.link_oauth_identity_to_user(member, %{
        provider: :oauth2,
        id_in_provider: "linked-member",
        provider_organization_id: organization.sso_organization_id
      })

      stub_sso_userinfo("linked-member", member.email)

      conn = sso_callback(conn, organization)
      assert get_session(conn, :user_token)
      assert get_session(conn, :auth_method) == :oauth2
      assert Accounts.belongs_to_organization?(member, organization)
      assert Accounts.sso_enforced_for_email?(member.email)
      refute Accounts.sso_enforced_for_email?("new@authctl-customer.example")
    end

    test "does not link a member by email while the login domain is unverified", %{conn: conn} do
      member = AccountsFixtures.user_fixture(email: "member@authctl-customer.example")
      organization = custom_provider_organization(creator: member)
      stub_sso_userinfo("unverified-member", member.email)

      conn = sso_callback(conn, organization)

      assert redirected_to(conn) == "/users/log_in"
      assert get_session(conn, :user_return_to) == "/users/auth/oauth2?organization_id=#{organization.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Log in to your Tuist account"
      refute get_session(conn, :user_token)

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "unverified-member", "https://login.authctl-vendor.example")
    end

    test "does not link a member whose email is outside the verified domain", %{conn: conn} do
      member = AccountsFixtures.user_fixture(email: "contractor@authctl-elsewhere.example")

      organization =
        custom_provider_organization(
          creator: member,
          sso_login_domain: "authctl-customer.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z]
        )

      stub_sso_userinfo("off-domain-member", member.email)

      conn = sso_callback(conn, organization)

      assert redirected_to(conn) == "/users/log_in"

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "off-domain-member", "https://login.authctl-vendor.example")
    end

    test "links an account the organization's SCIM provisioning created while the domain is unverified", %{
      conn: conn
    } do
      owner = AccountsFixtures.user_fixture(email: "owner@authctl-customer.example")
      organization = custom_provider_organization(creator: owner)
      {:ok, provisioned} = Tuist.SCIM.provision_user(organization, %{user_name: "provisioned@authctl-customer.example"})
      stub_sso_userinfo("provisioned-identity", provisioned.email)

      conn = sso_callback(conn, organization)

      assert redirected_to(conn) =~ "/#{provisioned.account.name}"

      assert {:ok, identity} =
               Accounts.get_oauth2_identity(:oauth2, "provisioned-identity", "https://login.authctl-vendor.example")

      assert identity.user_id == provisioned.id
    end

    test "does not link an account another organization's SCIM provisioning created", %{conn: conn} do
      owner = AccountsFixtures.user_fixture(email: "owner@authctl-customer.example")
      organization = custom_provider_organization(creator: owner)

      other_organization =
        AccountsFixtures.organization_fixture(
          creator: AccountsFixtures.user_fixture(email: "other-owner@authctl-mail.example")
        )

      {:ok, provisioned} = Tuist.SCIM.provision_user(other_organization, %{user_name: "shared@authctl-customer.example"})
      :ok = Accounts.add_user_to_organization(provisioned, organization, role: :user)
      stub_sso_userinfo("foreign-identity", provisioned.email)

      conn = sso_callback(conn, organization)

      assert redirected_to(conn) == "/users/log_in"

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "foreign-identity", "https://login.authctl-vendor.example")
    end

    test "requires existing members to sign in before linking an unverified provider", %{conn: conn} do
      member = AccountsFixtures.user_fixture(email: "legacy-member@authctl-customer.example")

      organization =
        custom_provider_organization(creator: member, existing_sso_configuration: true)

      stub_sso_userinfo("legacy-member", member.email)

      conn = sso_callback(conn, organization)

      assert redirected_to(conn) == "/users/log_in"

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "legacy-member", "https://login.authctl-vendor.example")
    end

    test "asks a signed-in member to confirm linking an identity with a different email", %{conn: conn} do
      member = AccountsFixtures.user_fixture(email: "personal@authctl-mail.example")
      organization = custom_provider_organization(creator: member, existing_sso_configuration: true)
      stub_sso_userinfo("work-identity", "person@authctl-customer.example")

      conn =
        sso_callback(conn, organization, %{
          user_token: Accounts.generate_user_session_token(member),
          user_return_to: "/#{member.account.name}/projects"
        })

      assert redirected_to(conn) == "/auth/sso/link"

      assert %{
               "user_id" => user_id,
               "organization_id" => organization_id,
               "provider" => "oauth2",
               "uid" => "work-identity",
               "provider_organization_id" => "https://login.authctl-vendor.example",
               "email" => "person@authctl-customer.example",
               "return_to" => return_to
             } = get_session(conn, :pending_sso_link)

      assert user_id == member.id
      assert organization_id == organization.id
      assert return_to == "/#{member.account.name}/projects"

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "work-identity", "https://login.authctl-vendor.example")
    end

    test "links a signed-in member rather than starting a signup that cannot finish while signed in", %{
      conn: conn
    } do
      member = AccountsFixtures.user_fixture(email: "personal@authctl-mail.example")

      organization =
        custom_provider_organization(
          creator: member,
          sso_login_domain: "authctl-customer.example",
          sso_login_domain_verification_token: "verification-token",
          sso_login_domain_verified_at: ~U[2026-07-24 12:00:00Z],
          sso_automatic_enrollment: true
        )

      stub_sso_userinfo("work-identity", "person@authctl-customer.example")

      conn =
        sso_callback(conn, organization, %{user_token: Accounts.generate_user_session_token(member)})

      assert redirected_to(conn) == "/auth/sso/link"
      assert get_session(conn, :pending_sso_link)["user_id"] == member.id
      refute get_session(conn, :pending_oauth_signup)
    end

    test "does not offer a signed-in user who was only invited a link", %{conn: conn} do
      owner = AccountsFixtures.user_fixture(email: "owner@authctl-customer.example")
      invitee = AccountsFixtures.user_fixture(email: "invitee@authctl-mail.example")
      organization = custom_provider_organization(creator: owner)

      {:ok, _invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: owner, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      stub_sso_userinfo("provider-chosen-identity", "someone@authctl-provider.example")

      assert_error_sent 401, fn ->
        sso_callback(conn, organization, %{user_token: Accounts.generate_user_session_token(invitee)})
      end

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "provider-chosen-identity", "https://login.authctl-vendor.example")
    end

    test "does not offer a signed-in user who does not belong to the organization a link", %{conn: conn} do
      owner = AccountsFixtures.user_fixture(email: "owner@authctl-customer.example")
      outsider = AccountsFixtures.user_fixture(email: "outsider@authctl-mail.example")
      organization = custom_provider_organization(creator: owner)
      stub_sso_userinfo("outsider-identity", outsider.email)

      assert_error_sent 401, fn ->
        sso_callback(conn, organization, %{user_token: Accounts.generate_user_session_token(outsider)})
      end
    end
  end

  describe "instance-trusted SSO callbacks" do
    setup do
      organization = custom_provider_organization(sso_login_domain: "authctl-example.com")

      other =
        custom_provider_organization(
          sso_login_domain: "authctl-example.com",
          sso_organization_id: "https://other.authctl-example.com"
        )

      stub(Tuist.Environment, :sso_require_login_domain_verification?, fn -> false end)
      %{organization: organization, other: other}
    end

    test "links an existing account through an instance-trusted provider", %{conn: conn, organization: organization} do
      user = AccountsFixtures.user_fixture(email: "person@authctl-example.com")
      stub_sso_userinfo("operator-sub", user.email)
      conn = sso_callback(conn, organization)
      assert get_session(conn, :user_token)

      assert {:ok, identity} =
               Accounts.get_oauth2_identity(:oauth2, "operator-sub", organization.sso_organization_id)

      assert identity.user_id == user.id
    end

    test "permits new-user signup when automatic enrollment is enabled", %{
      conn: conn,
      organization: organization
    } do
      {:ok, organization} =
        Accounts.update_sso_configuration(organization.id, :oauth2, %{sso_automatic_enrollment: true})

      stub_sso_userinfo("new-operator-sub", "new-person@authctl-example.com")
      conn = sso_callback(conn, organization)
      assert redirected_to(conn) == "/users/choose-username"
      assert get_session(conn, :pending_oauth_signup)
    end

    test "instance trust authorizes another organization's provider for its saved domain", %{
      conn: conn,
      other: other
    } do
      user = AccountsFixtures.user_fixture(email: "person@authctl-example.com")
      stub_sso_userinfo("other-sub", user.email)
      assert get_session(sso_callback(conn, other), :user_token)
      assert {:ok, identity} = Accounts.get_oauth2_identity(:oauth2, "other-sub", other.sso_organization_id)
      assert identity.user_id == user.id
    end

    test "never instance-trusts the operator email domain", %{conn: conn} do
      organization =
        custom_provider_organization(
          sso_login_domain: Tuist.Environment.operator_email_domain(),
          sso_organization_id: "https://idp.authctl-tenant.example"
        )

      operator = AccountsFixtures.user_fixture(email: "ops@#{organization.sso_login_domain}")

      assert {:error, changeset} =
               Accounts.update_sso_configuration(organization.id, :oauth2, %{sso_automatic_enrollment: true})

      assert {"requires a verified login email domain for this provider", _} = changeset.errors[:sso_automatic_enrollment]

      # A configuration saved before the operator domain was excluded.
      organization = organization |> Ecto.Changeset.change(sso_automatic_enrollment: true) |> Repo.update!()

      stub_sso_userinfo("new-sub", "x@#{organization.sso_login_domain}")
      assert_raise UnauthorizedError, fn -> sso_callback(conn, organization) end

      stub_sso_userinfo("operator-sub", operator.email)
      assert_raise UnauthorizedError, fn -> sso_callback(build_conn(), organization) end

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "operator-sub", organization.sso_organization_id)

      assert {:error, :not_found} = Accounts.sso_organization_for_user_email("x@#{organization.sso_login_domain}")

      # DNS proof still establishes trust for the operator domain.
      organization =
        organization |> Ecto.Changeset.change(sso_login_domain_verified_at: ~U[2026-01-01 00:00:00Z]) |> Repo.update!()

      assert Accounts.sso_login_domain_trust(organization) == :dns_verified
      stub_sso_userinfo("verified-sub", "y@#{organization.sso_login_domain}")
      assert redirected_to(sso_callback(build_conn(), organization)) == "/users/choose-username"
    end

    test "does not link email addresses outside the saved domain", %{conn: conn, organization: organization} do
      user = AccountsFixtures.user_fixture(email: "victim@authctl-outside.example")
      stub_sso_userinfo("outside-sub", user.email)
      assert_raise UnauthorizedError, fn -> sso_callback(conn, organization) end

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "outside-sub", organization.sso_organization_id)
    end
  end

  defp custom_provider_organization(attrs) do
    AccountsFixtures.organization_fixture(
      Keyword.merge(
        [
          sso_provider: :oauth2,
          sso_organization_id: "https://login.authctl-vendor.example",
          oauth2_client_id: UUIDv7.generate(),
          oauth2_client_secret: UUIDv7.generate(),
          oauth2_authorize_url: "https://login.authctl-vendor.example/authorize",
          oauth2_token_url: "https://login.authctl-vendor.example/token",
          oauth2_user_info_url: "https://login.authctl-vendor.example/userinfo"
        ],
        attrs
      )
    )
  end

  defp stub_sso_userinfo(sub, email) do
    expect(SSOClient, :exchange_token, fn _token_url, "auth-code", _redirect_uri, _client_id, _client_secret ->
      {:ok, %{"access_token" => "access-token", "token_type" => "Bearer", "scope" => "openid email profile"}}
    end)

    expect(SSOClient, :fetch_userinfo, fn _user_info_url, "access-token" ->
      {:ok, %{"sub" => sub, "email" => email, "name" => "Person"}}
    end)
  end

  defp github_auth(uid, email) do
    %Ueberauth.Auth{provider: :github, uid: uid, info: %Info{email: email}, extra: %{raw_info: %{user: %{}}}}
  end

  defp sso_callback(conn, organization, session \\ %{}) do
    conn
    |> init_test_session(
      Map.merge(
        %{sso_organization_id: organization.id, sso_state: "expected-state", sso_route_provider: :oauth2},
        session
      )
    )
    |> get("/users/auth/oauth2/callback?code=auth-code&state=expected-state")
  end

  describe "callback/2 with OAuth" do
    test "returns to the page that asked for the sign-in, not one from an abandoned SSO attempt", %{conn: conn} do
      user = AccountsFixtures.user_fixture(email: "member@authctl-example.com")

      organization =
        [creator: user, preload: [:account]]
        |> AccountsFixtures.organization_fixture()
        |> enforce_sso(:google, "authctl-example.com")

      {:ok, _} =
        Accounts.link_oauth_identity_to_user(user, %{
          provider: :google,
          id_in_provider: "google-member",
          provider_organization_id: "authctl-example.com"
        })

      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      [first, second] = for _ <- 1..2, do: AppBuildsFixtures.preview_fixture(project: project)
      previews_path = "/#{organization.account.name}/#{project.name}/previews"

      # A session that did not sign in with Google is sent there, and the
      # user leaves without finishing.
      conn = conn |> log_in_user(user) |> get("#{previews_path}/#{first.id}")
      assert redirected_to(conn) == "/users/auth/google"

      # The session expires before they open another preview.
      Repo.update_all(from(token in Accounts.UserToken, where: token.user_id == ^user.id),
        set: [last_active_at: DateTime.add(DateTime.utc_now(), -30, :day)]
      )

      conn = conn |> recycle() |> get("#{previews_path}/#{second.id}")
      assert redirected_to(conn) == "/users/log_in"

      conn =
        build_conn()
        |> init_test_session(get_session(conn))
        |> assign(:ueberauth_auth, %Ueberauth.Auth{
          provider: :google,
          uid: "google-member",
          info: %Info{email: user.email},
          extra: %{raw_info: %{user: %{"hd" => "authctl-example.com"}}}
        })
        |> TuistWeb.AuthController.callback(%{})

      assert redirected_to(conn) == "#{previews_path}/#{second.id}"
    end

    test "honors the legacy return path key only for provider sign-ins, below the current key", %{conn: conn} do
      user = AccountsFixtures.user_fixture(email: "legacy@authctl-example.com")

      {:ok, _} =
        Accounts.link_oauth_identity_to_user(user, %{provider: :google, id_in_provider: "google-legacy"})

      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-legacy",
        info: %Info{email: user.email},
        extra: %{raw_info: %{user: %{"hd" => nil}}}
      }

      callback = fn session ->
        conn
        |> init_test_session(session)
        |> assign(:ueberauth_auth, auth)
        |> TuistWeb.AuthController.callback(%{})
        |> redirected_to()
      end

      assert callback.(%{oauth_return_to: "/legacy"}) == "/legacy"
      assert callback.(%{oauth_return_to: "/legacy", user_return_to: "/current"}) == "/current"
      assert callback.(%{oauth_return_to: "/\\authctl-evil.example"}) == TuistWeb.Authentication.signed_in_path(user)

      # Only provider sign-ins ever honored the legacy key.
      password_conn =
        conn
        |> init_test_session(%{oauth_return_to: "/legacy"})
        |> TuistWeb.Authentication.log_in_user(user, %{auth_method: :password})

      assert redirected_to(password_conn) == TuistWeb.Authentication.signed_in_path(user)
    end

    test "links OAuth identity to existing user with same email and logs them in", %{conn: conn} do
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> false end)
      # Given: A user already exists with a specific email
      existing_user = AccountsFixtures.user_fixture(email: "existing@authctl-example.com")

      # Simulate OAuth callback with the same email but new OAuth identity
      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-uid-123",
        info: %Info{email: "existing@authctl-example.com"},
        extra: %{raw_info: %{user: %{"hd" => nil, "email_verified" => true}}}
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
      {:ok, oauth_identity} = Accounts.get_oauth2_identity(:google, "google-uid-123")
      assert oauth_identity.user.id == existing_user.id

      # And: The confirmed account keeps its password
      assert {:ok, _} =
               Accounts.get_user_by_email_and_password(
                 "existing@authctl-example.com",
                 AccountsFixtures.valid_user_password()
               )
    end

    test "a provider sign-in claims an unconfirmed account and voids the password it was registered with", %{
      conn: conn
    } do
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> false end)
      attacker_password = "attacker password!"
      {:ok, victim} = Accounts.create_user("victim@authctl-example.com", password: attacker_password, confirmed_at: nil)

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, github_auth("victim-github-uid", "victim@authctl-example.com"))
        |> TuistWeb.AuthController.callback(%{})

      assert {:ok, %{user: %{id: user_id}}} = Accounts.get_oauth2_identity(:github, "victim-github-uid")
      assert user_id == victim.id
      assert get_session(conn, :user_token)

      claimed = Accounts.get_user_by_id(victim.id)
      assert claimed.confirmed_at

      assert Accounts.get_user_by_email_and_password("victim@authctl-example.com", attacker_password) ==
               {:error, :invalid_email_or_password}
    end

    test "does not link an email-matched account while email confirmation is skipped", %{conn: conn} do
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> true end)
      attacker_password = "attacker password!"
      # Without email confirmation the account is confirmed at registration.
      {:ok, attacker_account} = Accounts.create_user("victim@authctl-example.com", password: attacker_password)
      assert attacker_account.confirmed_at

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, github_auth("victim-github-uid", "victim@authctl-example.com"))
        |> TuistWeb.AuthController.callback(%{})

      assert redirected_to(conn) == "/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already exists"
      refute get_session(conn, :user_token)
      assert Accounts.get_oauth2_identity(:github, "victim-github-uid") == {:error, :not_found}
    end

    test "links another provider while email confirmation is skipped once a provider proved the email", %{
      conn: conn
    } do
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> true end)

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: "owner-github-uid",
          info: %{email: "owner@authctl-example.com"}
        })

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, %Ueberauth.Auth{
          provider: :google,
          uid: "owner-google-uid",
          info: %Info{email: "owner@authctl-example.com"},
          extra: %{raw_info: %{user: %{"hd" => nil, "email_verified" => true}}}
        })
        |> TuistWeb.AuthController.callback(%{})

      assert redirected_to(conn) =~ "/#{user.account.name}"
      assert {:ok, %{user: %{id: user_id}}} = Accounts.get_oauth2_identity(:google, "owner-google-uid")
      assert user_id == user.id
    end

    test "refuses a Google email that Google has not verified", %{conn: conn} do
      existing_user = AccountsFixtures.user_fixture(email: "unverified-target@authctl-example.com")

      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-uid-unverified",
        info: %Info{email: existing_user.email},
        extra: %{raw_info: %{user: %{"hd" => nil, "email_verified" => false}}}
      }

      conn = conn |> init_test_session(%{}) |> assign(:ueberauth_auth, auth)

      assert_raise UnauthorizedError, fn -> TuistWeb.AuthController.callback(conn, %{}) end
      assert {:error, :not_found} = Accounts.get_oauth2_identity(:google, "google-uid-unverified")
    end

    test "confirms an unconfirmed account it links to and drops the password set before confirmation", %{conn: conn} do
      password = "StrongP@ssword!2035"

      squatted =
        AccountsFixtures.user_fixture(email: "squatted@authctl-example.com", password: password, confirmed_at: nil)

      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-uid-owner",
        info: %Info{email: squatted.email},
        extra: %{raw_info: %{user: %{"hd" => nil, "email_verified" => true}}}
      }

      conn |> init_test_session(%{}) |> assign(:ueberauth_auth, auth) |> TuistWeb.AuthController.callback(%{})

      assert {:ok, _} = Accounts.get_oauth2_identity(:google, "google-uid-owner")
      claimed = Accounts.get_user_by_id(squatted.id)
      assert claimed.confirmed_at
      refute User.valid_password?(claimed, password)
    end

    test "on a self-hosted instance, the first Google sign-in into an operator-domain account clears its unproven password",
         %{conn: conn} do
      # The account may predate mail being configured, when sign-ups were
      # confirmed automatically, so its password may belong to whoever
      # registered the owner's address first.
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> false end)
      stub(Tuist.Environment, :operator_email_domain_configured?, fn -> true end)
      stub(Tuist.Environment, :operator_email_domain, fn -> "authctl-example.com" end)
      password = "StrongP@ssword!2037"
      squatted = AccountsFixtures.user_fixture(email: "auto-confirmed@authctl-example.com", password: password)
      assert squatted.confirmed_at

      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-uid-auto-confirmed",
        info: %Info{email: squatted.email},
        extra: %{raw_info: %{user: %{"hd" => nil, "email_verified" => true}}}
      }

      conn |> init_test_session(%{}) |> assign(:ueberauth_auth, auth) |> TuistWeb.AuthController.callback(%{})

      claimed = Accounts.get_user_by_id(squatted.id)
      assert claimed.email_verified_at
      refute User.valid_password?(claimed, password)
    end

    test "a returning sign-in records mailbox proof only for the address the provider verified", %{conn: conn} do
      user = AccountsFixtures.user_fixture(email: "returning-#{System.unique_integer([:positive])}@authctl-example.com")
      AccountsFixtures.oauth2_identity_fixture(user: user, id_in_provider: "returning-uid", provider_organization_id: nil)

      sign_in = fn email ->
        auth = %Ueberauth.Auth{
          provider: :google,
          uid: "returning-uid",
          info: %Info{email: email},
          extra: %{raw_info: %{user: %{"hd" => nil, "email_verified" => true}}}
        }

        conn |> init_test_session(%{}) |> assign(:ueberauth_auth, auth) |> TuistWeb.AuthController.callback(%{})
      end

      sign_in.("someone-else@authctl-example.com")
      assert is_nil(Accounts.get_user_by_id(user.id).email_verified_at)

      sign_in.(user.email)
      assert Accounts.get_user_by_id(user.id).email_verified_at
    end

    test "redirects to choose-username for new OAuth user without existing email", %{conn: conn} do
      # Simulate OAuth callback with a new email
      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-uid-456",
        info: %Info{email: "newuser@authctl-example.com"},
        extra: %{raw_info: %{user: %{"hd" => nil, "email_verified" => true}}}
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
        info: %Info{email: "github-user@authctl-example.com"},
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
        info: %Info{email: "google-user@authctl-example.com"},
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
        info: %Info{email: "apple-user@authctl-example.com"},
        extra: %{raw_info: %{user: %{}}}
      }

      conn = conn |> init_test_session(%{}) |> assign(:ueberauth_auth, auth)

      assert_raise NotFoundError, fn ->
        TuistWeb.AuthController.callback(conn, %{})
      end
    end

    test "logs in existing OAuth user directly", %{conn: conn} do
      # Given: A user with an existing OAuth identity
      user = AccountsFixtures.user_fixture(email: "oauth-user@authctl-example.com")

      # Create OAuth identity for the user
      {:ok, _oauth_identity} =
        Repo.insert(
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
        info: %Info{email: "oauth-user@authctl-example.com"},
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

  defp enforce_sso(organization, provider, provider_organization_id) do
    # Enabling enforcement through `Accounts` also requires a verified login
    # email domain, which is not what these tests are about.
    organization
    |> Ecto.Changeset.change(sso_enforced: true, sso_provider: provider, sso_organization_id: provider_organization_id)
    |> Repo.update!()
  end
end
