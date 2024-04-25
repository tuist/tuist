defmodule TuistCloudWeb.UserRegistrationLiveTest do
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import TuistCloud.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/v2/users/register")

      assert html =~ "Create an account"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/v2/users/register")
        |> follow_redirect(conn, "/v2")

      assert {:ok, _conn} = result
    end
  end
end
