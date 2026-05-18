defmodule TuistWeb.UserForgotPasswordLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.UserToken
  alias Tuist.Environment
  alias Tuist.Repo

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

    test "repeated submissions reuse the existing reset password token", %{conn: conn} do
      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)

      user = user_fixture()

      {:ok, first_live, _html} = live(conn, ~p"/users/reset_password")

      first_live
      |> form("#login_form", user: %{email: user.email})
      |> render_submit()

      assert has_element?(first_live, "#forgot-password-success")

      {:ok, second_live, _html} = live(build_conn(), ~p"/users/reset_password")

      second_live
      |> form("#login_form", user: %{email: user.email})
      |> render_submit()

      assert Repo.aggregate(
               from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"),
               :count,
               :id
             ) == 1
    end
  end
end
