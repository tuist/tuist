defmodule TuistWeb.SSOLoginLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "shows an actionable error instead of choosing an ambiguous organization", %{conn: conn} do
    for issuer <- ["first.okta.com", "second.okta.com"] do
      AccountsFixtures.organization_fixture(
        sso_provider: :okta,
        sso_organization_id: issuer,
        sso_login_domain: "example.com",
        oauth2_client_id: "client",
        oauth2_client_secret: "secret"
      )
    end

    stub(Environment, :sso_trust_unverified_login_domains?, fn -> true end)
    {:ok, lv, _} = live(conn, ~p"/users/log_in/sso")
    html = render_submit(lv, "submit", %{"user" => %{"email" => "new@example.com"}})
    assert html =~ "Multiple organizations use this login domain"
    assert html =~ "SSO sign-in link"
  end
end
