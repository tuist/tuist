defmodule TuistWeb.RemoteExecutionLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Bazel
  alias Tuist.Bazel.Profile
  alias Tuist.IngestRepo
  alias Tuist.OnceEvents
  alias Tuist.RemoteExecution.Analytics
  alias Tuist.RemoteExecution.Scheduler
  alias Tuist.RemoteExecution.UsageEvent
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{project: project, organization: organization} do
    project = project |> Ecto.Changeset.change(build_system: :bazel) |> Repo.update!()
    %{project: project, path: "/#{organization.account.name}/#{project.name}/remote-execution"}
  end

  test "Bazel analytics, widget selection and invocation drill-down", %{
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
    assert has_element?(view, "#remote-execution", "No remote executions in this period")
    assert has_element?(view, "#remote-execution-duration [data-part=trend]", "since last month")
    assert has_element?(view, "#remote-execution-duration", "250ms")
    assert has_element?(view, "#remote-execution-queue[data-empty]")
    refute has_element?(view, "#remote-execution-chart")
    assert has_element?(view, "#remote-execution-activity", "bazel build //app:local")

    render_click(view, "select_execution_type", %{"type" => "p90"})
    assert has_element?(view, "#remote-execution-duration", "p90 execution time")
    view |> element("[phx-value-widget=execution]") |> render_click()
    assert has_element?(view, "#remote-execution-chart")
    assert has_element?(view, "#remote-execution-sort-by-label-portal", "Ran at")

    {:ok, view, _} = live(conn, path <> "?invocations-sort-by=execution&invocations-sort-order=asc")
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-sort-by-label-portal", "Avg. execution")
    assert has_element?(view, "#remote-execution-activity th", "Avg. execution")

    refute has_element?(view, "#remote-execution-environment-dropdown")
    assert has_element?(view, "#remote-execution-activity", "//app:ci")
    assert has_element?(view, "#remote-execution-activity a[href*='tab=remote-execution']")

    view |> form("#remote-execution-search-form", search: "missing") |> render_change()
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution", "No invocations match your search")
    assert has_element?(view, "#remote-execution-duration", "250ms")

    view |> form("#remote-execution-search-form", search: "") |> render_change()
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-activity", "//app:ci")

    {:ok, view, _} = live(conn, path <> "?filter_target_patterns_op=%3D~&filter_target_patterns_val=local")
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-activity", "//app:local")
    refute has_element?(view, "#remote-execution-activity", "//app:ci")
    assert has_element?(view, "#remote-execution [data-part=active-filters]", "Targets")
    assert has_element?(view, "#remote-execution-duration", "250ms")
  end

  test "running invocations lead the table with their remote actions and usage charts the ledger", %{
    conn: conn,
    project: project,
    path: path
  } do
    observed_at = DateTime.utc_now()

    :ok =
      Bazel.create_invocation_starts([
        %{
          project_id: project.id,
          invocation_id: "running-build",
          command: "build",
          target_patterns: ["//app:running"],
          is_ci: false,
          started_at: observed_at |> DateTime.add(-90, :second) |> DateTime.to_naive()
        }
      ])

    action = fn state, invocation_id, memory_gb, ago_ms ->
      %{
        id: Ecto.UUID.generate(),
        state: state,
        action_digest: "abcdef0123456789/10",
        invocation_id: invocation_id,
        mnemonic: "CppCompile",
        target: "//app:running",
        memory_gb: memory_gb,
        since: DateTime.add(observed_at, -ago_ms, :millisecond)
      }
    end

    # A build Kura has not reported yet still shows up through its actions;
    # an action without an invocation belongs to none.
    stub(Scheduler, :activity, fn _account_id, _project_id ->
      {:ok,
       [
         action.("running", "running-build", 8, 3_000),
         action.("queued", "running-build", 16, 1_500),
         action.("queued", "running-build", 8, 1_000),
         action.("running", "unreported-build", 8, 1_000),
         action.("running", nil, 8, 1_000)
       ]}
    end)

    now = NaiveDateTime.utc_now()

    IngestRepo.insert_all(UsageEvent, [
      usage_event(project, NaiveDateTime.add(now, -2, :day), 2, 4_000),
      usage_event(project, NaiveDateTime.add(now, -1, :day), 8, 60_000),
      usage_event(project, NaiveDateTime.add(now, -40, :day), 8, 1_000)
    ])

    {:ok, view, _} = live(conn, path)
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-activity tbody tr:first-child", "Invocation unreport")
    assert has_element?(view, "#remote-execution-activity tbody tr:first-child", "1 running · 0 queued")
    assert has_element?(view, "#remote-execution-activity tbody tr:nth-child(2)", "bazel build //app:running")
    assert has_element?(view, "#remote-execution-activity tbody tr:nth-child(2)", "1 running · 2 queued")
    assert has_element?(view, "#remote-execution-activity tbody tr:nth-child(2)", ~r/1m 3\ds/)
    assert has_element?(view, "#remote-execution-activity tbody tr", "Running")

    assert has_element?(
             view,
             "#remote-execution-activity a[href$='/builds/invocations/running-build?tab=remote-execution']"
           )

    assert has_element?(view, "#remote-execution-executions", "2")
    assert has_element?(view, "#remote-execution-execution-time", "1m 4s")
    assert has_element?(view, "#remote-execution-usage-chart")
    # One line for the project, not one per machine shape.
    assert has_element?(view, "#remote-execution-usage-chart [data-part=data]", "Executions")
    refute has_element?(view, "#remote-execution-usage-chart [data-part=data]", "vCPU")
    view |> element("[phx-value-widget=execution-time]") |> render_click()
    assert has_element?(view, "[data-selected][phx-value-widget=execution-time]")
    refute has_element?(view, "[data-selected][phx-value-widget=executions]")

    # Without the scheduler, Kura's report alone keeps the build listed.
    stub(Scheduler, :activity, fn _account_id, _project_id -> {:error, :unavailable} end)
    send(view.pid, :refresh_running)
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-activity tbody tr:first-child", "bazel build //app:running")
    refute has_element?(view, "#remote-execution-activity", "Invocation unreport")
    refute has_element?(view, "#remote-execution-activity", "running · ")

    # A failing diagnostics query leaves the usage widgets in place.
    stub(Analytics, :summary, fn _project_id, _opts -> raise "diagnostics query failed" end)
    stub(Analytics, :activity, fn _project_id, _opts -> raise "diagnostics query failed" end)

    ExUnit.CaptureLog.capture_log(fn ->
      {:ok, view, _} = live(conn, path)
      render_async(view, 5000)
      assert has_element?(view, "#remote-execution-executions", "2")
      assert has_element?(view, "#remote-execution-queue", "Couldn't load")
      assert has_element?(view, "[data-part=bazel-invocations-table-section] [data-error]")
    end)
  end

  test "Struo runs show their remote actions, while local actions never count", %{
    conn: conn,
    project: project,
    path: path
  } do
    project = project |> Ecto.Changeset.change(build_system: :once) |> Repo.update!()
    run_id = "run-" <> UUIDv7.generate()

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: run_id,
        kind: "build",
        command_display: "struo build atlas/mix_application_test",
        started_at: DateTime.utc_now()
      })

    # A local action of the run: never a remote execution.
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

    queued = System.os_time(:microsecond) - 60_000_000

    {:ok, 1} =
      Tuist.RemoteExecution.Actions.ingest(project, [
        %{
          "operation_id" => Ecto.UUID.generate(),
          "action_hash" => String.duplicate("c", 64),
          "invocation_id" => run_id,
          "tool_name" => "struo",
          "mnemonic" => "elixir-compile",
          "target" => "atlas/mix_application_test",
          "exit_code" => 0,
          "timestamps" => %{
            "queued" => queued,
            "worker_start" => queued + 2_000_000,
            "execution_start" => queued + 2_100_000,
            "execution_completed" => queued + 5_100_000,
            "worker_completed" => queued + 5_200_000
          }
        }
      ])

    {:ok, view, _} = live(conn, path)
    render_async(view, 5000)
    refute has_element?(view, "[data-once-telemetry-gap]")
    assert has_element?(view, "#remote-execution-queue", "2.0s")
    assert has_element?(view, "#remote-execution-activity", "struo build atlas/mix_application_test")
    assert has_element?(view, "#remote-execution-activity a[href$='/once/runs/#{run_id}']")

    # The run reported a local environment.
    {:ok, view, _} = live(conn, path <> "?analytics-environment=local")
    render_async(view, 5000)
    assert has_element?(view, "#remote-execution-environment-label-portal", "Local")
    assert has_element?(view, "#remote-execution-activity a[href$='/once/runs/#{run_id}']")

    {:ok, view, _} = live(conn, path <> "?analytics-environment=ci")
    render_async(view, 5000)
    refute has_element?(view, "#remote-execution-activity a[href$='/once/runs/#{run_id}']")
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

  defp usage_event(project, inserted_at, vcpus, duration_ms) do
    %{
      id: UUIDv7.generate(),
      account_id: project.account_id,
      project_id: project.id,
      sandbox_id: UUIDv7.generate(),
      mode: "scheduled",
      vcpus: vcpus,
      memory_mb: vcpus * 2048,
      duration_ms: duration_ms,
      inserted_at: NaiveDateTime.truncate(inserted_at, :microsecond)
    }
  end
end
