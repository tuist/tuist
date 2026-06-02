defmodule TuistWeb.IntegrationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "user123#{System.unique_integer([:positive])}")
    stub(Tuist.Environment, :github_app_configured?, fn -> true end)
    # The integrations UI gates its Enterprise tab on
    # `Entitlements.allows?(account, :github_enterprise_server)` which
    # short-circuits to true on self-hosted (`tuist_hosted?` false).
    # CI runs with `TUIST_HOSTED=1`, so without this stub the tab is
    # hidden and every test that interacts with it fails. The dedicated
    # entitlement-gate describe block (further down) overrides this.
    stub(Tuist.Environment, :tuist_hosted?, fn -> false end)

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        creator: user,
        preload: [:account]
      )

    selected_project = ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)

    conn =
      conn
      |> assign(:selected_project, selected_project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, project: selected_project, organization: organization, account: account}
  end

  test "renders integrations page with GitHub section", %{conn: conn, organization: organization} do
    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    assert html =~ "Integrations"
    assert html =~ "GitHub"
    assert html =~ "Connect any of your GitHub repositories to a project"
  end

  test "shows install GitHub app button when no installation exists", %{
    conn: conn,
    organization: organization,
    account: _account
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    assert has_element?(lv, "a", "Install GitHub App")
  end

  test "hides the GitHub Enterprise URL input by default", %{conn: conn, organization: organization} do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    refute html =~ "Server URL"
    assert html =~ "github.com"
    assert html =~ "Enterprise server"
  end

  test "reveals the URL input when the Enterprise server tab is selected", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.example.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    html = render_click(lv, "select-github-enterprise")
    assert html =~ "Server URL"
    assert html =~ "Organization"
  end

  test "shows a validation error and disables the install button for malformed URLs", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "not-a-url"
      })
      |> render_change()

    assert html =~ "Invalid URL"
  end

  test "rejects github.com URLs on the Enterprise server tab", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "https://github.com/tuist/tuist"
      })
      |> render_change()

    assert html =~ "Use a GitHub Enterprise Server URL"
  end

  test "rejects repository URLs in the GitHub Enterprise Server URL field", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://tuist.dev/integrations/github/manifest/start?state=test"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "https://github.example.com/ios/app"
      })
      |> render_change()

    assert html =~ "Use a GitHub Enterprise Server URL"
  end

  test "passes the optional GitHub organization to the manifest flow", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, opts ->
      case Keyword.get(opts, :github_app_owner) do
        "ios" -> "https://tuist.dev/integrations/github/manifest/start?state=with-org"
        _ -> "https://tuist.dev/integrations/github/manifest/start?state=without-org"
      end
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "https://github.example.com",
        "github_app_owner" => "ios"
      })
      |> render_change()

    assert html =~ "state=with-org"
  end

  test "shows a validation error for malformed GitHub organization names", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://tuist.dev/integrations/github/manifest/start?state=test"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "https://github.example.com",
        "github_app_owner" => "ios/bumble"
      })
      |> render_change()

    assert html =~ "Invalid organization"
  end

  test "switching back to github.com hides the input and clears the URL", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    lv
    |> form("form[phx-change=update-github-client-url]", %{
      "github_client_url" => "https://github.example.com"
    })
    |> render_change()

    html = render_click(lv, "select-github-com")

    refute html =~ "Server URL"
    assert html =~ "Install GitHub App"
  end

  test "defaults to the Enterprise tab when github.com isn't configured but GHES is entitled",
       %{conn: conn, organization: organization} do
    # Regression: a self-hosted Tuist deployment with no `TUIST_GITHUB_APP_*`
    # env vars but a GHES-entitled account would otherwise land on the
    # github.com tab by default — clicking Install would generate a
    # broken `/apps//installations/new` URL because there is no global
    # app name to interpolate.
    stub(Tuist.Environment, :github_app_configured?, fn -> false end)

    {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    # Server URL input renders (Enterprise tab is the default).
    assert html =~ "Server URL"

    # Form is interactive — change events trigger the validator.
    error_html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{"github_client_url" => ""})
      |> render_change()

    # Empty URL on the Enterprise tab surfaces a "Required" error
    # (validate_github_client_url/2 distinguishes empty + Enterprise
    # from empty + github.com).
    assert error_html =~ "Required"
  end

  describe "delete-connection" do
    test "does not allow deleting a VCS connection belonging to a different account", %{
      conn: conn,
      organization: organization
    } do
      # Given: a VCS connection on a completely different account
      other_user = AccountsFixtures.user_fixture()
      other_org = AccountsFixtures.organization_fixture(creator: other_user, preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_org.account.id)

      other_installation =
        VCSFixtures.github_app_installation_fixture(account_id: other_org.account.id)

      {:ok, other_connection} =
        Tuist.Projects.create_vcs_connection(%{
          project_id: other_project.id,
          provider: :github,
          repository_full_handle: "other-org/other-repo",
          github_app_installation_id: other_installation.id
        })

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

      # When: the user sends a delete event with the other account's connection ID
      render_hook(lv, "delete-connection", %{"connection_id" => other_connection.id})

      # Then: the connection should still exist
      assert {:ok, _} = Tuist.Projects.get_vcs_connection(other_connection.id)
    end
  end

  test "shows GitHub repositories when GitHub app is installed", %{
    conn: conn,
    organization: organization,
    account: account
  } do
    _github_installation = VCSFixtures.github_app_installation_fixture(account_id: account.id)

    stub(VCS, :get_github_app_installation_repositories, fn _installation ->
      {:ok, [%{id: 123, full_name: "test-org/test-repo"}]}
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    assert has_element?(lv, "button", "Add new project connection")

    html = render_async(lv)
    assert html =~ "test-org/test-repo"
  end

  describe "GitHub Enterprise Server entitlement gate (hosted Tuist server)" do
    setup do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      :ok
    end

    test "hides the Enterprise server tab when the account is not on the Enterprise plan",
         %{conn: conn, organization: organization, account: account} do
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

      refute html =~ "Enterprise server"
    end

    test "shows the Enterprise server tab when the account is on the Enterprise plan",
         %{conn: conn, organization: organization, account: account} do
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

      assert html =~ "Enterprise server"
    end

    test "ignores a fabricated select-github-enterprise event when the account is not entitled",
         %{conn: conn, organization: organization, account: account} do
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

      html = render_click(lv, "select-github-enterprise")

      refute html =~ "Server URL"
    end
  end
end
