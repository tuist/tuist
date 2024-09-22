defmodule TuistWeb.UserLoginLiveTest do
  use TuistWeb.ConnCase
  use Tuist.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import Tuist.AccountsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/log_in")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end

    test "renders Okta button if Okta is configured", %{conn: conn} do
      Tuist.Environment
      |> stub(:okta_configured?, fn -> true end)

      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Sign in with Okta"
    end

    test "does not render Okta button if Okta is not configured", %{conn: conn} do
      Tuist.Environment
      |> stub(:okta_configured?, fn -> false end)

      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      refute html =~ "Sign in with Okta"
    end
  end

  describe "user login" do
    test "redirects if user login with valid credentials", %{conn: conn} do
      password = "123456789abcd"
      user = user_fixture(password: password)

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: password, remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form",
          user: %{email: "test@email.com", password: "123456", remember_me: true}
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

      assert redirected_to(conn) == "/users/log_in"
    end
  end
end
