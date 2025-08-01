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
end
