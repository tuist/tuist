defmodule TuistWeb.OnceCacheLiveTest do
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
          command_display: "once build",
          host_class: "macos-arm64",
          once_version: "0.60.0",
          started_at: started_at
        })

      {:ok, run} =
        OnceEvents.finalize_run(run, %{
          finalization: "finalized",
          exit_status: 0,
          wall_ms: 1000,
          finalized_at: started_at
        })

      OnceEvents.ingest_action(run, %{
        target_execution_id: "target-#{index}",
        capability: "build",
        action_index: 0,
        result: "succeeded",
        was_cached: true,
        duration_ms: 5,
        exit_code: 0,
        finished_at: started_at
      })
    end

    %{path: "/#{organization.account.name}/#{project.name}/once-cache"}
  end

  test "the cache hit rate can be shown as a scatter of runs", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    render_async(view)

    assert has_element?(view, "#once-cache-analytics-chart")
    refute has_element?(view, "#once-cache-hit-rate-scatter-chart")

    render_click(view, "select_hit_rate_chart_type", %{"type" => "scatter"})
    render_async(view)

    assert has_element?(view, "#once-cache-hit-rate-scatter-chart")
    refute has_element?(view, "#once-cache-analytics-chart")
  end

  test "the scatter groups by host or Once version", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path <> "?cache-hit-rate-chart-type=scatter")
    render_async(view)

    assert has_element?(view, "#once-cache-hit-rate-scatter-chart")
    # Host is the default grouping and the runs above all report one host.
    assert render(view) =~ "macos-arm64"

    {:ok, view, _} =
      live(conn, path <> "?cache-hit-rate-chart-type=scatter&cache-hit-rate-scatter-group-by=version")

    render_async(view)

    assert render(view) =~ "0.60.0"
  end
end
