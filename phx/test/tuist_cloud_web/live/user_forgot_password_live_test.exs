defmodule TuistCloudWeb.UserForgotPasswordLiveTest do
  use TuistCloudWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TuistCloud.AccountsFixtures

  describe "Forgot password page" do
    test "renders email page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/v2/users/reset_password")

      assert html =~ "Forgot your password?"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/v2/users/reset_password")
        |> follow_redirect(conn, ~p"/v2")

      assert {:ok, _conn} = result
    end
  end
end
