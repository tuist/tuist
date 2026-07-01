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
      Tuist.Builds.list_build_runs(%{
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

  test "filters build runs by scheme", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    RunsFixtures.build_fixture(
      project_id: project.id,
      scheme: "App"
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      scheme: "Framework"
    )

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_scheme_op===&filter_scheme_val=App"
      )

    assert has_element?(lv, "[data-part='build-runs-table'] span", "App")
    refute has_element?(lv, "[data-part='build-runs-table'] span", "Framework")
  end

  test "filters build runs by ran_by user without including continuous integration runs", %{
    conn: conn,
    user: user,
    organization: organization,
    project: project
  } do
    RunsFixtures.build_fixture(
      project_id: project.id,
      user_id: user.account.id,
      scheme: "local-user-build",
      is_ci: false
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      user_id: user.account.id,
      scheme: "ci-user-build",
      is_ci: true
    )

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs?filter_ran_by_op===&filter_ran_by_val=#{user.account.id}"
      )

    assert has_element?(lv, "[data-part='build-runs-table'] span", "local-user-build")
    refute has_element?(lv, "[data-part='build-runs-table'] span", "ci-user-build")
  end

  test "filters build runs whose branch does not contain a substring", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    RunsFixtures.build_fixture(
      project_id: project.id,
      scheme: "Queued",
      git_branch: "gh-readonly-queue/main"
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      scheme: "Regular",
      git_branch: "feature/main"
    )

    query =
      URI.encode_query(%{
        "filter_git_branch_op" => "!=~",
        "filter_git_branch_val" => "gh-readonly-queue"
      })

    {:ok, lv, html} =
      live(conn, "/#{organization.account.name}/#{project.name}/builds/build-runs?#{query}")

    assert has_element?(lv, "[data-part='build-runs-table']")
    assert html =~ "does not contain"
    assert has_element?(lv, "[data-part='build-runs-table'] span", "Regular")
    refute has_element?(lv, "[data-part='build-runs-table'] span", "Queued")
  end
end
