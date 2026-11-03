defmodule TuistWeb.UserLoginLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Environment

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Log in"
    end

    test "does not render test user login button by default", %{conn: conn} do
      stub(Environment, :test_user_login_enabled?, fn -> false end)

      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      refute html =~ "Log in as test user"
    end

    test "renders test user login button when enabled", %{conn: conn} do
      stub(Environment, :test_user_login_enabled?, fn -> true end)

      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Log in as test user"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = user_fixture(preload: [:account])

      result =
        conn
        |> log_in_user(user)
        |> live(~p"/users/log_in")
        |> follow_redirect(conn, ~p"/#{user.account.name}/projects")

      assert {:ok, _conn} = result
    end

    test "renders SSO button if Okta is configured", %{conn: conn} do
      stub(Environment, :okta_oauth_configured?, fn -> true end)
      stub(Environment, :tuist_hosted?, fn -> false end)
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "SSO"
    end

    test "does not render SSO button if Okta is not configured and not tuist hosted", %{
      conn: conn
    } do
      stub(Environment, :okta_oauth_configured?, fn -> false end)
      stub(Environment, :tuist_hosted?, fn -> false end)
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      refute html =~ "SSO"
    end

    test "renders SSO button if tuist hosted even when Okta is not configured", %{conn: conn} do
      stub(Environment, :okta_oauth_configured?, fn -> false end)
      stub(Environment, :tuist_hosted?, fn -> true end)
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "SSO"
    end

    test "renders SSO button if an organization has SSO configured even when not tuist hosted", %{conn: conn} do
      stub(Environment, :okta_oauth_configured?, fn -> false end)
      stub(Environment, :tuist_hosted?, fn -> false end)
      stub(Tuist.Accounts, :sso_configured?, fn -> true end)
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "SSO"
    end

    test "renders GitHub button when GitHub OAuth is configured and GitHub auth is enabled", %{conn: conn} do
      stub(Environment, :github_oauth_configured?, fn -> true end)
      stub(Environment, :github_auth_enabled?, fn -> true end)
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "GitHub"
    end

    test "hides GitHub button when GitHub auth is disabled even if GitHub OAuth is configured", %{conn: conn} do
      stub(Environment, :github_oauth_configured?, fn -> true end)
      stub(Environment, :github_auth_enabled?, fn -> false end)
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      refute html =~ "GitHub"
    end

    test "renders email and password fields regardless of mail configuration", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      assert has_element?(lv, "input#email")
      assert has_element?(lv, "input#password")
    end

    test "hides the password form and sign-up link when email auth is disabled", %{conn: conn} do
      stub(Environment, :email_auth_enabled?, fn -> false end)

      {:ok, lv, html} = live(conn, ~p"/users/log_in")

      refute has_element?(lv, "#login_form")
      refute has_element?(lv, "input#password")
      refute html =~ "Sign up"
    end

    test "still renders the SSO button when email auth is disabled", %{conn: conn} do
      stub(Environment, :email_auth_enabled?, fn -> false end)
      stub(Environment, :okta_oauth_configured?, fn -> true end)
      stub(Environment, :tuist_hosted?, fn -> false end)

      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "SSO"
    end

    test "renders the Google button when Google is configured and enabled", %{conn: conn} do
      stub(Environment, :google_oauth_configured?, fn -> true end)

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      assert has_element?(lv, "a[href='/users/auth/google']")
      assert has_element?(lv, "#google-one-tap[phx-hook='GoogleOneTap']")
    end

    test "hides the Google button when Google auth is disabled", %{conn: conn} do
      stub(Environment, :google_oauth_configured?, fn -> true end)
      stub(Environment, :google_auth_enabled?, fn -> false end)

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      refute has_element?(lv, "a[href='/users/auth/google']")
      refute has_element?(lv, "#google-one-tap")
    end

    test "hides the Apple button when Apple auth is disabled", %{conn: conn} do
      stub(Environment, :apple_oauth_configured?, fn -> true end)
      stub(Environment, :apple_auth_enabled?, fn -> false end)

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      refute has_element?(lv, "a[href='/users/auth/apple']")
    end

    test "self-hosted login does not render a challenge", %{conn: conn} do
      stub(Environment, :tuist_hosted?, fn -> false end)
      stub(Environment, :turnstile_enabled?, fn -> true end)
      stub(Environment, :turnstile_site_key, fn -> "test-site-key" end)

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      assert has_element?(lv, "#login_form input#password")
      refute has_element?(lv, "#email-login-turnstile")
      refute has_element?(lv, "input[name='cf-turnstile-response']")
    end

    test "drops Okta from the SSO button when Okta auth is disabled", %{conn: conn} do
      stub(Environment, :okta_oauth_configured?, fn -> true end)
      stub(Environment, :okta_auth_enabled?, fn -> false end)
      stub(Environment, :tuist_hosted?, fn -> false end)
      stub(Tuist.Accounts, :sso_configured?, fn -> false end)

      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      refute html =~ "Log in with SSO"
    end
  end

  describe "user login" do
    test "the challenged form submits its token and a forged ready event cannot authorize login", %{conn: conn} do
      stub(Environment, :turnstile_required?, fn -> true end)
      stub(Environment, :turnstile_site_key, fn -> "test-site-key" end)
      stub(Environment, :turnstile_secret_key, fn -> "test-secret" end)
      stub(Environment, :app_url, fn -> "https://login.example.com" end)
      stub(FunWithFlags, :enabled?, fn :turnstile_kill_switch -> false end)
      stub(TuistWeb.RateLimit.Auth, :hit, fn _conn -> {:allow, 1} end)
      user = user_fixture(preload: [:account])

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      assert has_element?(
               lv,
               "#login_form #email-login-turnstile[phx-hook='Turnstile'][data-action='email_login'][data-sitekey='test-site-key'] input[name='cf-turnstile-response']"
             )

      render_hook(lv, "turnstile_state_changed", %{"id" => "email-login-turnstile", "state" => "ready"})

      login_form = form(lv, "#login_form", user: %{email: user.email, password: valid_user_password()})
      rejected = submit_form(login_form, conn)

      refute get_session(rejected, :user_token)
      assert redirected_to(rejected) == ~p"/users/log_in"

      assert Phoenix.Flash.get(rejected.assigns.flash, :error) ==
               "Please complete the security check and try again."

      stub(Req, :post, fn "https://challenges.cloudflare.com/turnstile/v0/siteverify", opts ->
        assert opts[:form] == %{secret: "test-secret", response: "login-token"}

        {:ok,
         %Req.Response{
           status: 200,
           body: %{"success" => true, "action" => "email_login", "hostname" => "login.example.com"}
         }}
      end)

      verified_form =
        form(lv, "#login_form", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()},
          "cf-turnstile-response" => "login-token"
        })

      accepted = submit_form(verified_form, conn)

      assert get_session(accepted, :user_token)
      assert redirected_to(accepted) == ~p"/#{user.account.name}/projects"
    end

    test "redirects if user login with valid credentials", %{conn: conn} do
      password = UUIDv7.generate()
      user = user_fixture(password: password, preload: [:account])

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: password, remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/#{user.account.name}/projects"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form", user: %{email: "test@email.com", password: "123456", remember_me: true})

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

      assert redirected_to(conn) == "/users/log_in"
    end
  end
end
