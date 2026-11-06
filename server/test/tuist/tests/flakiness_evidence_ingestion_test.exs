defmodule Tuist.Tests.FlakinessEvidenceIngestionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.ClickHouseRepo
  alias Tuist.Shards.TestReport
  alias Tuist.Tests
  alias Tuist.Tests.FlakinessEvidence
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunFlakyCorrection
  alias Tuist.Tests.Workers.CorrectTestCaseRunFlakyStateWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  test "a successful rerun cannot turn a correlated crash into historical flaky evidence" do
    project = ProjectsFixtures.project_fixture(default_branch: "main")
    failed = ingest(project, modules("failure"))
    assert length(case_runs(failed)) == 20

    assert Enum.all?(
             case_runs(failed),
             &(&1.status == "failure" and not &1.is_flaky and
                 &1.is_flakiness_excluded == true)
           )

    for table <- [
          "test_case_runs_by_commit",
          "test_case_run_daily_stats_per_case",
          "test_case_run_daily_stats_per_case_default_branch",
          "test_case_runs_recent_window_per_case",
          "test_case_runs_default_branch_recent_window_per_case"
        ] do
      assert %{rows: [[0]]} =
               ClickHouseRepo.query!(
                 "SELECT count() FROM #{table} WHERE project_id = {project_id:Int64}",
                 %{project_id: project.id}
               )
    end

    passed = ingest(project, modules("success"))
    refute_enqueued(worker: CorrectTestCaseRunFlakyStateWorker)

    assert Enum.all?(
             case_runs(passed),
             &(not &1.is_flaky and &1.is_flakiness_excluded == false)
           )

    assert Enum.all?(case_runs(failed), &(not &1.is_flaky))

    assert %{rows: [[20, 20, 0]]} =
             ClickHouseRepo.query!(
               "SELECT countMerge(run_count), sumMerge(successful_run_count), sumMerge(flaky_run_count) FROM test_case_run_daily_stats_per_case WHERE project_id = {project_id:Int64}",
               %{project_id: project.id}
             )
  end

  test "crashes arriving after a passing run stay failures without becoming flaky" do
    project = ProjectsFixtures.project_fixture()
    ingest(project, modules("success"))
    failed = ingest(project, modules("failure"))
    assert {:ok, %{is_flaky: false}} = Tests.get_test(failed.id)
    assert Enum.all?(case_runs(failed), &(&1.status == "failure" and not &1.is_flaky))
  end

  test "successful in-report retries retain diagnostics without becoming flaky" do
    project = ProjectsFixtures.project_fixture()

    modules =
      Enum.map(modules("failure"), fn module ->
        %{
          module
          | status: "success",
            test_cases:
              Enum.map(module.test_cases, fn test_case ->
                Map.merge(test_case, %{
                  status: "success",
                  duration: 100,
                  repetitions: [
                    %{status: "failure", duration: 0},
                    %{status: "success", duration: 100}
                  ]
                })
              end)
        }
      end)

    run = ingest(project, modules)
    assert {:ok, %{is_flaky: false}} = Tests.get_test(run.id)

    assert Enum.all?(
             case_runs(run),
             &(not &1.is_flaky and &1.is_flakiness_excluded == true)
           )

    assert %{rows: [[20]]} =
             ClickHouseRepo.query!(
               "SELECT count() FROM test_case_failures WHERE test_case_run_id IN (SELECT id FROM test_case_runs WHERE test_run_id = {id:UUID})",
               %{id: run.id}
             )
  end

  test "ordinary assertion failures in a crash burst still become flaky after a pass" do
    project = ProjectsFixtures.project_fixture()

    assertion = %{
      name: "AssertionTests",
      status: "failure",
      duration: 10,
      test_cases: [
        %{
          name: "test_assertion",
          status: "failure",
          duration: 10,
          failures: [%{message: "XCTAssertEqual failed", path: "Tests.swift", line_number: 12}]
        }
      ]
    }

    failed = ingest(project, modules("failure") ++ [assertion])

    passing_assertion = %{
      assertion
      | status: "success",
        test_cases: [%{name: "test_assertion", status: "success", duration: 10}]
    }

    ingest(project, modules("success") ++ [passing_assertion])
    assert [job] = all_enqueued(worker: CorrectTestCaseRunFlakyStateWorker)
    assertion_run = Enum.find(case_runs(failed), &(&1.name == "test_assertion"))
    assert job.args["test_case_run_ids"] == [assertion_run.id]
    assert :ok = perform_job(CorrectTestCaseRunFlakyStateWorker, job.args)
    RunsFixtures.optimize_test_case_runs()
    assert Enum.count(case_runs(failed), & &1.is_flaky) == 1
  end

  test "server evidence annotations preserve immutable report identity" do
    attrs = %{test_modules: modules("failure"), build_system: "xcode"}

    assert TestReport.identity_digest(attrs) ==
             TestReport.identity_digest(FlakinessEvidence.annotate(attrs))

    changed =
      put_in(attrs, [:test_modules, Access.at(0), :test_cases, Access.at(0), :duration], 1)

    refute TestReport.identity_digest(attrs) == TestReport.identity_digest(changed)
  end

  test "a stale correction job cannot mark an excluded execution flaky" do
    project = ProjectsFixtures.project_fixture()
    failed = ingest(project, modules("failure"))
    row = hd(case_runs(failed))

    Repo.insert!(%TestCaseRunFlakyCorrection{
      test_case_run_id: row.id,
      project_id: project.id,
      test_case_id: row.test_case_id,
      git_commit_sha: row.git_commit_sha
    })

    assert :ok = Tests.apply_test_case_run_flaky_corrections([row.id])
    assert :ok = Tests.apply_test_case_run_flaky_corrections([row.id])
    assert length(case_runs(failed)) == 20
    assert Enum.all?(case_runs(failed), &(not &1.is_flaky))
    assert Repo.get!(TestCaseRunFlakyCorrection, row.id).state == "applied"
  end

  defp ingest(project, modules) do
    {:ok, run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: project.account_id,
        git_commit_sha: "correlated-crash",
        git_branch: "main",
        scheme: "App",
        is_ci: true,
        status: hd(modules).status,
        test_modules: modules
      )

    run
  end

  defp case_runs(run) do
    ClickHouseRepo.all(from(r in TestCaseRun, where: r.test_run_id == ^run.id))
  end

  defp modules(status) do
    for module <- 1..2 do
      %{
        name: "Module#{module}",
        status: status,
        duration: 0,
        test_cases:
          for(
            index <- 1..10,
            do: %{
              name: "test_#{index}",
              test_suite_name: "Suite",
              status: status,
              duration: 0,
              failures:
                if(status == "failure",
                  do: [
                    %{
                      message: "Crash: xctest",
                      path: "",
                      line_number: 0,
                      issue_type: "assertion_failure"
                    }
                  ],
                  else: []
                )
            }
          )
      }
    end
  end
end
