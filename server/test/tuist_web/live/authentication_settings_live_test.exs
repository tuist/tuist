defmodule TuistWeb.AuthenticationSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.SCIM
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
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/authentication")
    assert html =~ "Authentication · #{account.name} · Tuist"
  end

  test "displays SSO and SCIM sections for organizations", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/authentication")
    assert html =~ "Single Sign-On"
    assert html =~ "Enable Single Sign-On"
    assert html =~ "SCIM provisioning"
    assert html =~ "/scim/v2"
  end

  test "raises NotFoundError for personal accounts", %{conn: conn, user: user} do
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, ~p"/#{user.account.name}/authentication")
    end
  end

  test "raises UnauthorizedError when user is not an admin", %{conn: conn} do
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    other_user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(other_user, organization)
    conn = log_in_user(conn, other_user)

    assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
      live(conn, ~p"/#{organization.account.name}/authentication")
    end
  end

  test "hides provider options when SSO is disabled", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/authentication")
    refute html =~ "SSO provider"
  end

  test "shows provider options when SSO is enabled via toggle", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

    html = render_hook(lv, "toggle_sso")

    assert html =~ "SSO provider"
  end

  describe "Google SSO" do
    test "disables save button when domain is empty", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

      render_hook(lv, "toggle_sso")
      html = render_hook(lv, "select_provider", %{"value" => ["google"]})

      assert html =~ "disabled"
    end

    test "shows error when user has no Google OAuth identity", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

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

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

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
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

      render_hook(lv, "toggle_sso")
      html = render_hook(lv, "select_provider", %{"value" => ["okta"]})

      assert html =~ "disabled"
    end

    test "configures Okta SSO with all fields", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["okta"]})

      html =
        lv
        |> form("#sso-form", %{
          "sso" => %{
            "okta_domain" => "company.okta.com",
            "oauth2_client_id" => "test_client_id",
            "oauth2_client_secret" => "test_client_secret"
          }
        })
        |> render_submit()

      refute html =~ "Failed to configure"
      assert html =~ "Enable Single Sign-On"
    end
  end

  describe "Custom OAuth2 SSO" do
    test "disables save button when required fields are empty", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

      render_hook(lv, "toggle_sso")
      html = render_hook(lv, "select_provider", %{"value" => ["oauth2"]})

      assert html =~ "disabled"
    end

    test "shows error when submitting invalid URLs", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["oauth2"]})

      html =
        lv
        |> form("#sso-form", %{
          "sso" => %{
            "oauth2_site" => "not-a-url",
            "oauth2_client_id" => "test_client_id",
            "oauth2_client_secret" => "test_client_secret",
            "oauth2_authorize_url" => "not-a-url",
            "oauth2_token_url" => "not-a-url",
            "oauth2_user_info_url" => "not-a-url"
          }
        })
        |> render_submit()

      assert html =~ "must be a valid URL"
    end
  end

  describe "SCIM provisioning" do
    test "shows the empty-state message when no tokens exist", %{conn: conn, account: account} do
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/authentication")
      assert html =~ "No SCIM tokens yet"
    end

    test "generates a token, reveals it in the modal, and lists it in the table", %{
      conn: conn,
      account: account,
      organization: org
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

      html = render_submit(lv, "generate_scim_token", %{"scim_token" => %{"name" => "okta"}})

      assert html =~ ~s(data-part="modal-message")
      assert html =~ ~s(data-part="title">)
      assert html =~ "Token created"
      assert html =~ ~s(data-part="subtitle">)
      assert html =~ "will not be shown again"
      assert html =~ "tuist_scim_"
      assert html =~ ~s(id="new-scim-token")
      document = Floki.parse_fragment!(html)
      plaintext_token = document |> Floki.find("#new-scim-token") |> Floki.text()
      assert Floki.attribute(document, "#copy-scim-token-button", "data-clipboard-value") == [plaintext_token]
      assert Floki.attribute(document, "#copy-scim-token-button", "type") == ["button"]
      assert html =~ ~s(aria-label="Revoke token")
      assert html =~ "icon-tabler-trash"
      refute html =~ "No SCIM tokens yet"

      [token] = SCIM.list_tokens(org)
      assert token.name == "okta"
      assert html =~ "okta"
    end

    test "rejects empty token name", %{conn: conn, account: account, organization: org} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

      html = render_submit(lv, "generate_scim_token", %{"scim_token" => %{"name" => "  "}})

      assert html =~ "Token name is required"
      assert SCIM.list_tokens(org) == []
    end

    test "dismissing the modal clears the revealed plaintext", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

      render_submit(lv, "generate_scim_token", %{"scim_token" => %{"name" => "okta"}})

      html = render_hook(lv, "dismiss_scim_token")
      refute html =~ "Token created"
      refute html =~ "tuist_scim_"
    end

    test "open_change reset clears any leftover plaintext", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/authentication")

      render_submit(lv, "generate_scim_token", %{"scim_token" => %{"name" => "okta"}})

      html = render_hook(lv, "scim_modal_open_change", %{"open" => false})
      refute html =~ "tuist_scim_"
    end

    test "revokes a token", %{conn: conn, account: account, organization: org} do
      {:ok, {token, _plaintext}} = SCIM.create_token(org, %{name: "to-revoke"})

      {:ok, lv, html} = live(conn, ~p"/#{account.name}/authentication")
      assert html =~ "to-revoke"

      html = render_hook(lv, "revoke_scim_token", %{"id" => token.id})
      refute html =~ "SCIM token revoked."
      refute html =~ "to-revoke"
      assert SCIM.list_tokens(org) == []
    end
  end
end
