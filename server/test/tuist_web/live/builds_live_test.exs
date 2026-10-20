defmodule TuistWeb.BuildsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.RunsFixtures

  # render_async/2 is LiveViewTest's first-party hook for waiting on async assigns.
  # The builds widgets still cross analytics-backed async work that can be slower on CI,
  # so keep an explicit timeout until we have a deterministic non-time-based drain.
  @render_async_timeout 1_000

  test "renders empty view when no builds are available", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds")

    # Then
    assert has_element?(lv, "span", "No data yet")
  end

  test "lists latest builds", %{
    conn: conn,
    project: project
  } do
    # Given
    RunsFixtures.build_fixture(
      project_id: project.id,
      scheme: "AppOne"
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      scheme: "AppTwo"
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{project.account.name}/#{project.name}/builds")
    render_async(lv, @render_async_timeout)

    # Then
    assert has_element?(lv, "span", "AppOne")
    assert has_element?(lv, "span", "AppTwo")
  end

  test "displays chart type toggle when build-duration widget is selected", %{
    conn: conn,
    project: project
  } do
    yesterday = DateTime.add(DateTime.utc_now(), -1, :day)

    RunsFixtures.build_fixture(
      project_id: project.id,
      duration: 5000,
      status: "success",
      inserted_at: yesterday
    )

    # When - navigate with build-duration widget selected
    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{project.account.name}/#{project.name}/builds?analytics-selected-widget=build-duration"
      )

    render_async(lv, @render_async_timeout)

    # Then
    assert has_element?(lv, ".tuist-chart-type-toggle")
  end

  test "displays build success rate widget", %{
    conn: conn,
    project: project
  } do
    yesterday = DateTime.add(DateTime.utc_now(), -1, :day)

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: yesterday
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: yesterday
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "failure",
      inserted_at: yesterday
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{project.account.name}/#{project.name}/builds")
    render_async(lv, @render_async_timeout)

    # Then
    assert has_element?(lv, "#widget-build-success-rate")
    assert has_element?(lv, "span", "Build success rate")
    assert has_element?(lv, "span", "66.7%")
  end

  test "renders a searchable scheme dropdown", %{
    conn: conn,
    project: project
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{project.account.name}/#{project.name}/builds")
    render_async(lv, @render_async_timeout)

    assert has_element?(lv, "#builds-analytics-scheme-dropdown [data-part='search-input']")
  end

  test "renders with legacy analytics environment all query parameter", %{
    conn: conn,
    project: project
  } do
    {:ok, lv, _html} =
      live(conn, ~p"/#{project.account.name}/#{project.name}/builds?analytics-environment=all")

    render_async(lv, @render_async_timeout)

    assert has_element?(lv, "#builds-analytics-environment-dropdown")
  end

  test "failure categories follow scheme and environment filters", %{conn: conn, project: project} do
    yesterday = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

    for {scheme, is_ci, category} <- [{"App", true, "verification"}, {"Other", false, "infrastructure_tooling"}] do
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: scheme,
        is_ci: is_ci,
        status: "failure",
        inserted_at: yesterday,
        custom_values: %{"tuist.detected_failure_category" => category}
      )
    end

    path = "/#{project.account.name}/#{project.name}/builds"
    {:ok, view, _} = live(conn, path)
    render_async(view, 5_000)
    assert has_element?(view, "#build-runs-table", "App")
    assert has_element?(view, "#build-runs-table", "Other")
    render_patch(view, path <> "?analytics-build-scheme=App&analytics-environment=ci")
    render_async(view, 5_000)
    assert has_element?(view, "#build-runs-table", "App")
    refute has_element?(view, "#build-runs-table", "Other")
    render_patch(view, path <> "?analytics-build-scheme=App&analytics-environment=local")
    render_async(view, 5_000)
    refute has_element?(view, "#build-runs-table", "Verification")
  end
end
