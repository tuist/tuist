defmodule TuistWeb.UserRegistrationLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Create an account"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = user_fixture(preload: [:account])

      result =
        conn
        |> log_in_user(user)
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/#{user.account.name}/projects")

      assert {:ok, _conn} = result
    end
  end

  describe "Registration with email confirmation" do
    test "trims whitespace from email and username before registration", %{conn: conn} do
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> true end)
      stub(Tuist.Environment, :skip_email_confirmation?, fn _ -> true end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      lv
      |> form("#login_form",
        user: %{email: "  trimtest@example.com  ", password: "StrongP@ssword!2024", username: "  trimuser  "}
      )
      |> render_submit()

      assert {:ok, user} = Tuist.Accounts.get_user_by_email("trimtest@example.com")
      assert user.email == "trimtest@example.com"
      assert user.account.name == "trimuser"
    end

    test "user is auto-confirmed when skip_email_confirmation is enabled" do
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> true end)
      stub(Tuist.Environment, :skip_email_confirmation?, fn _ -> true end)

      {:ok, user} =
        Tuist.Accounts.create_user("skiptest@example.com", password: "StrongP@ssword!2024")

      assert user.confirmed_at
    end

    test "user requires confirmation when skip_email_confirmation is disabled" do
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> false end)
      stub(Tuist.Environment, :skip_email_confirmation?, fn _ -> false end)

      {:ok, user} =
        Tuist.Accounts.create_user("nonskip@example.com", password: "StrongP@ssword!2025")

      assert user.confirmed_at == nil
    end

    test "user is auto-confirmed when skip_email_confirmation is not set and email not configured" do
      stub(Tuist.Environment, :mail_configured?, fn -> false end)
      stub(Tuist.Environment, :mail_configured?, fn _ -> false end)
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> true end)
      stub(Tuist.Environment, :skip_email_confirmation?, fn _ -> true end)

      {:ok, user} =
        Tuist.Accounts.create_user("default@example.com", password: "StrongP@ssword!2026")

      # When email is not configured, skip_email_confirmation defaults to true
      assert user.confirmed_at
    end

    test "user requires confirmation when email is configured and skip_email_confirmation not set" do
      stub(Tuist.Environment, :mail_configured?, fn -> true end)
      stub(Tuist.Environment, :mail_configured?, fn _ -> true end)
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> false end)
      stub(Tuist.Environment, :skip_email_confirmation?, fn _ -> false end)

      {:ok, user} =
        Tuist.Accounts.create_user("withmail@example.com", password: "StrongP@ssword!2027")

      # When email is configured and skip not explicitly set, default to false (require confirmation)
      assert user.confirmed_at == nil
    end
  end
end
