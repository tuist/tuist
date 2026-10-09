defmodule TuistWeb.IntegrationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.GitLab
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
    assert has_element?(lv, "#github-client-url[required]")

    assert has_element?(
             lv,
             "#github-enterprise-registration-form > .noora-text-input:first-child [data-part=required-indicator]",
             "*"
           )

    refute has_element?(lv, "#github-api-url[required]")
    refute html =~ "API URL (optional)"
    assert has_element?(lv, "#github-api-url-hint", "Leave empty to use the Server URL followed by /api/v3.")
    refute has_element?(lv, "#github-enterprise-registration-form > .noora-text-input:nth-child(2) > .noora-hint-text")
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

  test "carries a separate API URL in the signed registration link", %{conn: conn, organization: organization} do
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/settings/integrations")
    render_click(lv, "select-github-enterprise")
    assert has_element?(lv, "#github-api-url")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "https://github.internal.example.com",
        "github_api_url" => "  https://proxy.example.com/api/v3/  "
      })
      |> render_change()

    assert has_element?(lv, "a", "Install GitHub App")
    assert [_, url] = Regex.run(~r/href="([^"]*\/integrations\/github\/manifest\/start[^\"]*)"/, html)
    token = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("state")

    assert {:ok, %{client_url: "https://github.internal.example.com", api_url: "https://proxy.example.com/api/v3"}} =
             VCS.verify_github_state_token(token)
  end

  test "invalid API URLs disable installation but an empty override is allowed", %{conn: conn, organization: organization} do
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/settings/integrations")
    render_click(lv, "select-github-enterprise")

    for value <- ["invalid", "https://proxy.example.com/api/v3?token=secret", "https://u:p@proxy.example.com/api/v3"] do
      html =
        lv
        |> form("form[phx-change=update-github-client-url]", %{
          "github_client_url" => "https://github.internal.example.com",
          "github_api_url" => value
        })
        |> render_change()

      assert html =~ "Invalid URL"
      assert has_element?(lv, "button[disabled]", "Install GitHub App")
    end

    lv |> form("form[phx-change=update-github-client-url]", %{"github_api_url" => ""}) |> render_change()
    assert has_element?(lv, "a", "Install GitHub App")
  end

  test "switching tabs clears the API URL and any errors", %{conn: conn, organization: organization} do
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/settings/integrations")
    render_click(lv, "select-github-enterprise")

    lv
    |> form("form[phx-change=update-github-client-url]", %{
      "github_client_url" => "https://github.internal.example.com",
      "github_api_url" => "invalid"
    })
    |> render_change()

    render_click(lv, "select-github-com")
    refute has_element?(lv, "#github-api-url")
    assert has_element?(lv, "a", "Install GitHub App")
    html = render_click(lv, "select-github-enterprise")
    assert has_element?(lv, "#github-api-url[value='']")
    refute html =~ "Invalid URL"
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

  test "disables the Install button on the github.com tab when no github.com App is configured",
       %{conn: conn, organization: organization} do
    # Regression: the install URL interpolates `TUIST_GITHUB_APP_NAME`, so
    # with no github.com App configured the button linked to
    # `https://github.com/apps//installations/new`, which 404s on GitHub.
    stub(Tuist.Environment, :github_app_configured?, fn -> false end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    html = render_click(lv, "select-github-com")

    assert html =~ "No github.com App is configured"
    assert html =~ "TUIST_GITHUB_APP_NAME"
    assert has_element?(lv, "button[disabled]", "Install GitHub App")
    refute has_element?(lv, "a", "Install GitHub App")
  end

  test "keeps the Install button enabled on the github.com tab when the App is configured", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    refute html =~ "No github.com App is configured"
    assert has_element?(lv, "a", "Install GitHub App")
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

  test "updates and clears an existing Enterprise API URL without replacing the App or project connections", %{
    conn: conn,
    organization: organization,
    account: account,
    project: project
  } do
    installation =
      VCSFixtures.github_app_installation_fixture(
        account_id: account.id,
        client_url: "https://github.internal.example.com",
        api_url: "https://old-proxy.example.com/api/v3",
        app_id: "42",
        private_key: "pem",
        webhook_secret: "secret"
      )

    {:ok, connection} =
      Tuist.Projects.create_vcs_connection(%{
        project_id: project.id,
        provider: :github,
        repository_full_handle: "org/repo",
        github_app_installation_id: installation.id
      })

    stub(VCS, :get_github_app_installation_repositories, fn _ -> {:ok, []} end)
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    assert has_element?(
             lv,
             "[data-part=github-card-section] > [data-part=header] > [data-part=title]",
             "GitHub Enterprise Server"
           )

    assert has_element?(lv, "#github-client-url[readonly][value='https://github.internal.example.com']")
    assert has_element?(lv, "#github-api-url-form > .noora-text-input:first-child [data-part=label]", "Server URL")
    assert has_element?(lv, "#github-api-url[value='https://old-proxy.example.com/api/v3']")
    refute has_element?(lv, "#github-api-url[required]")
    refute render(lv) =~ "API URL (optional)"
    assert has_element?(lv, "#github-api-url-hint", "Leave empty to use the Server URL followed by /api/v3.")
    assert has_element?(lv, "#github-api-url-hint [data-part=trigger][tabindex='0']")
    refute has_element?(lv, "#github-api-url-form > .noora-text-input:nth-child(2) > .noora-hint-text")

    lv
    |> form("form[phx-submit=save-github-api-url]", %{"github_api_url" => "https://new-proxy.example.com/api/v3/"})
    |> render_submit()

    assert {:ok, updated} = VCS.get_github_app_installation_for_account(account.id)
    assert updated.api_url == "https://new-proxy.example.com/api/v3"
    assert updated.id == installation.id
    assert updated.client_url == installation.client_url
    assert updated.installation_id == installation.installation_id
    assert updated.private_key == installation.private_key
    assert updated.webhook_secret == installation.webhook_secret
    assert {:ok, ^connection} = Tuist.Projects.get_vcs_connection(connection.id)

    lv |> form("form[phx-submit=save-github-api-url]", %{"github_api_url" => ""}) |> render_submit()
    assert {:ok, cleared} = VCS.get_github_app_installation_for_account(account.id)
    assert cleared.api_url == nil
    assert cleared.id == installation.id
    assert cleared.client_url == installation.client_url
    assert VCS.installation_api_url(cleared) == "https://github.internal.example.com/api/v3"
    assert has_element?(lv, "#github-client-url[readonly][value='https://github.internal.example.com']")
  end

  test "identifies an existing Enterprise instance without an API override", %{
    conn: conn,
    organization: organization,
    account: account
  } do
    VCSFixtures.github_app_installation_fixture(account_id: account.id, client_url: "https://github.internal.example.com")
    stub(VCS, :get_github_app_installation_repositories, fn _ -> {:ok, []} end)
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    assert has_element?(
             lv,
             "[data-part=github-card-section] > [data-part=header] > [data-part=title]",
             "GitHub Enterprise Server"
           )

    assert has_element?(lv, "#github-client-url[readonly][value='https://github.internal.example.com']")
    assert has_element?(lv, "#github-api-url[value='']")
  end

  test "rejects invalid API updates even when submitted without client-side validation", %{
    conn: conn,
    organization: organization,
    account: account
  } do
    installation =
      VCSFixtures.github_app_installation_fixture(
        account_id: account.id,
        client_url: "https://github.internal.example.com",
        api_url: "https://proxy.example.com/api/v3"
      )

    stub(VCS, :get_github_app_installation_repositories, fn _ -> {:ok, []} end)
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    html =
      lv
      |> form("form[phx-submit=save-github-api-url]", %{"github_api_url" => "https://api.github.com"})
      |> render_submit()

    assert html =~ "Invalid URL"
    assert {:ok, unchanged} = VCS.get_github_app_installation_for_account(account.id)
    assert unchanged.api_url == installation.api_url
  end

  test "cannot update another account's API URL through a forged installation ID", %{
    conn: conn,
    organization: organization,
    account: account
  } do
    own = VCSFixtures.github_app_installation_fixture(account_id: account.id, client_url: "https://own.example.com")

    other =
      VCSFixtures.github_app_installation_fixture(
        client_url: "https://other.example.com",
        api_url: "https://other-proxy.example.com/api/v3"
      )

    stub(VCS, :get_github_app_installation_repositories, fn _ -> {:ok, []} end)
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_hook(lv, "save-github-api-url", %{
      "id" => other.id,
      "github_client_url" => "https://spoofed.example.com",
      "github_api_url" => "https://new-proxy.example.com/api/v3"
    })

    assert {:ok, own_updated} = VCS.get_github_app_installation_for_account(account.id)
    assert own_updated.id == own.id
    assert own_updated.client_url == own.client_url
    assert has_element?(lv, "#github-client-url[readonly][value='https://own.example.com']")
    assert own_updated.api_url == "https://new-proxy.example.com/api/v3"
    assert {:ok, other_unchanged} = VCS.get_github_app_installation_for_account(other.account_id)
    assert other_unchanged.api_url == other.api_url
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
    assert has_element?(lv, "[data-part=github-card-section] > [data-part=header] > [data-part=title]", "GitHub")
    refute has_element?(lv, "#github-client-url")

    html = render_async(lv)
    assert html =~ "test-org/test-repo"
  end

  test "adopts the repository's default branch when creating a connection", %{
    conn: conn,
    organization: organization,
    account: account,
    project: project
  } do
    _github_installation = VCSFixtures.github_app_installation_fixture(account_id: account.id)

    stub(VCS, :get_github_app_installation_repositories, fn _installation ->
      {:ok, [%{id: 123, full_name: "test-org/test-repo", default_branch: "develop"}]}
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")
    render_async(lv)

    render_hook(lv, "select-project", %{"project_id" => Integer.to_string(project.id)})
    render_hook(lv, "select-repository", %{"repository" => "test-org/test-repo"})
    render_hook(lv, "create-connection", %{})

    assert Tuist.Projects.get_project_by_id(project.id).default_branch == "develop"
    assert [%{id: project_id}] = Tuist.Projects.projects_by_vcs_repository_full_handle("test-org/test-repo")
    assert project_id == project.id
  end

  test "rejects a repository that is not accessible to the account's GitHub App installation", %{
    conn: conn,
    organization: organization,
    account: account,
    project: project
  } do
    _github_installation = VCSFixtures.github_app_installation_fixture(account_id: account.id)

    stub(VCS, :get_github_app_installation_repositories, fn _installation ->
      {:ok, [%{id: 123, full_name: "test-org/test-repo", default_branch: "main"}]}
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")
    render_async(lv)

    render_hook(lv, "select-project", %{"project_id" => Integer.to_string(project.id)})
    render_hook(lv, "select-repository", %{"repository" => "victim-org/victim-repo"})
    html = render_hook(lv, "create-connection", %{})

    assert html =~ "The selected repository is not accessible to this account&#39;s GitHub App installation."
    assert Tuist.Projects.projects_by_vcs_repository_full_handle("victim-org/victim-repo") == []
  end

  test "rejects a repository when the installation repositories cannot be fetched", %{
    conn: conn,
    organization: organization,
    account: account,
    project: project
  } do
    _github_installation = VCSFixtures.github_app_installation_fixture(account_id: account.id)

    stub(VCS, :get_github_app_installation_repositories, fn _installation -> {:error, :unauthorized} end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")
    render_async(lv)

    render_hook(lv, "select-project", %{"project_id" => Integer.to_string(project.id)})
    render_hook(lv, "select-repository", %{"repository" => "test-org/test-repo"})
    html = render_hook(lv, "create-connection", %{})

    assert html =~ "The selected repository is not accessible to this account&#39;s GitHub App installation."
    assert Tuist.Projects.projects_by_vcs_repository_full_handle("test-org/test-repo") == []
  end

  test "reuses the repositories loaded at mount when creating a connection", %{
    conn: conn,
    organization: organization,
    account: account,
    project: project
  } do
    _github_installation = VCSFixtures.github_app_installation_fixture(account_id: account.id)
    calls = :counters.new(1, [])

    stub(VCS, :get_github_app_installation_repositories, fn _installation ->
      :counters.add(calls, 1, 1)
      {:ok, [%{id: 123, full_name: "test-org/test-repo"}]}
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")
    render_async(lv)

    render_hook(lv, "select-project", %{"project_id" => Integer.to_string(project.id)})
    render_hook(lv, "select-repository", %{"repository" => "test-org/test-repo"})
    render_hook(lv, "create-connection", %{})

    assert [%{id: project_id}] = Tuist.Projects.projects_by_vcs_repository_full_handle("test-org/test-repo")
    assert project_id == project.id
    assert :counters.get(calls, 1) == 1
  end

  test "fetches the repositories again when the load at mount failed", %{
    conn: conn,
    organization: organization,
    account: account,
    project: project
  } do
    _github_installation = VCSFixtures.github_app_installation_fixture(account_id: account.id)
    calls = :counters.new(1, [])

    stub(VCS, :get_github_app_installation_repositories, fn _installation ->
      :counters.add(calls, 1, 1)

      if :counters.get(calls, 1) == 1,
        do: {:error, :timeout},
        else: {:ok, [%{id: 123, full_name: "test-org/test-repo"}]}
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")
    render_async(lv)

    render_hook(lv, "select-project", %{"project_id" => Integer.to_string(project.id)})
    render_hook(lv, "select-repository", %{"repository" => "test-org/test-repo"})
    render_hook(lv, "create-connection", %{})

    assert [%{id: project_id}] = Tuist.Projects.projects_by_vcs_repository_full_handle("test-org/test-repo")
    assert project_id == project.id
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

  describe "GitLab CI" do
    setup do
      stub(Tuist.FeatureFlags, :runners_enabled?, fn _ -> true end)
      :ok
    end

    test "connects with only URL and token, rotates tokens without reflecting secrets, and disconnects", %{
      conn: conn,
      account: account
    } do
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")
      assert html =~ "connect-gitlab-form"

      assert Floki.find(Floki.parse_document!(html), "#gitlab-profile") == []

      assert html |> Floki.parse_document!() |> Floki.find("input#gitlab-token") |> Floki.attribute("type") == [
               "password"
             ]

      html =
        lv
        |> form("#connect-gitlab-form", %{
          url: "https://gitlab.com",
          runner_token: "glrt-private-token"
        })
        |> render_submit()

      [connection] = GitLab.list_connections(account.id)
      assert connection.runner_token == "glrt-private-token"
      refute html =~ "glrt-private-token"
      refute has_element?(lv, "#connect-gitlab-form")

      assert has_element?(
               lv,
               "[data-part=gitlab-card-section] > [data-part=header-row] button[phx-click=disconnect-gitlab]"
             )

      refute has_element?(lv, "#gitlab-connection-#{connection.id} [data-part=title]")
      assert has_element?(lv, "#gitlab-connection-#{connection.id} input[name=_id]")
      refute has_element?(lv, "#gitlab-connection-#{connection.id} input[name=id]")
      lv |> form("#gitlab-connection-#{connection.id}", %{runner_token: ""}) |> render_submit()
      assert GitLab.get_connection(connection.id).runner_token == "glrt-private-token"
      html = lv |> form("#gitlab-connection-#{connection.id}", %{runner_token: "glrt-rotated"}) |> render_submit()
      refute html =~ "glrt-rotated"
      assert GitLab.get_connection(connection.id).runner_token == "glrt-rotated"
      lv |> element("button[phx-click=disconnect-gitlab][phx-value-id='#{connection.id}']") |> render_click()
      assert GitLab.list_connections(account.id) == []
      assert has_element?(lv, "#connect-gitlab-form")
      refute has_element?(lv, "button[phx-click=disconnect-gitlab]")
    end

    test "rejects invalid credentials without exposing the submitted token", %{conn: conn, account: account} do
      {:ok, lv, _} = live(conn, ~p"/#{account.name}/settings/integrations")

      html =
        lv
        |> form("#connect-gitlab-form", %{
          url: "https://gitlab.com",
          runner_token: "personal-access-secret"
        })
        |> render_submit()

      assert html =~ "Check the GitLab URL"
      refute html =~ "personal-access-secret"
      assert GitLab.list_connections(account.id) == []
    end

    test "does not connect runners when the feature is disabled", %{conn: conn, account: account} do
      stub(Tuist.FeatureFlags, :runners_enabled?, fn _ -> false end)
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")
      refute html =~ "connect-gitlab-form"

      render_hook(lv, "save-gitlab", %{
        url: "https://gitlab.com",
        runner_token: "glrt-secret"
      })

      assert GitLab.list_connections(account.id) == []
    end
  end

  describe "Buildkite" do
    setup do
      stub(Tuist.FeatureFlags, :runners_enabled?, fn _account -> true end)
      :ok
    end

    defp connect_buildkite(lv, attrs) do
      lv
      |> form(
        "#connect-buildkite-form",
        Map.merge(%{"organization_slug" => "acme", "agent_token" => "bkct_secret"}, attrs)
      )
      |> render_submit()
    end

    test "connects a cluster from the modal and shows it on the card", %{conn: conn, account: account} do
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      # Nothing connected: the card offers the modal and takes no more room.
      refute html =~ ~s(id="buildkite-form")

      html = connect_buildkite(lv, %{})

      installation = Buildkite.get_installation(account.id)
      assert installation.organization_slug == "acme"
      assert installation.agent_token == "bkct_secret"
      # Derived, never taken from the form: a customer-chosen key could
      # collide with another account's and swap their reservations.
      assert installation.stack_key == "tuist-#{account.id}"
      assert html =~ ~s(value="acme")
    end

    test "masks the agent token so it is never typed in the clear", %{conn: conn, account: account} do
      # Noora's `text_input` derives the HTML input type from `input_type`,
      # not from `type`, so `type="password"` alone renders a plaintext
      # field. Only the rendered attribute catches it.
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      token_input = html |> Floki.parse_document!() |> Floki.find("input#buildkite-agent-token")

      assert [_] = token_input
      assert Floki.attribute(token_input, "type") == ["password"]
    end

    test "reports a rejected token instead of storing it", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/integrations")

      html = connect_buildkite(lv, %{"agent_token" => "bkua_wrong_kind_of_token"})

      assert html =~ "cluster agent token"
      assert is_nil(Buildkite.get_installation(account.id))
    end

    test "surfaces the last poll error so a broken connection is visible", %{conn: conn, account: account} do
      {:ok, installation} =
        Buildkite.upsert_installation(account.id, %{
          organization_slug: "acme",
          stack_key: "tuist-#{account.id}",
          agent_token: "bkct_secret"
        })

      Buildkite.record_poll_result(installation, {:error, :unauthorized})

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      assert html =~ "Buildkite rejected the agent token"
    end

    test "disconnects a cluster", %{conn: conn, account: account} do
      {:ok, _installation} =
        Buildkite.upsert_installation(account.id, %{
          organization_slug: "acme",
          stack_key: "tuist-#{account.id}",
          agent_token: "bkct_secret"
        })

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/integrations")

      lv |> element("button[phx-click=disconnect-buildkite]") |> render_click()

      assert is_nil(Buildkite.get_installation(account.id))
    end

    defp connected(account) do
      {:ok, _installation} =
        Buildkite.upsert_installation(account.id, %{
          organization_slug: "acme",
          stack_key: "tuist-#{account.id}",
          agent_token: "bkct_secret"
        })

      :ok
    end

    test "saves a new organization from the card while a blank token keeps the current one", %{
      conn: conn,
      account: account
    } do
      connected(account)
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/integrations")

      html =
        lv
        |> form("#buildkite-form", %{"organization_slug" => "acme-mobile", "agent_token" => ""})
        |> render_submit()

      assert html =~ "Buildkite connection saved."
      installation = Buildkite.get_installation(account.id)
      assert installation.organization_slug == "acme-mobile"
      assert installation.agent_token == "bkct_secret"
    end

    test "saves a new token from the card", %{conn: conn, account: account} do
      connected(account)
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/integrations")

      lv
      |> form("#buildkite-form", %{"organization_slug" => "acme", "agent_token" => "bkct_rotated"})
      |> render_submit()

      installation = Buildkite.get_installation(account.id)
      assert installation.agent_token == "bkct_rotated"
      assert installation.organization_slug == "acme"
    end

    test "keeps an invalid organization on screen with its error instead of saving it", %{
      conn: conn,
      account: account
    } do
      connected(account)
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/integrations")

      html =
        lv
        |> form("#buildkite-form", %{"organization_slug" => "acme corp", "agent_token" => ""})
        |> render_submit()

      assert html =~ ~s(value="acme corp")
      assert html =~ "has invalid format"
      assert Buildkite.get_installation(account.id).organization_slug == "acme"
    end

    test "enables Save changes only once something changed", %{conn: conn, account: account} do
      connected(account)
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      save = fn html -> html |> Floki.parse_document!() |> Floki.find("#buildkite-form button[type=submit]") end

      # Rendered valueless, which Floki reads back as an empty string.
      assert Floki.attribute(save.(html), "disabled") == [""]

      html =
        lv
        |> form("#buildkite-form", %{"organization_slug" => "acme", "agent_token" => "bkct_new"})
        |> render_change()

      assert Floki.attribute(save.(html), "disabled") == []
    end

    test "masks the token field on the card", %{conn: conn, account: account} do
      connected(account)
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      token_input = html |> Floki.parse_document!() |> Floki.find("input#buildkite-token")

      assert [_] = token_input
      assert Floki.attribute(token_input, "type") == ["password"]
    end

    test "is hidden when runners are not enabled for the account", %{conn: conn, account: account} do
      stub(Tuist.FeatureFlags, :runners_enabled?, fn _account -> false end)

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      refute html =~ "buildkite-card-section"
    end
  end
end
