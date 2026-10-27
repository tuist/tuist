defmodule TuistWeb.UserConfirmationInstructionsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.UserToken
  alias Tuist.Environment
  alias Tuist.Repo

  defp confirm_token_count(user_id) do
    Repo.aggregate(
      from(t in UserToken, where: t.user_id == ^user_id and t.context == "confirm"),
      :count,
      :id
    )
  end

  describe "Confirmation instructions page" do
    test "renders the email form for anonymous visitors", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/confirm")

      assert html =~ "Confirm your email"
      assert html =~ "confirmation_instructions_form"
    end

    test "redirects to log in when email auth is disabled", %{conn: conn} do
      stub(Environment, :email_auth_enabled?, fn -> false end)

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/confirm")
      assert to == ~p"/users/log_in"
    end

    test "sends a confirmation link when submitting an unconfirmed email", %{conn: conn} do
      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
      user = user_fixture(confirmed_at: nil)

      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      lv
      |> form("#confirmation_instructions_form", user: %{email: user.email})
      |> render_submit()

      assert has_element?(lv, "#confirmation-instructions-success")
      assert confirm_token_count(user.id) == 1
    end

    test "does not reveal whether an unknown email exists", %{conn: conn} do
      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)

      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      lv
      |> form("#confirmation_instructions_form",
        user: %{email: "nobody-#{System.unique_integer([:positive])}@tuist.io"}
      )
      |> render_submit()

      assert has_element?(lv, "#confirmation-instructions-success")
    end

    test "offers a one-click resend using the email carried from a failed login", %{conn: conn} do
      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
      user = user_fixture(confirmed_at: nil)

      conn = init_test_session(conn, %{"unconfirmed_email" => user.email})
      {:ok, lv, html} = live(conn, ~p"/users/confirm")

      assert html =~ user.email
      refute has_element?(lv, "#confirmation_instructions_form")

      lv |> element("[phx-click='resend']") |> render_click()

      assert has_element?(lv, "#confirmation-instructions-success")
      assert confirm_token_count(user.id) == 1
    end
  end
end
