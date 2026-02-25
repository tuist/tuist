defmodule TuistWeb.SSOSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "test-org",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account, organization: organization}
  end

  test "sets the right title", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/sso")
    assert html =~ "SSO · #{account.name} · Tuist"
  end

  test "displays SSO page for organizations", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/sso")
    assert html =~ "Single Sign-On"
    assert html =~ "Enable Single Sign-On"
  end

  test "raises NotFoundError for personal accounts", %{conn: conn, user: user} do
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, ~p"/#{user.account.name}/sso")
    end
  end

  test "raises UnauthorizedError when user is not authorized", %{conn: conn} do
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)
    conn = log_in_user(conn, user)

    assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
      live(conn, ~p"/#{organization.account.name}/sso")
    end
  end

  test "hides provider options when SSO is disabled", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/sso")
    refute html =~ "SSO provider"
  end

  test "shows provider options when SSO is enabled via toggle", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sso")

    html = render_hook(lv, "toggle_sso")

    assert html =~ "SSO provider"
  end

  describe "Google SSO" do
    test "disables save button when domain is empty", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sso")

      render_hook(lv, "toggle_sso")
      html = render_hook(lv, "select_provider", %{"value" => ["google"]})

      assert html =~ "disabled"
    end

    test "shows error when user has no Google OAuth identity", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sso")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["google"]})

      html =
        lv
        |> form("#sso-form", %{"sso" => %{"google_domain" => "example.com"}})
        |> render_submit()

      assert html =~ "You must be authenticated with Google"
    end

    test "configures Google SSO when user has matching Google identity", %{
      conn: conn,
      account: account,
      user: user
    } do
      Accounts.link_oauth_identity_to_user(user, %{
        provider: :google,
        id_in_provider: "google-uid-#{System.unique_integer([:positive])}",
        provider_organization_id: "example.com"
      })

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sso")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["google"]})

      html =
        lv
        |> form("#sso-form", %{"sso" => %{"google_domain" => "example.com"}})
        |> render_submit()

      refute html =~ "Failed to configure"
      assert html =~ "Enable Single Sign-On"
    end
  end

  describe "Okta SSO" do
    test "disables save button when required fields are empty", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sso")

      render_hook(lv, "toggle_sso")
      html = render_hook(lv, "select_provider", %{"value" => ["okta"]})

      assert html =~ "disabled"
    end

    test "disables save button when client secret is missing for new configuration", %{
      conn: conn,
      account: account
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sso")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["okta"]})

      html =
        render_hook(lv, "validate_sso", %{
          "sso" => %{
            "okta_domain" => "company.okta.com",
            "okta_client_id" => "test_client_id",
            "okta_client_secret" => ""
          }
        })

      assert html =~ "disabled"
    end

    test "configures Okta SSO with all fields", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sso")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["okta"]})

      html =
        lv
        |> form("#sso-form", %{
          "sso" => %{
            "okta_domain" => "company.okta.com",
            "okta_client_id" => "test_client_id",
            "okta_client_secret" => "test_client_secret"
          }
        })
        |> render_submit()

      refute html =~ "Failed to configure"
      assert html =~ "Enable Single Sign-On"
    end

    test "displays Okta setup instructions when okta is selected", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sso")

      render_hook(lv, "toggle_sso")
      html = render_hook(lv, "select_provider", %{"value" => ["okta"]})

      assert html =~ "Create App Integration"
      assert html =~ "/users/auth/okta/callback"
    end
  end

  describe "disable SSO" do
    test "disables Google SSO", %{conn: conn, user: user} do
      %{account: google_account} =
        AccountsFixtures.organization_fixture(
          name: "google-sso-org",
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      {:ok, lv, _html} = live(conn, ~p"/#{google_account.name}/sso")

      render_hook(lv, "toggle_sso")

      html =
        lv
        |> form("#sso-form")
        |> render_submit()

      refute html =~ "error"
      assert html =~ "Enable Single Sign-On"
    end

    test "disables Okta SSO", %{conn: conn, user: user} do
      %{account: okta_account} =
        AccountsFixtures.organization_fixture(
          name: "okta-sso-org",
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "company.okta.com",
          okta_client_id: "test_client_id",
          okta_client_secret: "test_secret",
          preload: [:account]
        )

      {:ok, lv, _html} = live(conn, ~p"/#{okta_account.name}/sso")

      render_hook(lv, "toggle_sso")

      html =
        lv
        |> form("#sso-form")
        |> render_submit()

      refute html =~ "error"
      assert html =~ "Enable Single Sign-On"
    end
  end
end
