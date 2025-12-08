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

  test "handles cursor mismatch when sort order changes", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    for i <- 1..25 do
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App-#{i}",
        duration: i * 1000
      )
    end

    # Generate a cursor with inserted_at sorting
    {_builds, %{end_cursor: cursor}} =
      Tuist.Runs.list_build_runs(%{
        filters: [%{field: :project_id, op: :==, value: project.id}],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 20
      })

    # Navigate with duration sorting but use the cursor from inserted_at sorting
    # Before the fix, this would raise Flop.InvalidParamsError
    assert {:ok, lv, _html} =
             live(
               conn,
               ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?build-runs-sort-by=duration&build-runs-sort-order=asc&after=#{cursor}"
             )

    assert has_element?(lv, "span", "App-1")
  end
end
