defmodule TuistWeb.ProjectSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  test "renders the project settings page", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    # Then
    assert html =~ "Settings"
  end

  test "handles URL parameter changes via live_patch", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    # Patch the URL with query params - this triggers handle_params
    assert render_patch(lv, ~p"/#{organization.account.name}/#{project.name}/settings?tab=general") =~
             "Settings"
  end

  test "surfaces the project's default branch", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, _project} = Tuist.Projects.update_project(project, %{default_branch: "develop"})

    {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    assert html =~ "Default branch"
    assert html =~ "develop"
    assert has_element?(lv, "#default-branch-modal")
    assert has_element?(lv, "#default-branch-form button svg.icon-tabler-pencil")
  end

  test "updates the project's default branch", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    lv
    |> form("#default-branch-form", %{"project" => %{"default_branch" => "trunk"}})
    |> render_submit()

    assert Tuist.Projects.get_project_by_id(project.id).default_branch == "trunk"
  end

  test "a blank default branch does not overwrite the current one", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    lv
    |> form("#default-branch-form", %{"project" => %{"default_branch" => "develop"}})
    |> render_submit()

    assert Tuist.Projects.get_project_by_id(project.id).default_branch == "develop"

    html =
      lv
      |> form("#default-branch-form", %{"project" => %{"default_branch" => "  "}})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert Tuist.Projects.get_project_by_id(project.id).default_branch == "develop"
  end
end
