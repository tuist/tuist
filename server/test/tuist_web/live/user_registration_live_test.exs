defmodule TuistWeb.UserRegistrationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.Workers.DeliverConfirmationInstructionsWorker
  alias TuistWeb.RateLimit.Registration
  alias TuistWeb.Turnstile

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Create an account"
    end

    test "redirects to log in when email auth is disabled", %{conn: conn} do
      stub(Tuist.Environment, :email_auth_enabled?, fn -> false end)

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/register")
      assert to == ~p"/users/log_in"
    end

    test "renders the Google button when Google is configured and enabled", %{conn: conn} do
      stub(Tuist.Environment, :google_oauth_configured?, fn -> true end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      assert has_element?(lv, "a[href='/users/auth/google']")
    end

    test "hides the Google button when Google auth is disabled", %{conn: conn} do
      stub(Tuist.Environment, :google_oauth_configured?, fn -> true end)
      stub(Tuist.Environment, :google_auth_enabled?, fn -> false end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      refute has_element?(lv, "a[href='/users/auth/google']")
    end

    test "hides the Okta button when Okta auth is disabled", %{conn: conn} do
      stub(Tuist.Environment, :okta_oauth_configured?, fn -> true end)
      stub(Tuist.Environment, :okta_auth_enabled?, fn -> false end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      refute has_element?(lv, "a[href='/users/auth/okta']")
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
    test "asks the user to reload when the session token is missing", %{conn: conn} do
      stub(Turnstile, :required?, fn -> true end)
      stub(Turnstile, :site_key, fn -> "site-key" end)
      stub(Registration, :hit, fn _session_token -> {:error, :missing_session} end)
      reject(&Turnstile.verify/2)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      html =
        lv
        |> form("#login_form", %{
          "cf-turnstile-response" => "",
          "user" => %{
            "email" => "missing-session@example.com",
            "password" => "StrongP@ssword!2028",
            "username" => "missingsession"
          }
        })
        |> render_submit()

      assert html =~ "Your session has expired"
      refute html =~ "Too many sign-up attempts"
    end

    test "disables the submit button until the Turnstile widget reports ready", %{conn: conn} do
      stub(Turnstile, :required?, fn -> true end)
      stub(Turnstile, :site_key, fn -> "site-key" end)

      {:ok, lv, html} = live(conn, ~p"/users/register")

      assert html =~ ~s(disabled)

      after_ready =
        render_hook(lv, "turnstile_state_changed", %{"id" => "email-signup-turnstile", "state" => "ready"})

      refute after_ready =~ ~s(name="user[email]"[^>]*disabled)
    end

    test "surfaces a distinct error when the Turnstile bundle cannot load", %{conn: conn} do
      stub(Turnstile, :required?, fn -> true end)
      stub(Turnstile, :site_key, fn -> "site-key" end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      html =
        render_hook(lv, "turnstile_state_changed", %{"id" => "email-signup-turnstile", "state" => "unavailable"})

      assert html =~ "The security check could not load"
    end

    test "does not create a user when the security check is rejected", %{conn: conn} do
      email = "rejected-security-check@example.com"

      stub(Turnstile, :required?, fn -> true end)
      stub(Turnstile, :site_key, fn -> "site-key" end)
      stub(Registration, :hit, fn _session_token -> {:allow, 2} end)
      stub(Turnstile, :verify, fn "invalid-token", [expected_action: "email_signup"] -> {:error, :rejected} end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      html =
        lv
        |> form("#login_form", %{
          "cf-turnstile-response" => "invalid-token",
          "user" => %{
            "email" => email,
            "password" => "StrongP@ssword!2028",
            "username" => "rejectedsecuritycheck"
          }
        })
        |> render_submit()

      assert html =~ "Please complete the security check and try again."
      assert {:error, :not_found} = Tuist.Accounts.get_user_by_email(email)
    end

    test "completes registration when confirmation email delivery fails", %{conn: conn} do
      stub(Tuist.Environment, :skip_email_confirmation?, fn -> false end)
      stub(Tuist.Environment, :skip_email_confirmation?, fn _ -> false end)

      stub(Tuist.Accounts.UserNotifier, :deliver_confirmation_instructions, fn _ ->
        raise "Mailgun is temporarily unavailable"
      end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      lv
      |> form("#login_form",
        user: %{
          email: "mail-provider-outage@example.com",
          password: "StrongP@ssword!2028",
          username: "mailprovideroutage"
        }
      )
      |> render_submit()

      assert has_element?(lv, "#signup-success")
      assert {:ok, user} = Tuist.Accounts.get_user_by_email("mail-provider-outage@example.com")

      assert_enqueued(
        worker: DeliverConfirmationInstructionsWorker,
        args: %{user_id: user.id}
      )
    end

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
