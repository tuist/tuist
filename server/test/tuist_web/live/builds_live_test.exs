defmodule TuistWeb.BuildsLiveTest do
  use TuistTestSupport.Cases.ConnCase, clickhouse: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.RunsFixtures

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
    render_async(lv)

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

    render_async(lv)

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
    render_async(lv)

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
    render_async(lv)

    assert has_element?(lv, "#builds-analytics-scheme-dropdown [data-part='search-input']")
  end
end
