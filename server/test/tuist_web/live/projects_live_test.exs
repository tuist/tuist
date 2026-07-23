defmodule TuistWeb.ProjectsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, account: account}
  end

  test "creates a project with the selected build system", %{conn: conn, account: account} do
    {:ok, view, _html} = live(conn, ~p"/#{account.name}/projects")

    render_hook(view, "select_build_system", %{"value" => ["gradle"]})

    view
    |> form("#create-project-form", project: %{name: "my-project"})
    |> render_submit()

    project = Projects.get_project_by_account_and_project_handles(account.name, "my-project")

    assert project.build_system == :gradle
  end

  test "shows why a reserved project name cannot be created", %{conn: conn, account: account} do
    {:ok, view, _html} = live(conn, ~p"/#{account.name}/projects")

    render_change(view, "validate-project", %{"project" => %{"name" => "test"}})

    html = view |> element("#create-project-form-modal-portal") |> render()

    assert html =~ "is reserved"
  end

  test "associates the portal-rendered create button with its form", %{conn: conn, account: account} do
    {:ok, view, _html} = live(conn, ~p"/#{account.name}/projects")

    html = view |> element("#create-project-form-modal-footer-portal") |> render()

    assert html =~ ~s(form="create-project-form")
  end

  test "ignores a stale pagination cursor on initial load", %{conn: conn, account: account} do
    for index <- 1..7 do
      ProjectsFixtures.project_fixture(account_id: account.id, name: "project-#{index}")
    end

    stale_cursor = Flop.Cursor.encode(%{inserted_at_naive: ~N[2025-04-14 12:30:17]})

    conn = get(conn, ~p"/#{account.name}/projects?before=#{stale_cursor}")

    assert html_response(conn, 200) =~ ~s(data-part="project")
  end
end
