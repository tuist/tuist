defmodule TuistWeb.AuthenticationSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Accounts.SSOLoginDomainVerification
  alias Tuist.Environment
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
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/authentication")
    assert html =~ "Authentication · #{account.name} · Tuist"
  end

  test "displays SSO and SCIM sections for organizations", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/authentication")
    assert html =~ "Single Sign-On"
    assert html =~ "Enable Single Sign-On"
    assert html =~ "SCIM provisioning"
    assert html =~ "/scim/v2"
  end

  test "raises NotFoundError for personal accounts", %{conn: conn, user: user} do
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, ~p"/#{user.account.name}/settings/authentication")
    end
  end

  test "raises UnauthorizedError when user is not an admin", %{conn: conn} do
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    other_user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(other_user, organization)
    conn = log_in_user(conn, other_user)

    assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
      live(conn, ~p"/#{organization.account.name}/settings/authentication")
    end
  end

  test "hides provider options when SSO is disabled", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/authentication")
    refute html =~ "SSO provider"
  end

  test "shows provider options when SSO is enabled via toggle", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

    html = render_hook(lv, "toggle_sso")

    assert html =~ "SSO provider"
  end

  test "ignores an unsupported provider selection", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

    render_hook(lv, "toggle_sso")
    html = render_hook(lv, "select_provider", %{"value" => ["unsupported"]})

    assert html =~ "Google Workspace domain"
    refute html =~ "Provider URL"
  end

  describe "Google SSO" do
    test "disables save button when domain is empty", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_hook(lv, "toggle_sso")
      html = render_hook(lv, "select_provider", %{"value" => ["google"]})

      assert html =~ "disabled"
    end

    test "shows error when user has no Google OAuth identity", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

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
      user: user,
      organization: organization
    } do
      Accounts.link_oauth_identity_to_user(user, %{
        provider: :google,
        id_in_provider: "google-uid-#{System.unique_integer([:positive])}",
        provider_organization_id: "example.com"
      })

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["google"]})

      html =
        lv
        |> form("#sso-form", %{"sso" => %{"google_domain" => "example.com"}})
        |> render_submit()

      refute html =~ "Failed to configure"
      assert html =~ "Enable Single Sign-On"

      {:ok, updated_organization} = Accounts.get_organization_by_id(organization.id)
      assert updated_organization.sso_automatic_enrollment
    end
  end

  describe "Okta SSO" do
    test "disables save button when required fields are empty", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_hook(lv, "toggle_sso")
      html = render_hook(lv, "select_provider", %{"value" => ["okta"]})

      assert html =~ "disabled"
    end

    test "configures Okta SSO with all fields", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

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

  describe "Microsoft Entra ID SSO" do
    test "disables save button when the tenant is empty", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_hook(lv, "toggle_sso")
      html = render_hook(lv, "select_provider", %{"value" => ["entra"]})

      assert html =~ "disabled"
      assert html =~ "Directory (tenant) ID"
    end

    test "derives the endpoints from the directory (tenant) ID", %{
      conn: conn,
      account: account,
      organization: organization
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["entra"]})

      lv
      |> form("#sso-form", %{
        "sso" => %{
          "entra_tenant_id" => "11111111-2222-3333-4444-555555555555",
          "sso_login_domain" => "example.com",
          "oauth2_client_id" => "test_client_id",
          "oauth2_client_secret" => "test_client_secret"
        }
      })
      |> render_submit()

      {:ok, updated_organization} = Accounts.get_organization_by_id(organization.id)

      assert updated_organization.sso_provider == :oauth2

      assert updated_organization.sso_organization_id ==
               "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/v2.0"

      assert updated_organization.oauth2_authorize_url ==
               "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/oauth2/v2.0/authorize"

      assert updated_organization.oauth2_token_url ==
               "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/oauth2/v2.0/token"

      assert updated_organization.oauth2_user_info_url == "https://graph.microsoft.com/oidc/userinfo"
    end

    test "reopens a saved configuration on the Entra form with its tenant", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["entra"]})

      lv
      |> form("#sso-form", %{
        "sso" => %{
          "entra_tenant_id" => "contoso.onmicrosoft.com",
          "oauth2_client_id" => "test_client_id",
          "oauth2_client_secret" => "test_client_secret"
        }
      })
      |> render_submit()

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/authentication")

      document = Floki.parse_fragment!(html)
      assert Floki.attribute(document, "#sso_entra_tenant_id", "value") == ["contoso.onmicrosoft.com"]
    end

    test "keeps a hand-configured Entra organization on the generic OAuth2 form", %{
      conn: conn,
      account: account,
      organization: organization
    } do
      {:ok, _organization} =
        Accounts.update_sso_configuration(organization.id, :oauth2, %{
          sso_organization_id: "https://sts.windows.net/11111111-2222-3333-4444-555555555555/",
          oauth2_client_id: "test_client_id",
          oauth2_client_secret: "test_client_secret",
          oauth2_authorize_url:
            "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/oauth2/v2.0/authorize",
          oauth2_token_url: "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/oauth2/v2.0/token",
          oauth2_user_info_url: "https://graph.microsoft.com/oidc/userinfo"
        })

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/authentication")

      document = Floki.parse_fragment!(html)

      assert Floki.attribute(document, "#sso_oauth2_site", "value") == [
               "https://sts.windows.net/11111111-2222-3333-4444-555555555555"
             ]
    end

    test "rejects a tenant that is not a single path segment", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["entra"]})

      html =
        lv
        |> form("#sso-form", %{
          "sso" => %{
            "entra_tenant_id" => "https://login.microsoftonline.com/tenant/v2.0",
            "oauth2_client_id" => "test_client_id",
            "oauth2_client_secret" => "test_client_secret"
          }
        })
        |> render_change()

      assert html =~ "disabled"
    end
  end

  describe "Custom OAuth2 SSO" do
    test "disables save button when required fields are empty", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_hook(lv, "toggle_sso")
      html = render_hook(lv, "select_provider", %{"value" => ["oauth2"]})

      assert html =~ "disabled"
    end

    test "shows error when submitting invalid URLs", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

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

      document = Floki.parse_fragment!(html)

      assert Floki.attribute(document, "#sso_oauth2_site", "value") == ["not-a-url"]
      assert Floki.attribute(document, "#sso_oauth2_authorize_url", "value") == ["not-a-url"]
      assert Floki.attribute(document, "#sso_oauth2_token_url", "value") == ["not-a-url"]
      assert Floki.attribute(document, "#sso_oauth2_user_info_url", "value") == ["not-a-url"]
    end

    test "configures OAuth2 SSO with private Keycloak-style URLs on self-hosted installations", %{
      conn: conn,
      account: account
    } do
      stub(Environment, :tuist_hosted?, fn -> false end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["oauth2"]})

      html =
        lv
        |> form("#sso-form", %{
          "sso" => %{
            "oauth2_site" => "https://10.0.0.1/realms/master",
            "oauth2_client_id" => "test_client_id",
            "oauth2_client_secret" => "test_client_secret",
            "oauth2_authorize_url" => "https://10.0.0.1/realms/master/protocol/openid-connect/auth",
            "oauth2_token_url" => "https://10.0.0.1/realms/master/protocol/openid-connect/token",
            "oauth2_user_info_url" => "https://10.0.0.1/realms/master/protocol/openid-connect/userinfo"
          }
        })
        |> render_submit()

      refute html =~ "must be a valid URL"
      assert html =~ "Enable Single Sign-On"
    end

    test "stores the login domain separately and shows its verification record", %{
      conn: conn,
      account: account,
      organization: organization
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_hook(lv, "toggle_sso")
      render_hook(lv, "select_provider", %{"value" => ["oauth2"]})

      html =
        lv
        |> form("#sso-form", %{
          "sso" => %{
            "oauth2_site" => "https://login.vendor.example",
            "sso_login_domain" => "Customer.Example.",
            "oauth2_client_id" => "test_client_id",
            "oauth2_client_secret" => "test_client_secret",
            "oauth2_authorize_url" => "https://login.vendor.example/authorize",
            "oauth2_token_url" => "https://login.vendor.example/token",
            "oauth2_user_info_url" => "https://login.vendor.example/userinfo"
          }
        })
        |> render_submit()

      assert html =~ "Pending verification"
      assert html =~ "_tuist-verification.customer.example"
      assert html =~ "tuist-domain-verification="
      assert has_element?(lv, ~s([data-testid="sso-automatic-enrollment-toggle"][data-disabled]))

      {:ok, updated_organization} = Accounts.get_organization_by_id(organization.id)
      assert updated_organization.sso_organization_id == "https://login.vendor.example"
      assert updated_organization.sso_login_domain == "customer.example"
      refute updated_organization.sso_login_domain_verified_at
      assert updated_organization.sso_login_domain_verification_token
    end

    test "keeps legacy enforcement while an existing organization adds its replacement login domain", %{
      conn: conn,
      account: account,
      organization: organization,
      user: user
    } do
      {:ok, configured_organization} =
        Accounts.update_sso_configuration(organization.id, :oauth2, %{
          sso_organization_id: "https://login.vendor.example",
          oauth2_client_id: "test_client_id",
          oauth2_client_secret: "test_client_secret",
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        })

      {:ok, _legacy_organization} =
        configured_organization
        |> Ecto.Changeset.change(
          sso_enforced: true,
          sso_automatic_enrollment: true,
          sso_legacy_email_domain_fallback: true
        )
        |> Tuist.Repo.update()

      Accounts.link_oauth_identity_to_user(user, %{
        provider: :oauth2,
        id_in_provider: "legacy-admin",
        provider_organization_id: "https://login.vendor.example"
      })

      conn = put_session(conn, :auth_method, :oauth2)
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      html =
        lv
        |> form("#sso-form", %{
          "sso" => %{
            "oauth2_site" => "https://login.vendor.example",
            "sso_login_domain" => "customer.example",
            "oauth2_client_id" => "test_client_id",
            "oauth2_client_secret" => "",
            "oauth2_authorize_url" => "https://login.vendor.example/authorize",
            "oauth2_token_url" => "https://login.vendor.example/token",
            "oauth2_user_info_url" => "https://login.vendor.example/userinfo"
          }
        })
        |> render_submit()

      assert html =~ "Pending verification"
      assert html =~ "This existing configuration allows any email address reported by the provider"

      {:ok, updated_organization} = Accounts.get_organization_by_id(organization.id)
      assert updated_organization.sso_enforced
      assert updated_organization.sso_automatic_enrollment
      assert updated_organization.sso_legacy_email_domain_fallback
      assert updated_organization.sso_login_domain == "customer.example"
      refute updated_organization.sso_login_domain_verified_at
    end

    test "verifies a saved login domain", %{
      conn: conn,
      account: account,
      organization: organization
    } do
      {:ok, configured_organization} =
        Accounts.update_sso_configuration(organization.id, :oauth2, %{
          sso_organization_id: "https://login.vendor.example",
          sso_login_domain: "customer.example",
          oauth2_client_id: "test_client_id",
          oauth2_client_secret: "test_client_secret",
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        })

      expect(SSOLoginDomainVerification, :verified?, fn domain, token ->
        assert domain == "customer.example"
        assert token == configured_organization.sso_login_domain_verification_token
        true
      end)

      {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/authentication")
      assert html =~ "Pending verification"

      html = render_hook(lv, "verify_sso_login_domain")

      assert html =~ "The login domain has been verified."
      assert html =~ "Verified"
      refute html =~ "Pending verification"
    end

    test "does not verify a domain that changed after the form was rendered", %{
      conn: conn,
      account: account,
      organization: organization
    } do
      {:ok, configured_organization} =
        Accounts.update_sso_configuration(organization.id, :oauth2, %{
          sso_organization_id: "https://login.vendor.example",
          sso_login_domain: "customer.example",
          oauth2_client_id: "test_client_id",
          oauth2_client_secret: "test_client_secret",
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        })

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      assert {:ok, changed_organization} =
               Accounts.update_organization(configured_organization, %{
                 sso_login_domain: "other.example"
               })

      reject(SSOLoginDomainVerification, :verified?, 2)

      html = render_hook(lv, "verify_sso_login_domain")

      assert html =~ "Save the login domain before verifying it."
      assert changed_organization.sso_login_domain == "other.example"
      refute changed_organization.sso_login_domain_verified_at
    end

    test "persists the automatic enrollment policy", %{
      conn: conn,
      account: account,
      organization: organization
    } do
      {:ok, configured_organization} =
        Accounts.update_sso_configuration(organization.id, :oauth2, %{
          sso_organization_id: "https://login.vendor.example",
          sso_login_domain: "customer.example",
          oauth2_client_id: "test_client_id",
          oauth2_client_secret: "test_client_secret",
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        })

      expect(SSOLoginDomainVerification, :verified?, fn domain, token ->
        assert domain == "customer.example"
        assert token == configured_organization.sso_login_domain_verification_token
        true
      end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")
      render_hook(lv, "verify_sso_login_domain")
      refute has_element?(lv, ~s([data-testid="sso-automatic-enrollment-toggle"][data-disabled]))
      render_hook(lv, "toggle_sso_automatic_enrollment")

      lv
      |> form("#sso-form", %{
        "sso" => %{
          "oauth2_site" => "https://login.vendor.example",
          "sso_login_domain" => "customer.example",
          "oauth2_client_id" => "test_client_id",
          "oauth2_client_secret" => "",
          "oauth2_authorize_url" => "https://login.vendor.example/authorize",
          "oauth2_token_url" => "https://login.vendor.example/token",
          "oauth2_user_info_url" => "https://login.vendor.example/userinfo"
        }
      })
      |> render_submit()

      {:ok, updated_organization} = Accounts.get_organization_by_id(organization.id)
      assert updated_organization.sso_automatic_enrollment
    end

    test "persists the role automatic enrollment grants", %{
      conn: conn,
      account: account,
      organization: organization
    } do
      {:ok, configured_organization} =
        Accounts.update_sso_configuration(organization.id, :oauth2, %{
          sso_organization_id: "https://login.vendor.example",
          sso_login_domain: "customer.example",
          oauth2_client_id: "test_client_id",
          oauth2_client_secret: "test_client_secret",
          oauth2_authorize_url: "https://login.vendor.example/authorize",
          oauth2_token_url: "https://login.vendor.example/token",
          oauth2_user_info_url: "https://login.vendor.example/userinfo"
        })

      expect(SSOLoginDomainVerification, :verified?, fn _domain, token ->
        assert token == configured_organization.sso_login_domain_verification_token
        true
      end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")
      render_hook(lv, "verify_sso_login_domain")
      render_hook(lv, "toggle_sso_automatic_enrollment")
      render_hook(lv, "select_sso_default_role", %{"value" => ["viewer"]})

      lv
      |> form("#sso-form", %{
        "sso" => %{
          "oauth2_site" => "https://login.vendor.example",
          "sso_login_domain" => "customer.example",
          "oauth2_client_id" => "test_client_id",
          "oauth2_client_secret" => "",
          "oauth2_authorize_url" => "https://login.vendor.example/authorize",
          "oauth2_token_url" => "https://login.vendor.example/token",
          "oauth2_user_info_url" => "https://login.vendor.example/userinfo"
        }
      })
      |> render_submit()

      {:ok, updated_organization} = Accounts.get_organization_by_id(organization.id)
      assert updated_organization.sso_default_role == "viewer"
      assert Accounts.sso_default_role(updated_organization) == "viewer"
    end

    test "turns off automatic enrollment and enforcement when switching to an unverified custom provider", %{
      conn: conn,
      account: account,
      organization: organization
    } do
      {:ok, _organization} =
        Accounts.update_organization(organization, %{
          sso_provider: :google,
          sso_organization_id: "customer.example",
          sso_enforced: true,
          sso_automatic_enrollment: true
        })

      conn = put_session(conn, :auth_method, :google)
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")
      render_hook(lv, "select_provider", %{"value" => ["oauth2"]})

      assert has_element?(lv, ~s([data-testid="sso-automatic-enrollment-toggle"][data-disabled]))
      assert has_element?(lv, ~s([data-testid="sso-enforced-toggle"][data-disabled]))

      lv
      |> form("#sso-form", %{
        "sso" => %{
          "oauth2_site" => "https://login.vendor.example",
          "sso_login_domain" => "",
          "oauth2_client_id" => "test_client_id",
          "oauth2_client_secret" => "test_client_secret",
          "oauth2_authorize_url" => "https://login.vendor.example/authorize",
          "oauth2_token_url" => "https://login.vendor.example/token",
          "oauth2_user_info_url" => "https://login.vendor.example/userinfo"
        }
      })
      |> render_submit()

      {:ok, updated_organization} = Accounts.get_organization_by_id(organization.id)
      assert updated_organization.sso_provider == :oauth2
      refute updated_organization.sso_automatic_enrollment
      refute updated_organization.sso_enforced
    end
  end

  describe "SCIM provisioning" do
    test "shows the empty-state message when no tokens exist", %{conn: conn, account: account} do
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/authentication")
      assert html =~ "No SCIM tokens yet"
    end

    test "generates a token, reveals it in the modal, and lists it in the table", %{
      conn: conn,
      account: account,
      organization: org
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

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
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      html = render_submit(lv, "generate_scim_token", %{"scim_token" => %{"name" => "  "}})

      assert html =~ "Token name is required"
      assert SCIM.list_tokens(org) == []
    end

    test "dismissing the modal clears the revealed plaintext", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_submit(lv, "generate_scim_token", %{"scim_token" => %{"name" => "okta"}})

      html = render_hook(lv, "dismiss_scim_token")
      refute html =~ "Token created"
      refute html =~ "tuist_scim_"
    end

    test "open_change reset clears any leftover plaintext", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      render_submit(lv, "generate_scim_token", %{"scim_token" => %{"name" => "okta"}})

      html = render_hook(lv, "scim_modal_open_change", %{"open" => false})
      refute html =~ "tuist_scim_"
    end

    test "revokes a token", %{conn: conn, account: account, organization: org} do
      {:ok, {token, _plaintext}} = SCIM.create_token(org, %{name: "to-revoke"})

      {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/authentication")
      assert html =~ "to-revoke"

      html = render_hook(lv, "revoke_scim_token", %{"id" => token.id})
      refute html =~ "SCIM token revoked."
      refute html =~ "to-revoke"
      assert SCIM.list_tokens(org) == []
    end

    test "does not revoke a token from another organization", %{conn: conn, account: account} do
      other_org = AccountsFixtures.organization_fixture()
      {:ok, {other_token, _plaintext}} = SCIM.create_token(other_org, %{name: "other-org-token"})

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/authentication")

      html = render_hook(lv, "revoke_scim_token", %{"id" => other_token.id})
      assert html =~ "Token not found."
      assert [%{id: token_id}] = SCIM.list_tokens(other_org)
      assert token_id == other_token.id
    end
  end
end
