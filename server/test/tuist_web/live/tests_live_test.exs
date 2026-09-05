defmodule TuistWeb.TestsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @render_async_timeout 1_000

  test "renders a searchable scheme dropdown", %{
    conn: conn,
    project: project
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{project.account.name}/#{project.name}/tests")
    render_async(lv, @render_async_timeout)

    assert has_element?(lv, "#tests-analytics-scheme-dropdown [data-part='search-input']")
  end

  test "renders the shared test dashboard for Bazel projects", %{
    conn: conn,
    organization: organization
  } do
    project = ProjectsFixtures.project_fixture(account: organization.account, build_system: :bazel)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests")
    render_async(lv, @render_async_timeout)

    assert has_element?(lv, "[data-part='analytics']")
    assert has_element?(lv, "#tests-analytics-scheme-dropdown", "Targets:")
    refute has_element?(lv, "[data-part='selective-testing']")
  end
end
