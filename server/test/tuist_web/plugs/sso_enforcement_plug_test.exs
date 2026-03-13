defmodule TuistWeb.Plugs.SSOEnforcementPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  describe "SSO enforcement" do
    test "redirects to Google SSO when org has Google SSO enforced and session auth provider does not match",
         %{conn: conn, user: user} do
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      Accounts.update_organization(organization, %{sso_enforced: true})

      conn = get(conn, "/#{organization.account.name}/projects")

      assert redirected_to(conn) == "/users/auth/google"
      assert get_session(conn, :oauth_return_to) == "/#{organization.account.name}/projects"
    end

    test "redirects to Okta SSO when org has Okta SSO enforced and session auth provider does not match",
         %{conn: conn, user: user} do
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "company.okta.com",
          okta_client_id: "client_id",
          okta_client_secret: "client_secret",
          preload: [:account]
        )

      Accounts.update_organization(organization, %{sso_enforced: true})

      conn = get(conn, "/#{organization.account.name}/projects")

      assert redirected_to(conn) == "/users/auth/okta?organization_id=#{organization.id}"
      assert get_session(conn, :oauth_return_to) == "/#{organization.account.name}/projects"
    end

    test "allows access when session auth provider matches org SSO provider",
         %{conn: conn, user: user} do
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      Accounts.update_organization(organization, %{sso_enforced: true})

      conn =
        conn
        |> init_test_session(%{auth_provider: :google})
        |> get("/#{organization.account.name}/projects")

      refute conn.halted
    end

    test "allows access when org has SSO but enforcement is disabled",
         %{conn: conn, user: user} do
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      conn = get(conn, "/#{organization.account.name}/projects")

      refute conn.halted
    end

    test "allows access for orgs without SSO configured",
         %{conn: conn, user: user} do
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          preload: [:account]
        )

      conn = get(conn, "/#{organization.account.name}/projects")

      refute conn.halted
    end
  end
end
