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
    stub(VCS, :get_github_app_installation_url, fn _account ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/integrations")

    assert has_element?(lv, "a", "Install GitHub App")
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
