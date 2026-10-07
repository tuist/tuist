defmodule TuistWeb.ConnectLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(creator: user, preload: [:account])

    %{conn: log_in_user(conn, user), user: user, account: account}
  end

  defp open_connect(conn, account, build_system) do
    project = ProjectsFixtures.project_fixture(account_id: account.id, build_system: build_system)

    {:ok, view, html} =
      conn
      |> assign(:selected_project, project)
      |> assign(:selected_account, account)
      |> live(~p"/#{account.name}/#{project.name}/connect")

    {project, view, html}
  end

  test "walks a Mix project through the Hex package", %{conn: conn, account: account} do
    {project, _view, html} = open_connect(conn, account, :mix)

    assert html =~ "using Mix"
    assert html =~ "tuist_ex"
    assert html =~ "#{account.name}/#{project.name}"
    assert html =~ "mix tuist.login"
    assert html =~ "https://tuist.dev/en/docs/guides/get-started/elixir-project"
    refute html =~ "Install Tuist CLI"
  end

  test "walks every other project through the CLI", %{conn: conn, account: account} do
    {_project, _view, html} = open_connect(conn, account, :xcode)

    assert html =~ "using CLI"
    assert html =~ "Install Tuist CLI"
    refute html =~ "mix tuist.login"
  end

  test "shows the connection once the user reaches the project", %{conn: conn, user: user, account: account} do
    {project, view, html} = open_connect(conn, account, :mix)
    assert html =~ "Waiting for connection"

    Projects.notify_connected(project, user)

    assert render(view) =~ "Connection successful"
  end

  test "ignores someone else reaching the project", %{conn: conn, account: account} do
    {project, view, _html} = open_connect(conn, account, :mix)

    Projects.notify_connected(project, AccountsFixtures.user_fixture())
    Projects.notify_connected(project, nil)

    assert render(view) =~ "Waiting for connection"
  end
end
