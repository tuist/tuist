defmodule TuistWeb.OnceOverviewLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.OnceEvents

  setup %{project: project, organization: organization} do
    project = project |> Ecto.Changeset.change(build_system: :once) |> Tuist.Repo.update!()
    at = DateTime.add(DateTime.utc_now(), -3600, :second)

    for {kind, exit_status} <- [{"build", 0}, {"build", 1}, {"test", 0}] do
      {:ok, run} =
        OnceEvents.upsert_run(%{
          project_id: project.id,
          run_id: UUIDv7.generate(),
          kind: kind,
          command_display: "once #{kind}",
          started_at: at
        })

      {:ok, run} =
        OnceEvents.finalize_run(run, %{
          finalization: "finalized",
          exit_status: exit_status,
          wall_ms: 1000,
          finalized_at: at
        })

      OnceEvents.ingest_action(run, %{
        target_execution_id: "target",
        capability: "build",
        action_index: 0,
        result: "succeeded",
        was_cached: true,
        duration_ms: 5,
        exit_code: 0,
        finished_at: at
      })
    end

    %{path: "/#{organization.account.name}/#{project.name}"}
  end

  test "a Once project gets an overview instead of a redirect", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    render_async(view)

    assert has_element?(view, "#once-overview")

    # The same three cards the other build systems land on.
    assert has_element?(view, "[data-part=analytics-card]")
    assert has_element?(view, "#once-cache-hit-rate")
    assert has_element?(view, "#once-average-build-time")
    assert has_element?(view, "#once-average-test-run-time")

    # Two builds, one of which failed, and one passing test run.
    assert has_element?(view, "#once-overview-builds-passed", "1")
    assert has_element?(view, "#once-overview-builds-failed", "1")
    assert has_element?(view, "#once-overview-tests-passed", "1")
  end

  test "changing the period keeps the overview rendered", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    render_async(view)

    render_click(view, "analytics_period_changed", %{
      "value" => %{"start" => "2026-09-01", "end" => "2026-09-23"},
      "preset" => "last-7-days"
    })

    render_async(view)

    assert has_element?(view, "#once-overview")
  end
end
