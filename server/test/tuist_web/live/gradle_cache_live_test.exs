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

  test "cache savings and reporting coverage follow the selected environment", %{conn: conn, project: project} do
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
    assert has_element?(view, "#cache-savings-coverage", "2 of 3 builds")

    render_patch(view, path <> "?analytics-environment=ci")
    render_async(view, 5_000)
    assert has_element?(view, "#cache-savings-coverage", "1 of 1 builds")

    render_patch(view, path <> "?analytics-environment=local")
    render_async(view, 5_000)
    assert has_element?(view, "#cache-work-avoided", "0ms")
    assert has_element?(view, "#cache-savings-coverage", "1 of 2 builds")
  end
end
