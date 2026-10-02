defmodule Tuist.OnceEvents.TestReportIngestorTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Once.Events.V1.RunEvent
  alias Once.Events.V1.TestCaseCompleted
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Projector
  alias Tuist.OnceEvents.TestReportIngestor
  alias Tuist.Tests.Test.Buffer
  alias Tuist.Tests.TestCaseRun
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

  defp case_run_count(test_run_id) do
    TestCaseRun
    |> where([c], c.test_run_id == ^test_run_id)
    |> Tuist.IngestRepo.aggregate(:count)
  end

  test "a case that failed then passed on retry is recorded as flaky", %{run: run, project: project} do
    # Once retries in place and reports each attempt as its own event, so the
    # repetitions are the only evidence of flakiness.
    stage_case(run, %{case_id: "a", name: "a", attempt: 1, result: "failed", duration_ms: 10})
    stage_case(run, %{case_id: "a", name: "a", attempt: 2, result: "passed", duration_ms: 12})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run))

    # The verdict is the final attempt's, and the run is marked flaky.
    assert test.status == "success"
    assert test.is_flaky

    Buffer.flush()
    assert {:ok, %{is_flaky: true}} = Tuist.Tests.get_test(test.id)
    assert project.id == test.project_id
  end

  test "a case that keeps failing is not flaky", %{run: run} do
    stage_case(run, %{case_id: "a", name: "a", attempt: 1, result: "failed"})
    stage_case(run, %{case_id: "a", name: "a", attempt: 2, result: "failed"})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run, 1))

    refute test.is_flaky
    assert test.status == "failure"
  end

  test "retries collapse to one case rather than counting twice", %{run: run} do
    stage_case(run, %{case_id: "a", name: "a", attempt: 1, result: "failed", duration_ms: 10})
    stage_case(run, %{case_id: "a", name: "a", attempt: 2, result: "passed", duration_ms: 12})
    stage_case(run, %{case_id: "b", name: "b", attempt: 1, result: "passed", duration_ms: 5})

    assert {:ok, first} = TestReportIngestor.publish(finalize(run))

    Buffer.flush()
    assert case_run_count(first.id) == 2
  end

  test "a quarantined case is flagged on the published run", %{run: run, project: project} do
    stage_case(run, %{case_id: "muted_one", name: "muted_one", result: "failed"})

    # Quarantine the case before the run started. Without the marking step the
    # shared store never learns it is quarantined, so it keeps failing runs.
    identity = Tuist.Tests.generate_test_case_id(project.id, "muted_one", "cargo_aqua", "unit")

    Tuist.IngestRepo.insert_all(Tuist.Tests.TestCaseState, [
      %{
        project_id: project.id,
        test_case_id: identity,
        state: "muted",
        is_flaky: true,
        inserted_at: DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.to_naive()
      }
    ])

    assert {:ok, test} = TestReportIngestor.publish(finalize(run, 1))

    Buffer.flush()

    quarantined =
      TestCaseRun
      |> where([c], c.test_run_id == ^test.id and c.is_quarantined == true)
      |> Tuist.IngestRepo.aggregate(:count)

    assert quarantined == 1
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

  test "every Once case result maps onto the shared enum", %{run: run, project: project} do
    # Driven through the projector rather than by writing staged strings, so
    # the proto values a client actually sends are what gets mapped. An
    # earlier version of this test wrote the strings directly and missed that
    # unknown results were being recorded as passes.
    results = [
      {:TEST_CASE_RESULT_PASSED, "success"},
      {:TEST_CASE_RESULT_FAILED, "failure"},
      {:TEST_CASE_RESULT_SKIPPED, "skipped"},
      {:TEST_CASE_RESULT_ERRORED, "failure"},
      {:TEST_CASE_RESULT_TIMED_OUT, "failure"},
      {:TEST_CASE_RESULT_CANCELLED, "skipped"},
      {:TEST_CASE_RESULT_UNKNOWN, "skipped"},
      {:TEST_CASE_RESULT_UNSPECIFIED, "skipped"}
    ]

    for {result, _expected} <- results do
      Projector.project(
        %RunEvent{
          epoch_ms: 1_789_405_000_000,
          payload:
            {:test_case_completed,
             %TestCaseCompleted{
               test_case_execution_id: "cargo_aqua",
               suite_id: "unit",
               case_id: to_string(result),
               name: to_string(result),
               attempt: 1,
               result: result
             }}
        },
        project.id,
        run.run_id
      )
    end

    assert {:ok, test} = TestReportIngestor.publish(finalize(run, 1))

    Buffer.flush()

    stored =
      TestCaseRun
      |> where([c], c.test_run_id == ^test.id)
      |> select([c], {c.name, c.status})
      |> Tuist.IngestRepo.all()
      |> Map.new()

    for {result, expected} <- results do
      assert stored[to_string(result)] == expected,
             "#{result} should store as #{expected}, got #{inspect(stored[to_string(result)])}"
    end
  end

  test "an interrupted run does not manufacture failures", %{run: run} do
    # Cancelled cases never reached a verdict. Counting them as failures would
    # invent failure and flakiness signals out of an interrupted run.
    stage_case(run, %{case_id: "a", name: "a", result: "cancelled"})
    stage_case(run, %{case_id: "b", name: "b", result: "cancelled"})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run))
    assert test.status == "skipped"
  end

  test "a replayed RunCompleted does not publish the run twice", %{run: run} do
    stage_case(run, %{case_id: "a", name: "a"})
    finalized = finalize(run)

    assert {:ok, first} = TestReportIngestor.publish(finalized)

    # `create_test/1` is not a single atomic write. The run row dedupes on its
    # derived id, but the module, suite and case children are appended, so
    # without a publication guard a replay silently doubles every test case.
    # Asserting on the returned run alone did not catch that.
    # Both callers hold the run as it was BEFORE the first publish, which is
    # what two pods projecting the same replayed event would have. A read
    # check would let both through; the claim is a conditional update.
    assert {:ok, :already_published} = TestReportIngestor.publish(finalized)
    assert {:ok, :already_published} = TestReportIngestor.publish(finalized)

    Buffer.flush()

    assert case_run_count(first.id) == 1
  end

  test "the published run is readable back from the shared store", %{run: run, project: project} do
    stage_case(run, %{case_id: "a", name: "a", result: "passed"})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run))

    # `create_test/1` writes the run through `Test.Buffer`, so asserting on
    # the returned struct alone proves nothing about persistence. Flush and
    # read it back.
    Buffer.flush()

    assert {:ok, %{build_system: "once", once_run_id: once_run_id, project_id: project_id}} =
             Tuist.Tests.get_test(test.id)

    assert once_run_id == run.run_id
    assert project_id == project.id
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
