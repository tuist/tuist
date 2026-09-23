defmodule TuistWeb.OnceRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.OnceEvents

  setup %{project: project, organization: organization} do
    project = project |> Ecto.Changeset.change(build_system: :once) |> Tuist.Repo.update!()
    started_at = DateTime.add(DateTime.utc_now(), -3600, :second)

    for index <- 1..3 do
      {:ok, run} =
        OnceEvents.upsert_run(%{
          project_id: project.id,
          run_id: UUIDv7.generate(),
          kind: "build",
          command_display: "once build crate#{index}",
          host_class: "macos-arm64",
          once_version: "0.60.0",
          started_at: started_at
        })

      {:ok, _} =
        OnceEvents.finalize_run(run, %{
          finalization: "finalized",
          exit_status: 0,
          wall_ms: 1000 * index,
          finalized_at: started_at
        })
    end

    %{path: "/#{organization.account.name}/#{project.name}/once/builds"}
  end

  test "the runs list can be searched by command", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    render_async(view)

    assert row_count(view) == 3

    view |> form("#once-invocations-search-form", %{search: "crate2"}) |> render_change()
    render_async(view)

    assert row_count(view) == 1
    assert has_element?(view, "#once-invocations-table", "crate2")
  end

  test "the build duration widget can be shown as a scatter of runs", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path <> "?analytics-selected-widget=build-duration")
    render_async(view)

    # Line by default.
    assert has_element?(view, "#once-builds-analytics-chart")
    refute has_element?(view, "#once-build-duration-scatter-chart")

    render_click(view, "select_duration_chart_type", %{"type" => "scatter"})
    render_async(view)

    assert has_element?(view, "#once-build-duration-scatter-chart")
    refute has_element?(view, "#once-builds-analytics-chart")
  end

  defp row_count(view),
    do: view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-invocations-table tbody tr") |> length()
end
