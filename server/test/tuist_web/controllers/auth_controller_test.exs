defmodule TuistWeb.AuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures

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
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "dev-123456",
          okta_client_id: UUIDv7.generate(),
          okta_client_secret: UUIDv7.generate()
        )

      # When
      conn = get(conn, "/users/auth/okta?organization_id=#{organization.id}")

      # Then
      assert redirected_to(conn) =~ "https://dev-123456/oauth2/v1/authorize"
    end

    test "includes login_hint in Okta OAuth redirect when provided", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "dev-123456",
          okta_client_id: UUIDv7.generate(),
          okta_client_secret: UUIDv7.generate()
        )

      login_hint = "user@example.com"

      # When
      conn = get(conn, "/users/auth/okta?organization_id=#{organization.id}&login_hint=#{login_hint}")

      # Then
      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://dev-123456/oauth2/v1/authorize"
      assert redirect_url =~ "login_hint=user%40example.com"
    end

    test "redirects to home with error when organization not found", %{conn: conn} do
      # When
      conn = get(conn, "/users/auth/okta?organization_id=999")

      # Then
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed to authenticate with Okta."
    end

    test "redirects to home with error when organization not configured for Okta", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com"
        )

      # When
      conn = get(conn, "/users/auth/okta?organization_id=#{organization.id}")

      # Then
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed to authenticate with Okta."
    end
  end

  describe "GET /users/auth/okta/callback" do
    test "processes callback when organization is found and configured", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "dev-123456"
        )

      # When
      conn =
        conn
        |> init_test_session(%{okta_organization_id: organization.id})
        |> get("/users/auth/okta/callback")

      # Then
      assert conn.status == 302
    end

    test "redirects to home with error when organization not found in session", %{conn: conn} do
      # When
      conn = get(conn, "/users/auth/okta/callback")

      # Then
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed to authenticate with Okta."
    end

    test "redirects to home with error when organization not configured for Okta", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com"
        )

      # When
      conn =
        conn
        |> init_test_session(%{okta_organization_id: organization.id})
        |> get("/users/auth/okta/callback")

      # Then
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed to authenticate with Okta."
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
      assert redirected_to(conn) =~ "/#{user.account.name}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Successfully authenticated."
    end

    test "redirects to oauth_return_url when provided in token", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      return_url = "/some/return/path"
      token = Phoenix.Token.sign(TuistWeb.Endpoint, "signup_completion", %{user_id: user.id, oauth_return_url: return_url})

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
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Please try again."
    end

    test "redirects to login with error when token is expired", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      # Create an expired token (max_age is 300 seconds, so we simulate by using a very old timestamp)
      token = Phoenix.Token.sign(TuistWeb.Endpoint, "signup_completion", %{user_id: user.id, oauth_return_url: nil}, signed_at: System.system_time(:second) - 400)

      # When
      conn = get(conn, "/auth/complete-signup?token=#{token}")

      # Then
      assert redirected_to(conn) == "/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Please try again."
    end

    test "redirects to login with error when token is missing", %{conn: conn} do
      # When
      conn = get(conn, "/auth/complete-signup")

      # Then
      assert redirected_to(conn) == "/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Please try again."
    end

    test "redirects to login with error when user does not exist", %{conn: conn} do
      # Given
      non_existent_user_id = 999_999_999
      token = Phoenix.Token.sign(TuistWeb.Endpoint, "signup_completion", %{user_id: non_existent_user_id, oauth_return_url: nil})

      # When
      conn = get(conn, "/auth/complete-signup?token=#{token}")

      # Then
      assert redirected_to(conn) == "/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Please try again."
    end
  end
end
