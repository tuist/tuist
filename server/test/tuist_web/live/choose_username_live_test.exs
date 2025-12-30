defmodule TuistWeb.ChooseUsernameLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts

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
