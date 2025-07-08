defmodule TuistWeb.UserOktaLoginLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  describe "Okta login page" do
    test "renders okta login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log_in/okta")

      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = user_fixture(preload: [:account])

      result =
        conn
        |> log_in_user(user)
        |> live(~p"/users/log_in/okta")
        |> follow_redirect(conn, ~p"/#{user.account.name}/projects")

      assert {:ok, _conn} = result
    end
  end

  describe "okta login" do
    test "redirects to okta auth when user has okta organization", %{conn: conn} do
      user = user_fixture()

      organization =
        organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "company.okta.com"
        )

      {:ok, lv, _html} = live(conn, ~p"/users/log_in/okta")

      lv
      |> form("#okta_login_form", user: %{email: user.email})
      |> render_submit()

      assert_redirect(lv, "/users/auth/okta?organization_id=#{organization.id}")
    end

    test "shows error when user not found", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in/okta")

      html =
        lv
        |> form("#okta_login_form", user: %{email: "nonexistent@example.com"})
        |> render_submit()

      assert html =~ "Logging in via Okta failed"
    end

    test "shows error when user has no okta organization", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log_in/okta")

      html =
        lv
        |> form("#okta_login_form", user: %{email: user.email})
        |> render_submit()

      assert html =~ "Logging in via Okta failed"
    end
  end
end
