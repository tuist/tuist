defmodule Tuist.OnceEvents.TestReportIngestorTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.TestReportIngestor
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    at = DateTime.utc_now()

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: "once-test-run-#{System.unique_integer([:positive])}",
        kind: "test",
        command_display: "once test //...",
        git_rev: "abc123",
        git_branch: "main",
        is_ci: true,
        started_at: at
      })

    %{project: project, run: run, at: at}
  end

  defp stage_case(run, attrs) do
    OnceEvents.ingest_test_case_run(
      run,
      Map.merge(
        %{
          target_execution_id: "cargo_aqua",
          suite_id: "unit",
          case_id: "case",
          name: "case",
          attempt: 1,
          result: "passed",
          duration_ms: 10,
          started_at: DateTime.utc_now(),
          finished_at: DateTime.utc_now()
        },
        attrs
      )
    )
  end

  defp finalize(run, exit_status \\ 0) do
    {:ok, finalized} =
      OnceEvents.finalize_run(run, %{
        finalization: "finalized",
        exit_status: exit_status,
        wall_ms: 1234,
        finalized_at: DateTime.utc_now()
      })

    finalized
  end

  test "a build run with no test cases publishes nothing", %{run: run} do
    assert TestReportIngestor.publish(finalize(run)) == {:ok, :no_test_cases}
  end

  test "a finished test run lands in the shared store as a Once run", %{run: run, project: project} do
    stage_case(run, %{case_id: "a", name: "a", result: "passed", duration_ms: 10})
    stage_case(run, %{case_id: "b", name: "b", result: "failed", duration_ms: 20})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run))

    assert test.build_system == "once"
    assert test.once_run_id == run.run_id
    assert test.project_id == project.id
    # Branch, commit and CI all have to reach the shared row: flaky detection
    # and quarantine key off them, so a build-system label alone is not enough.
    assert test.git_branch == "main"
    assert test.git_commit_sha == "abc123"
    assert test.git_ref == "refs/heads/main"
    assert test.is_ci
    assert test.status == "failure"
  end

  test "every Once case result maps onto the shared enum", %{run: run} do
    # The shared column is Enum8('success', 'failure', 'skipped'), so an
    # unmapped result is a write error rather than a silent coercion.
    for {result, _expected} <- [
          {"passed", "success"},
          {"failed", "failure"},
          {"errored", "failure"},
          {"timed_out", "failure"},
          {"cancelled", "skipped"},
          {"unknown", "skipped"},
          {"unspecified", "skipped"}
        ] do
      stage_case(run, %{case_id: result, name: result, result: result})
    end

    assert {:ok, _test} = TestReportIngestor.publish(finalize(run))
  end

  test "an interrupted run does not manufacture failures", %{run: run} do
    # Cancelled cases never reached a verdict. Counting them as failures would
    # invent failure and flakiness signals out of an interrupted run.
    stage_case(run, %{case_id: "a", name: "a", result: "cancelled"})
    stage_case(run, %{case_id: "b", name: "b", result: "cancelled"})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run))
    assert test.status == "skipped"
  end

  test "republishing the same run targets the same shared row", %{run: run} do
    stage_case(run, %{case_id: "a", name: "a"})
    finalized = finalize(run)

    assert {:ok, first} = TestReportIngestor.publish(finalized)
    assert {:ok, second} = TestReportIngestor.publish(finalized)

    # `create_test/1` is not a single atomic write, so a retry has to resolve
    # to one id rather than creating a second run for the same Once run.
    assert first.id == second.id
  end

  test "the run id is scoped by project, since Once run ids are client minted", %{run: run} do
    other_project = ProjectsFixtures.project_fixture()

    {:ok, other_run} =
      OnceEvents.upsert_run(%{
        project_id: other_project.id,
        run_id: run.run_id,
        kind: "test",
        started_at: DateTime.utc_now()
      })

    stage_case(run, %{case_id: "a", name: "a"})
    stage_case(other_run, %{case_id: "a", name: "a"})

    assert {:ok, first} = TestReportIngestor.publish(finalize(run))
    assert {:ok, second} = TestReportIngestor.publish(finalize(other_run))

    refute first.id == second.id
  end
end
