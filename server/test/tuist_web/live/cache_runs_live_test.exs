defmodule TuistWeb.CacheRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  test "lists latest cache runs", %{
    conn: conn,
    user: user,
    organization: organization,
    project: project
  } do
    # Given
    _cache_run_one =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "cache",
        command_arguments: ["cache", "App"]
      )

    _cache_run_one =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "cache",
        command_arguments: ["cache", "AppTwo"]
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/binary-cache/cache-runs")

    # Then
    assert has_element?(lv, "span", "tuist cache App")
    assert has_element?(lv, "span", "tuist cache AppTwo")
  end
end
