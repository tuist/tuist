defmodule TuistWeb.ChooseUsernameLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias TuistWeb.RateLimit.Registration
  alias TuistWeb.Turnstile

  describe "Choose username page" do
    test "redirects to login when session has no pending_oauth_signup", %{conn: conn} do
      result = live(conn, ~p"/users/choose-username")

      assert {:error, {:live_redirect, %{to: "/users/log_in"}}} = result
    end

    test "renders page with suggested username when pending_oauth_signup exists", %{conn: conn} do
      oauth_data = %{
        "provider" => "google",
        "uid" => "12345",
        "email" => "john.doe@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      {:ok, _lv, html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      assert html =~ "Choose a username"
      assert html =~ "john-doe"
    end

    test "suggests username based on email prefix", %{conn: conn} do
      oauth_data = %{
        "provider" => "github",
        "uid" => "67890",
        "email" => "test_user.name@company.org",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      {:ok, _lv, html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      # Underscores and periods are replaced with dashes
      assert html =~ "test-user-name"
    end

    test "redirects if user is already logged in", %{conn: conn} do
      user = user_fixture(preload: [:account])

      oauth_data = %{
        "provider" => "google",
        "uid" => "12345",
        "email" => "test@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      result =
        conn
        |> log_in_user(user)
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")
        |> follow_redirect(conn, ~p"/#{user.account.name}/projects")

      assert {:ok, _conn} = result
    end
  end

  describe "username selection" do
    test "asks the user to reload when the session token is missing", %{conn: conn} do
      email = "oauth-missing-session-#{System.unique_integer([:positive])}@example.com"

      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => email,
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      stub(Turnstile, :required?, fn -> true end)
      stub(Turnstile, :site_key, fn -> "site-key" end)
      stub(Registration, :hit, fn _session_token -> {:error, :missing_session} end)
      reject(&Turnstile.verify/2)

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      render_hook(lv, "turnstile_state_changed", %{"id" => "oauth-signup-turnstile", "state" => "ready"})

      html =
        lv
        |> form("#choose-username-form", %{"account" => %{"name" => "missingsession"}, "cf-turnstile-response" => ""})
        |> render_submit()

      assert html =~ "Your session has expired"
      assert {:error, :not_found} = Accounts.get_user_by_email(email)
    end

    test "parks the submit and shows a verifying message when the user clicks before the widget is ready",
         %{conn: conn} do
      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => "oauth-optimistic-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      stub(Turnstile, :required?, fn -> true end)
      stub(Turnstile, :site_key, fn -> "site-key" end)
      reject(&Registration.hit/1)
      reject(&Turnstile.verify/2)

      {:ok, lv, html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      # Button is not pre-disabled.
      refute html =~ ~s(<button[^>]*disabled)

      after_submit =
        lv
        |> form("#choose-username-form", %{"account" => %{"name" => "optimistic"}})
        |> render_submit()

      assert after_submit =~ "Verifying, one moment"
      refute after_submit =~ "Please complete the security check"
      assert {:error, :not_found} = Accounts.get_user_by_email(oauth_data["email"])
    end

    test "does not create an OAuth user when the security check is rejected", %{conn: conn} do
      email = "oauth-rejected-#{System.unique_integer([:positive])}@example.com"

      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => email,
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      stub(Turnstile, :required?, fn -> true end)
      stub(Turnstile, :site_key, fn -> "site-key" end)
      stub(Registration, :hit, fn _session_token -> {:allow, 2} end)
      stub(Turnstile, :verify, fn _token, [expected_action: "oauth_signup"] -> {:error, :rejected} end)

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      render_hook(lv, "turnstile_state_changed", %{"id" => "oauth-signup-turnstile", "state" => "ready"})

      html =
        lv
        |> form("#choose-username-form", %{"account" => %{"name" => "oauthrejected"}})
        |> render_submit()

      assert html =~ "Please complete the security check and try again."
      assert {:error, :not_found} = Accounts.get_user_by_email(email)
    end

    test "surfaces a retry message when the Turnstile challenge itself fails", %{conn: conn} do
      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => "oauth-widget-error-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      stub(Turnstile, :required?, fn -> true end)
      stub(Turnstile, :site_key, fn -> "site-key" end)

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      html =
        render_hook(lv, "turnstile_state_changed", %{"id" => "oauth-signup-turnstile", "state" => "error"})

      assert html =~ "The security check failed"
    end

    test "surfaces a message when create_user returns :internal_server_error", %{conn: conn} do
      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => "oauth-internal-error-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      stub(Accounts, :create_user_from_pending_oauth, fn _oauth_data, _username ->
        {:error, :internal_server_error}
      end)

      stub(Turnstile, :required?, fn -> false end)

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      html =
        lv
        |> form("#choose-username-form", %{"account" => %{"name" => "internalerror"}})
        |> render_submit()

      assert html =~ "Something went wrong"
    end

    test "surfaces a message when the changeset fails on a field other than :name", %{conn: conn} do
      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => "oauth-other-field-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      changeset =
        %Tuist.Accounts.User{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:email, "has already been taken")

      stub(Accounts, :create_user_from_pending_oauth, fn _oauth_data, _username -> {:error, changeset} end)
      stub(Turnstile, :required?, fn -> false end)

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      html =
        lv
        |> form("#choose-username-form", %{"account" => %{"name" => "otherfield"}})
        |> render_submit()

      # Not blank: falls back to the other field's message rather than rendering nothing.
      assert html =~ "has already been taken"
    end

    test "creates user and redirects to complete-signup on valid username", %{conn: conn} do
      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => "newuser-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      username = "testuser#{System.unique_integer([:positive])}"

      result =
        lv
        |> form("#choose-username-form", account: %{name: username})
        |> render_submit()

      assert {:error, {:redirect, %{to: redirect_path}}} = result
      assert redirect_path =~ "/auth/complete-signup?token="

      # Verify user was created
      {:ok, user} = Accounts.get_user_by_email(oauth_data["email"])
      assert user.account.name == username
    end

    test "trims whitespace from username before creating user", %{conn: conn} do
      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => "trimuser-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      username = "trimmeduser#{System.unique_integer([:positive])}"

      result =
        lv
        |> form("#choose-username-form", account: %{name: "  #{username}  "})
        |> render_submit()

      assert {:error, {:redirect, %{to: redirect_path}}} = result
      assert redirect_path =~ "/auth/complete-signup?token="

      # Verify user was created with trimmed username
      {:ok, user} = Accounts.get_user_by_email(oauth_data["email"])
      assert user.account.name == username
    end

    test "shows error when username is already taken", %{conn: conn} do
      # Create an existing user with a specific username
      existing_user = user_fixture()
      existing_username = existing_user.account.name

      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => "newuser-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      # Try to use the existing username
      html =
        lv
        |> form("#choose-username-form", account: %{name: existing_username})
        |> render_submit()

      assert html =~ "has already been taken"
    end

    test "redirects to log in when email is already taken", %{conn: conn} do
      existing_user = user_fixture()

      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => existing_user.email,
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      username = "newhandle#{System.unique_integer([:positive])}"

      result =
        lv
        |> form("#choose-username-form", account: %{name: username})
        |> render_submit()

      assert {:error, {:redirect, %{to: "/auth/cancel-pending-signup"}}} = result
    end

    test "shows error when username contains invalid characters", %{conn: conn} do
      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => "newuser-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => nil
      }

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      html =
        lv
        |> form("#choose-username-form", account: %{name: "invalid@username!"})
        |> render_submit()

      assert html =~ "must contain only alphanumeric characters"
    end

    test "preserves oauth_return_url in token", %{conn: conn} do
      oauth_data = %{
        "provider" => "google",
        "uid" => "unique-uid-#{System.unique_integer([:positive])}",
        "email" => "newuser-#{System.unique_integer([:positive])}@example.com",
        "provider_organization_id" => nil,
        "oauth_return_url" => "/some/return/path"
      }

      {:ok, lv, _html} =
        conn
        |> init_test_session(%{"pending_oauth_signup" => oauth_data})
        |> live(~p"/users/choose-username")

      username = "testuser#{System.unique_integer([:positive])}"

      result =
        lv
        |> form("#choose-username-form", account: %{name: username})
        |> render_submit()

      assert {:error, {:redirect, %{to: redirect_path}}} = result
      assert redirect_path =~ "/auth/complete-signup?token="

      # Extract and verify token contains the return URL
      [_, token] = String.split(redirect_path, "token=")
      {:ok, data} = Phoenix.Token.verify(TuistWeb.Endpoint, "signup_completion", token, max_age: 300)
      assert data.oauth_return_url == "/some/return/path"
    end
  end
end
