defmodule TuistWeb.SSOVerificationControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  describe "GET /sso/verify" do
    test "redirects to Google SSO when organization has Google SSO configured", %{
      conn: conn,
      user: user
    } do
      %{account: account} =
        organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      return_to = "/#{account.name}/projects"

      conn =
        get(conn, "/sso/verify?organization_id=#{organization.id}&return_to=#{return_to}")

      assert redirected_to(conn) == "/users/auth/google"
      assert get_session(conn, :oauth_return_to) == return_to
    end

    test "redirects to Okta SSO when organization has Okta SSO configured", %{
      conn: conn,
      user: user
    } do
      %{account: account} =
        organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "company.okta.com",
          okta_client_id: "client_id",
          okta_client_secret: "client_secret",
          preload: [:account]
        )

      return_to = "/#{account.name}/projects"

      conn =
        get(conn, "/sso/verify?organization_id=#{organization.id}&return_to=#{return_to}")

      assert redirected_to(conn) == "/users/auth/okta?organization_id=#{organization.id}"
      assert get_session(conn, :oauth_return_to) == return_to
    end

    test "redirects back when organization has no SSO configured", %{
      conn: conn,
      user: user
    } do
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          preload: [:account]
        )

      conn =
        get(conn, "/sso/verify?organization_id=#{organization.id}&return_to=/some/path")

      assert redirected_to(conn) == "/some/path"
    end

    test "redirects back when organization does not exist", %{conn: conn} do
      conn = get(conn, "/sso/verify?organization_id=999999&return_to=/some/path")
      assert redirected_to(conn) == "/some/path"
    end

    test "redirects to root when params are missing", %{conn: conn} do
      conn = get(conn, "/sso/verify")
      assert redirected_to(conn) == "/"
    end
  end
end
