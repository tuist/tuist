defmodule TuistWeb.IntegrationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "user123#{System.unique_integer([:positive])}")
    stub(Tuist.Environment, :github_app_configured?, fn -> true end)

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
    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/integrations")

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

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/integrations")

    assert has_element?(lv, "a", "Install GitHub App")
  end

  test "hides the GitHub Enterprise URL input by default", %{conn: conn, organization: organization} do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/integrations")

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

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/integrations")

    html = render_click(lv, "select-github-enterprise")
    assert html =~ "Server URL"
  end

  test "shows a validation error and disables the install button for malformed URLs", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "not-a-url"
      })
      |> render_change()

    assert html =~ "Invalid URL"
  end

  test "switching back to github.com hides the input and clears the URL", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/integrations")

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

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/integrations")

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

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/integrations")

    assert has_element?(lv, "button", "Add new project connection")

    html = render_async(lv)
    assert html =~ "test-org/test-repo"
  end
end
