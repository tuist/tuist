defmodule TuistWeb.UserLoginLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = user_fixture(preload: [:account])

      result =
        conn
        |> log_in_user(user)
        |> live(~p"/users/log_in")
        |> follow_redirect(conn, ~p"/#{user.account.name}/projects")

      assert {:ok, _conn} = result
    end

    test "renders Okta button if Okta is configured", %{conn: conn} do
      stub(Tuist.Environment, :okta_oauth_configured?, fn -> true end)
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Okta"
    end

    test "does not render Okta button if Okta is not configured and not tuist hosted", %{
      conn: conn
    } do
      stub(Tuist.Environment, :okta_oauth_configured?, fn -> false end)
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      refute html =~ "Okta"
    end

    test "renders Okta button if tuist hosted even when Okta is not configured", %{conn: conn} do
      stub(Tuist.Environment, :okta_oauth_configured?, fn -> false end)
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Okta"
    end

    test "renders email and password fields regardless of mail configuration", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      assert has_element?(lv, "input#email")
      assert has_element?(lv, "input#password")
    end
  end

  describe "user login" do
    test "redirects if user login with valid credentials", %{conn: conn} do
      password = UUIDv7.generate()
      user = user_fixture(password: password, preload: [:account])

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: password, remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/#{user.account.name}/projects"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form", user: %{email: "test@email.com", password: "123456", remember_me: true})

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

      assert redirected_to(conn) == "/users/log_in"
    end
  end
end
