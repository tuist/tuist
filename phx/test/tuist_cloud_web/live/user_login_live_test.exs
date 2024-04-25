defmodule TuistCloudWeb.UserLoginLiveTest do
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import TuistCloud.AccountsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/v2/users/log_in")

      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/v2/users/log_in")
        |> follow_redirect(conn, "/v2")

      assert {:ok, _conn} = result
    end
  end

  describe "user login" do
    test "redirects if user login with valid credentials", %{conn: conn} do
      TuistCloud.Environment
      |> stub(:secret_key_password, fn -> "secret_key_password" end)

      password = "123456789abcd"
      user = user_fixture(password: password)

      {:ok, lv, _html} = live(conn, ~p"/v2/users/log_in")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: password, remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/v2"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/v2/users/log_in")

      form =
        form(lv, "#login_form",
          user: %{email: "test@email.com", password: "123456", remember_me: true}
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

      assert redirected_to(conn) == "/v2/users/log_in"
    end
  end
end
