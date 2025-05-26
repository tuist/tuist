defmodule TuistWeb.BuildRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.RunsFixtures

  test "lists latest build runs", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    RunsFixtures.build_fixture(
      project_id: project.id,
      scheme: "App"
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      scheme: "AppTests"
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs")

    # Then
    assert has_element?(lv, "span", "App")
    assert has_element?(lv, "span", "AppTests")
  end
end
