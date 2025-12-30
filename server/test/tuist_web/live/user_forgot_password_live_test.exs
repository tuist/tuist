defmodule TuistWeb.UserForgotPasswordLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  describe "Forgot password page" do
    test "renders email page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/reset_password")

      assert html =~ "Forgot your password?"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = user_fixture(preload: [:account])

      result =
        conn
        |> log_in_user(user)
        |> live(~p"/users/reset_password")
        |> follow_redirect(conn, ~p"/#{user.account.name}/projects")

      assert {:ok, _conn} = result
    end
  end
end
