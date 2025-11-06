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
    setup do
      # Store original value
      original_secrets = Tuist.Environment.secrets()
      on_exit(fn -> Tuist.Environment.put_application_secrets(original_secrets) end)
      :ok
    end

    test "user is auto-confirmed when skip_email_confirmation is enabled" do
      Tuist.Environment.put_application_secrets(%{"skip_email_confirmation" => "true"})

      assert Tuist.Environment.skip_email_confirmation?() == true

      {:ok, user} =
        Tuist.Accounts.create_user("skiptest@example.com", password: "StrongP@ssword!2024")

      assert user.confirmed_at != nil
      refute is_nil(user.confirmed_at)
    end

    test "user requires confirmation when skip_email_confirmation is disabled" do
      Tuist.Environment.put_application_secrets(%{"skip_email_confirmation" => "false"})

      assert Tuist.Environment.skip_email_confirmation?() == false

      {:ok, user} =
        Tuist.Accounts.create_user("nonskip@example.com", password: "StrongP@ssword!2025")

      assert user.confirmed_at == nil
    end

    test "user requires confirmation when skip_email_confirmation is not set" do
      Tuist.Environment.put_application_secrets(%{})

      assert Tuist.Environment.skip_email_confirmation?() == false

      {:ok, user} =
        Tuist.Accounts.create_user("default@example.com", password: "StrongP@ssword!2026")

      assert user.confirmed_at == nil
    end
  end
end
