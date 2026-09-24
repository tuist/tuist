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

    # Renders under the same container and parts as the Xcode overview, so
    # `overview.css` styles it rather than an approximation of it.
    assert has_element?(view, "#once-overview.overview")
    assert has_element?(view, "[data-part=analytics]")
    assert has_element?(view, "[data-part=cache-effectiveness-card-chart-section]")
    assert has_element?(view, "[data-part=effectiveness-chart]")
    assert has_element?(view, "#once-cache-hit-rate")
    assert has_element?(view, "#once-average-build-time")
    assert has_element?(view, "#once-average-test-run-time")

    # Builds and Tests each chart their recent runs with passed/failed
    # legends, the same shape the Bazel and Xcode overviews use.
    # Builds is the two column `builds-card-sections` Xcode uses: recent runs
    # on the left, average build time with its own View more on the right.
    assert has_element?(view, "[data-part=builds-card-sections]")
    assert has_element?(view, "[data-part=build-runs-chart]")
    assert has_element?(view, "[data-part=average-build-time-card-section]")
    assert has_element?(view, "[data-part=average-build-time-chart] [data-part=view-more]")
    assert has_element?(view, "#once-overview-builds-chart")
    assert has_element?(view, "#once-overview-average-build-time-chart")
    assert has_element?(view, "[data-part=test-runs-chart]")

    # Each card filters on its own period, and Tests sits above Builds.
    assert has_element?(view, "[data-part=analytics] #once-overview-date-range-picker")
    assert has_element?(view, "[data-part=builds-card-section] #builds-date-range-picker")

    order =
      view
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("[data-part=title]")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
      |> Enum.filter(&(&1 in ["Analytics", "Tests", "Builds"]))

    assert order == ["Analytics", "Tests", "Builds"]

    html = render(view)
    assert html =~ "Passed builds"
    assert html =~ "Failed builds"
    assert html =~ "Passed runs"

    # The percentage axis must not leak a formatter name into the label.
    refute html =~ "formatPercentage"
  end

  test "the Builds card filters on environment", %{conn: conn, path: path, project: project} do
    at = DateTime.add(DateTime.utc_now(), -3600, :second)

    # One CI build on top of the three local runs the setup creates, with a
    # duration nothing else uses so the legend counts are unambiguous.
    {:ok, ci_run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: "build",
        command_display: "once build",
        is_ci: true,
        started_at: at
      })

    {:ok, _} =
      OnceEvents.finalize_run(ci_run, %{
        finalization: "finalized",
        exit_status: 0,
        wall_ms: 4242,
        finalized_at: at
      })

    {:ok, view, _} = live(conn, path <> "?builds-environment=ci")
    render_async(view)

    assert has_element?(view, "#once-overview-builds-environment-dropdown")
    assert render(view) =~ "4242"

    # "Local" must exclude the CI run rather than showing everything.
    {:ok, view, _} = live(conn, path <> "?builds-environment=local")
    render_async(view)

    refute render(view) =~ "4242"

    # "Any" is unfiltered, so the CI run is back.
    {:ok, view, _} = live(conn, path <> "?builds-environment=any")
    render_async(view)

    assert render(view) =~ "4242"
  end

  test "changing the period keeps the overview rendered", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    # The card fans out to several `assign_async` queries, which do not
    # reliably settle inside `render_async/1`'s 100ms default when the suite
    # runs them alongside the other Once files.
    render_async(view, 2_000)

    render_click(view, "analytics_period_changed", %{
      "value" => %{"start" => "2026-09-01", "end" => "2026-09-23"},
      "preset" => "last-7-days"
    })

    render_async(view, 2_000)

    assert has_element?(view, "#once-overview")
  end
end
