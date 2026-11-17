defmodule TuistWeb.RemoteExecutionLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.Bazel
  alias Tuist.Bazel.Profile
  alias Tuist.OnceEvents
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{project: project, organization: organization} do
    project = project |> Ecto.Changeset.change(build_system: :bazel) |> Repo.update!()
    %{project: project, path: "/#{organization.account.name}/#{project.name}/remote-execution"}
  end

  test "Bazel analytics, environment filter, widget selection and invocation drill-down", %{
    conn: conn,
    project: project,
    path: path
  } do
    now = NaiveDateTime.add(NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second), -60)

    for {id, ci?, target} <- [{"compile-ci", true, "//app:ci"}, {"compile-local", false, "//app:local"}] do
      Bazel.create_invocations([
        %{
          project_id: project.id,
          invocation_id: id,
          command: "build",
          target_patterns: [target],
          git_branch: "main",
          is_ci: ci?,
          status: "success",
          exit_code: 0,
          started_at: now,
          finished_at: now,
          duration_ms: 1000,
          account_handle: "synthetic",
          project_handle: project.name,
          cache_endpoint: "cache.example.test"
        }
      ])

      events = [
        %{ph: "X", pid: 1, tid: 1, cat: "action processing", name: "Compile", ts: 0, dur: 1_000_000},
        %{ph: "X", pid: 1, tid: 1, cat: "Remote execution process wall time", name: "execute", ts: 1000, dur: 250_000}
      ]

      :ok = Profile.ingest(project, id, :zlib.gzip(JSON.encode!(%{otherData: %{build_id: id}, traceEvents: events})))
    end

    {:ok, view, _} = live(conn, path)
    render_async(view, 5000)
    assert has_element?(view, ".noora-tab-menu-vertical[data-selected]", "Remote execution")
    assert has_element?(view, "#remote-execution-actions", "2")
    assert has_element?(view, "#remote-execution-duration [data-part=trend]", "since last month")
    assert has_element?(view, "#remote-execution-duration", "250ms")
    assert has_element?(view, "#remote-execution-queue[data-empty]")
    assert has_element?(view, "#remote-execution-chart")
    assert has_element?(view, "#remote-execution-activity", "bazel build //app:local")

    render_click(view, "select_execution_type", %{"type" => "p90"})
    assert has_element?(view, "#remote-execution-duration", "p90 execution time")
    view |> element("[phx-value-widget=actions]") |> render_click()
    assert has_element?(view, "#remote-execution-chart")
    assert has_element?(view, "#remote-execution-sort-by-label-portal", "Ran at")

    {:ok, view, _} = live(conn, path <> "?invocations-sort-by=execution&invocations-sort-order=asc")
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-sort-by-label-portal", "Avg. execution")
    assert has_element?(view, "#remote-execution-activity th", "Avg. execution")

    {:ok, view, _} = live(conn, path <> "?analytics-environment=ci")
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-actions", "1")
    refute has_element?(view, "#remote-execution-activity", "//app:local")
    assert has_element?(view, "#remote-execution-activity a[href*='tab=remote-execution']")

    view |> form("#remote-execution-search-form", search: "missing") |> render_change()
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution", "No invocations match your search")
    assert has_element?(view, "#remote-execution-actions", "1")

    view |> form("#remote-execution-search-form", search: "") |> render_change()
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-activity", "//app:ci")

    {:ok, view, _} = live(conn, path <> "?filter_target_patterns_op=%3D~&filter_target_patterns_val=local")
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-activity", "//app:local")
    refute has_element?(view, "#remote-execution-activity", "//app:ci")
    assert has_element?(view, "#remote-execution [data-part=active-filters]", "Targets")
    assert has_element?(view, "#remote-execution-actions", "2")
  end

  test "Once local actions never become remote execution statistics", %{conn: conn, project: project, path: path} do
    project = project |> Ecto.Changeset.change(build_system: :once) |> Repo.update!()

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: "build",
        started_at: DateTime.utc_now()
      })

    OnceEvents.ingest_action(run, %{
      target_execution_id: "local",
      capability: "build",
      action_index: 0,
      result: "succeeded",
      was_cached: false,
      duration_ms: 100,
      worker_id: "worker-1",
      execute_ms: 100,
      finished_at: DateTime.utc_now()
    })

    {:ok, view, _} = live(conn, path)
    render_async(view, 5000)
    assert has_element?(view, "[data-once-telemetry-gap]", "Remote execution telemetry is not available for Once yet")
    assert has_element?(view, "a[href$='/once/build-runs']", "Open build runs")
    refute has_element?(view, "#remote-execution-actions")
    refute has_element?(view, "#remote-execution-chart")
  end

  test "empty projects stay discoverable while unsupported and private projects stay protected", %{
    conn: conn,
    project: project,
    path: path
  } do
    {:ok, view, _} = live(conn, path)
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-queue[data-empty]")
    assert has_element?(view, "#remote-execution", "No invocations with remote execution timings in this period")

    project |> Ecto.Changeset.change(build_system: :xcode) |> Repo.update!()
    assert_raise NotFoundError, fn -> live(conn, path) end

    foreign = [build_system: :bazel, visibility: :private] |> ProjectsFixtures.project_fixture() |> Repo.preload(:account)
    foreign_path = "/#{foreign.account.name}/#{foreign.name}/remote-execution"
    assert_raise NotFoundError, fn -> live(conn, foreign_path) end
  end
end
