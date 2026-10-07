defmodule TuistWeb.GradleCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.GradleFixtures

  setup %{project: project, conn: conn} do
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Tuist.Repo.update!()
    %{project: project, conn: Plug.Conn.assign(conn, :selected_project, project)}
  end

  test "task time saved widget and chart follow the selected environment", %{conn: conn, project: project} do
    inserted_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second) |> DateTime.to_naive()

    for {is_ci, metadata} <- [
          {true, %{"tuist.cache_work_avoided_ms" => "151"}},
          {false, %{"tuist.cache_work_avoided_ms" => "0"}},
          {false, %{}}
        ] do
      GradleFixtures.build_fixture(
        project_id: project.id,
        is_ci: is_ci,
        custom_values: metadata,
        inserted_at: inserted_at
      )
    end

    path = "/#{project.account.name}/#{project.name}/gradle-cache"
    {:ok, view, _} = live(conn, path)
    render_async(view, 5_000)
    assert has_element?(view, "#cache-work-avoided", "151ms")
    refute has_element?(view, "#cache-savings-coverage")
    refute has_element?(view, "#gradle-cache-savings")
    view |> element("[phx-value-widget=cache_work_avoided]") |> render_click()
    assert has_element?(view, "#gradle-task-time-saved-chart")
    refute has_element?(view, "#gradle-analytics-chart")

    render_patch(view, path <> "?analytics-environment=ci")
    render_async(view, 5_000)
    assert has_element?(view, "#cache-work-avoided", "151ms")
    refute has_element?(view, "#cache-savings-coverage")

    render_patch(view, path <> "?analytics-environment=local")
    render_async(view, 5_000)
    assert has_element?(view, "#cache-work-avoided", "0ms")
    refute has_element?(view, "#cache-savings-coverage")
    render_patch(view, path <> "?analytics-environment=local&analytics-selected-widget=cache_work_avoided")
    render_async(view, 5_000)
    assert has_element?(view, "#gradle-task-time-saved-chart")

    render_click(view, "select_widget", %{"widget" => "cache_downloads"})
    refute has_element?(view, "#gradle-task-time-saved-chart")
  end
end
