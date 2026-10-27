defmodule Tuist.Shards.ImmutableReportsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.ClickHouseRepo
  alias Tuist.FeatureFlags
  alias Tuist.IngestRepo
  alias Tuist.Runners.Jobs
  alias Tuist.Shards
  alias Tuist.Shards.Analytics
  alias Tuist.Shards.ShardPlan
  alias Tuist.Shards.TestReport
  alias Tuist.Storage
  alias Tuist.Tasks
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestModuleRun
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    stub(FeatureFlags, :immutable_shard_reports_enabled?, fn _ -> true end)
    stub(Tasks, :run_async, fn _ -> :ok end)
    project = ProjectsFixtures.project_fixture()
    %{project: project}
  end

  test "creation stores the reporting contract and complete assignments in one plan row", %{project: project} do
    %{plan: plan} = plan(project)
    assert plan.reporting_version == 1
    assert %{"modules" => [_ | _], "test_suites" => []} = JSON.decode!(plan.assignments)
    assert {:ok, %{reporting_version: 1, assignments: assignments}} = Shards.get_shard_plan(plan.id)
    assert assignments == plan.assignments
  end

  @tag capture_log: true
  test "coverage enabled after enrollment cannot publish stale coverage or lose test results", %{project: project} do
    %{plan: plan} = plan(project, 1)
    stub(FeatureFlags, :xcode_coverage_enabled?, fn _ -> true end)

    assert {:ok, run} =
             report(project, plan, 0,
               coverage_enabled: true,
               coverage: %{files: []},
               xcode_coverage: %{path: "/nonexistent/coverage.ndjson"},
               coverage_evidence: %{paths: ["Sources/App.swift"], scopes: []},
               test_modules: [
                 %{name: "Tests", status: "success", test_cases: [%{name: "test_one", status: "success", duration: 10}]}
               ]
             )

    refute run.coverage_enabled
    assert run.coverage_evidence_status == ""
    assert %{total_count: 1} = Tuist.Tests.Analytics.get_test_run_metrics(run)

    assert {:ok, %{rows: [[0]]}} =
             ClickHouseRepo.query("SELECT count() FROM coverage_files WHERE project_id = {project_id:Int64}", %{
               project_id: project.id
             })

    assert {:ok, %{rows: [[0]]}} =
             ClickHouseRepo.query("SELECT count() FROM coverage_runs WHERE project_id = {project_id:Int64}", %{
               project_id: project.id
             })

    assert :skipped = Coverage.publish(run, %{}, 0, 1)
    assert :skipped = Coverage.enqueue_publish(run, %{storage_key: "ignored"}, 0, 1)
    assert :skipped = Tuist.Tests.Coverage.Evidence.record(run, %{paths: ["Sources/App.swift"]}, 0)

    reject(Storage, :download_to_file, 3)

    assert {:cancel, :immutable_shard_coverage_unsupported} =
             Tuist.Tests.Workers.PublishCoverageWorker.perform(%Oban.Job{
               args: %{"test_run_id" => run.id, "project_id" => project.id, "storage_key" => "ignored"}
             })
  end

  test "assignment reads never depend on separately published assignment rows", %{project: project} do
    now = NaiveDateTime.utc_now()

    attrs = %{
      id: Ecto.UUID.generate(),
      project_id: project.id,
      reference: "atomic",
      shard_count: 1,
      inserted_at: now,
      reporting_version: 1,
      assignments:
        JSON.encode!(%{modules: [%{shard_index: 0, module_name: "Tests", estimated_duration_ms: 10}], test_suites: []})
    }

    {:ok, stored} = %ShardPlan{} |> ShardPlan.create_changeset(attrs) |> IngestRepo.insert()
    reject(IngestRepo, :preload, 2)
    stub(Storage, :object_exists?, fn _, _ -> false end)
    stub(Storage, :generate_download_url, fn key, _ -> key end)
    account = Repo.preload(project, :account).account
    assert {:ok, %{modules: ["Tests"]}} = Shards.get_shard_for_plan_id(project, account, stored.id, 0)
  end

  test "legacy point lookups retain the projection-friendly physical source", %{project: project} do
    {:ok, legacy} = RunsFixtures.test_fixture(project_id: project.id)

    expect(ClickHouseRepo, :one, fn query ->
      assert query.from.source == {"test_runs", Test}
      refute "FINAL" in query.from.hints
      Mimic.call_original(ClickHouseRepo, :one, [query])
    end)

    assert {:ok, %{id: id}} = Tests.get_test(legacy.id)
    assert id == legacy.id
  end

  for version <- [0, 1] do
    @reporting_version version
    test "loaded version #{version} runs avoid reporting-contract lookups", %{project: project} do
      stub(FeatureFlags, :immutable_shard_reports_enabled?, fn _ -> @reporting_version == 1 end)
      %{plan: plan} = plan(project, 1)

      assert {:ok, created} =
               report(project, plan, 0,
                 status: "failure",
                 test_modules: [
                   %{name: "Tests", status: "failure", test_cases: [%{name: "test_one", status: "failure", duration: 10}]}
                 ]
               )

      assert {:ok, run} = Tests.get_test(created.id)
      assert run.reporting_version == @reporting_version
      reject(Tests, :get_test, 1)
      reject(Tests, :get_test, 2)
      reject_parent_lookups()

      assert Tests.get_test_run_failures_count(run) == 1
      assert %{total_count: 1, failed_count: 1} = Tuist.Tests.Analytics.get_test_run_metrics(run)

      for {field, id} <- [test_run_id: run.id, shard_id: plan.id] do
        {cases, meta} =
          Tests.list_test_case_runs(%{filters: [%{field: field, op: :==, value: id}]}, test_run: run)

        assert meta.total_count == 1
        assert [%{name: "test_one"}] = cases
      end
    end
  end

  test "a loaded run for another scope cannot select the fact source", %{project: project} do
    %{plan: plan} = plan(project, 1)

    assert {:ok, _} =
             report(project, plan, 0,
               test_modules: [
                 %{name: "Tests", status: "success", test_cases: [%{name: "test_one", status: "success", duration: 10}]}
               ]
             )

    assert {:ok, _run} = Tests.get_test(plan.id)
    other = %Test{id: Ecto.UUID.generate(), shard_plan_id: Ecto.UUID.generate(), reporting_version: 0}

    stub(ClickHouseRepo, :one, fn query ->
      if match?(%Ecto.Query{from: %{source: {_table, Test}}}, query), do: send(self(), :parent_lookup)
      Mimic.call_original(ClickHouseRepo, :one, [query])
    end)

    for scope <- [:test_run_id, :shard_id] do
      {cases, meta} =
        Tests.list_test_case_runs(%{filters: [%{field: scope, op: :==, value: plan.id}]}, test_run: other)

      assert meta.total_count == 1
      assert [%{name: "test_one"}] = cases
    end

    for _ <- 1..4, do: assert_receive(:parent_lookup)
    refute_received :parent_lookup
  end

  test "actor attribution and filters follow the selected immutable execution", %{project: project} do
    %{plan: plan} = plan(project, 1)
    actor_id = project.account_id

    for {attempt, claim, status} <- [{0, "previous", "failure"}, {1, "current", "success"}] do
      report(project, plan, 0,
        shard_attempt: attempt,
        actor_account_id: actor_id,
        claimed_actor_id: claim,
        submission_auth: "token",
        status: status,
        test_modules: [%{name: "Tests", status: status, test_cases: [%{name: "test_one", status: status, duration: 10}]}]
      )
    end

    assert {:ok, run} = Tests.get_test(plan.id)
    assert run.actor_account_id == actor_id
    assert run.claimed_actor_id == "current"
    assert run.submission_auth == "token"

    for scope <- [:test_run_id, :shard_id] do
      {cases, _} =
        Tests.list_test_case_runs(%{
          filters: [
            %{field: scope, op: :==, value: plan.id},
            %{field: :verified_actor, op: :==, value: actor_id},
            %{field: :claimed_actor_id, op: :==, value: "current"}
          ]
        })

      assert [%{status: "success", actor_account_id: ^actor_id, claimed_actor_id: "current"}] = cases
    end
  end

  test "a newer execution clears previous actor attribution instead of retaining sparse metadata", %{project: project} do
    %{plan: plan} = plan(project, 1)
    report(project, plan, 0, actor_account_id: project.account_id, claimed_actor_id: "previous", submission_auth: "token")
    report(project, plan, 0, shard_attempt: 1, actor_account_id: 0, claimed_actor_id: "", submission_auth: "token")
    assert {:ok, run} = Tests.get_test(plan.id)
    assert run.actor_account_id == 0
    assert run.claimed_actor_id == ""
    assert run.submission_auth == "token"
  end

  test "build lookups are project-scoped and include derived immutable runs", %{project: project} do
    %{plan: plan} = plan(project, 1)
    build_id = UUIDv7.generate()
    gradle_id = UUIDv7.generate()
    report(project, plan, 0, build_run_id: build_id, gradle_build_id: gradle_id)
    assert {:ok, %{id: id}} = Tests.get_latest_test_by_build_run_id(build_id, project.id)
    assert id == plan.id
    assert {:ok, %{id: ^id}} = Tests.get_latest_test_by_gradle_build_id(gradle_id, project.id)
    assert {:error, :not_found} = Tests.get_latest_test_by_build_run_id(build_id, project.id + 1)
    assert {:error, :not_found} = Tests.get_latest_test_by_gradle_build_id(gradle_id, project.id + 1)
  end

  test "current shard bundles retain their upload IDs through parsing and retries", %{project: project} do
    %{plan: plan} = plan(project)
    first_id = String.upcase(UUIDv7.generate())
    second_id = String.upcase(UUIDv7.generate())
    report(project, plan, 0, id: first_id, status: "processing")
    report(project, plan, 0, id: plan.id, source_test_run_id: first_id)
    report(project, plan, 1, id: second_id)
    assert {:ok, run} = Tests.get_test(plan.id)
    assert Tests.result_bundle_run_ids(run) == [first_id, second_id]
    retry_id = String.upcase(UUIDv7.generate())
    report(project, plan, 0, id: retry_id, shard_attempt: 1)
    assert Tests.result_bundle_run_ids(run) == [retry_id, second_id]
  end

  test "first and final reports share the plan ID without reading an existing run", %{project: project} do
    %{plan: plan} = plan(project)
    reject(ClickHouseRepo, :one, 1)
    assert {:ok, first} = report(project, plan, 0)
    assert {:ok, last} = report(project, plan, 1)
    assert first.id == plan.id
    assert last.id == plan.id
    assert IngestRepo.aggregate(from(t in Test, where: t.id == ^plan.id), :count) == 0
    assert IngestRepo.aggregate(from(r in TestReport, where: r.id == ^plan.id), :count) == 2
  end

  test "the final aggregate comes from all shard observations, not a stored merge", %{project: project} do
    %{plan: plan} = plan(project)
    assert {:ok, _} = report(project, plan, 0, duration: 900)
    assert {:ok, %{status: "in_progress"}} = Tests.get_test(plan.id)
    assert {:ok, _} = report(project, plan, 1, duration: 1200)
    assert {:ok, %{status: "success", duration: 1200, reporting_version: 1}} = Tests.get_test(plan.id)
    assert IngestRepo.aggregate(from(t in Test, where: t.id == ^plan.id), :count) == 0
  end

  test "duplicates do not multiply run counts, stress totals or balance samples", %{project: project} do
    %{plan: plan} = plan(project)
    stress = %{mode: "report", outcome: "passed", new_count: 3, stressed_count: 2}
    assert {:ok, _} = report(project, plan, 0, stress_new_tests: stress)
    assert {:ok, _} = report(project, plan, 0, stress_new_tests: stress)
    assert {:ok, _} = report(project, plan, 1)
    assert {:ok, test} = Tests.get_test(plan.id)
    assert test.status == "success"
    assert test.stress_new_count == 3
    assert test.stress_stressed_count == 2
    {runs, meta} = Tests.list_test_runs(%{filters: [%{field: :project_id, op: :==, value: project.id}]})
    assert meta.total_count == 1
    assert Enum.map(runs, & &1.id) == [plan.id]
    assert length(Analytics.shard_metrics(plan.id)) == 2
  end

  test "a late processing replay cannot overwrite terminal results", %{project: project} do
    %{plan: plan} = plan(project)
    report(project, plan, 0)
    report(project, plan, 1)
    report(project, plan, 0, status: "processing")
    assert {:ok, %{status: "success"}} = Tests.get_test(plan.id)
  end

  test "producer attempts and revisions override arrival order", %{project: project} do
    %{plan: plan} = plan(project)
    report(project, plan, 0, status: "success", shard_attempt: 2)
    report(project, plan, 1)
    report(project, plan, 0, status: "failure", shard_attempt: 1, shard_report_revision: 99)
    assert {:ok, %{status: "success"}} = Tests.get_test(plan.id)
    report(project, plan, 0, status: "failure", shard_attempt: 2, shard_report_revision: 1)
    assert {:ok, %{status: "failure"}} = Tests.get_test(plan.id)
    report(project, plan, 0, status: "success", shard_attempt: 2, shard_report_revision: 0)
    assert {:ok, %{status: "failure"}} = Tests.get_test(plan.id)
  end

  test "a parsed result supersedes failed processing regardless of arrival order", %{project: project} do
    %{plan: plan} = plan(project)
    report(project, plan, 0)
    report(project, plan, 1)
    report(project, plan, 0, status: "failed_processing")
    assert {:ok, %{status: "success"}} = Tests.get_test(plan.id)
  end

  test "one-shard plans preserve processing and skipped statuses", %{project: project} do
    %{plan: plan} = plan(project, 1)
    report(project, plan, 0, status: "processing")
    assert {:ok, %{status: "processing"}} = Tests.get_test(plan.id)
    report(project, plan, 0, status: "skipped")
    assert {:ok, %{status: "skipped"}} = Tests.get_test(plan.id)
  end

  test "metadata from the initial report survives sparse terminal uploads", %{project: project} do
    %{plan: plan} = plan(project)
    report(project, plan, 0, status: "processing", scheme: "Known", git_branch: "main")
    report(project, plan, 0, scheme: nil, git_branch: nil)
    report(project, plan, 1, scheme: nil, git_branch: nil)
    assert {:ok, %{scheme: "Known", git_branch: "main"}} = Tests.get_test(plan.id)
  end

  test "new attempts and terminal corrections clear previous execution metadata", %{project: project} do
    previous = [
      status: "failure",
      is_flaky: true,
      scheme: "Previous",
      git_branch: "previous",
      ci_provider: "github",
      only_test_identifiers: ["Tests/old"],
      skip_test_identifiers: ["Tests/skipped"],
      coverage_evidence_status: "collected",
      stress_new_tests: %{mode: "report", outcome: "disagreed", new_count: 3, stressed_count: 2, known_count: 10}
    ]

    for version <- [[shard_attempt: 1], [shard_report_revision: 1]] do
      %{plan: plan} = plan(project, 1)
      report(project, plan, 0, previous)

      report(
        project,
        plan,
        0,
        version ++
          [
            scheme: nil,
            git_branch: nil,
            ci_provider: nil,
            coverage_evidence_status: "",
            only_test_identifiers: [],
            skip_test_identifiers: [],
            stress_new_tests: %{mode: "", outcome: "", new_count: 0, stressed_count: 0, known_count: 0}
          ]
      )

      report(project, plan, 0, previous)
      assert {:ok, run} = Tests.get_test(plan.id)
      assert run.status == "success"
      refute run.is_flaky
      assert run.scheme == ""
      assert run.git_branch == ""
      assert run.ci_provider == nil
      assert run.only_test_identifiers == []
      assert run.skip_test_identifiers == []
      assert run.coverage_evidence_status == ""
      assert run.stress_mode == ""
      assert run.stress_outcome == ""
      assert run.stress_new_count == 0
      assert run.stress_stressed_count == 0
      assert run.stress_known_count == 0
    end
  end

  test "a new processing attempt cannot inherit metadata from an older terminal report", %{project: project} do
    %{plan: plan} = plan(project, 1)
    report(project, plan, 0, shard_report_revision: 99, scheme: "Previous", only_test_identifiers: ["Tests/old"])
    report(project, plan, 0, shard_attempt: 1, status: "processing", scheme: nil)
    assert {:ok, run} = Tests.get_test(plan.id)
    assert run.status == "processing"
    assert run.scheme == ""
    assert run.only_test_identifiers == []
  end

  test "a higher processing revision cannot supply metadata to the selected terminal revision", %{project: project} do
    %{plan: plan} = plan(project, 1)
    report(project, plan, 0, scheme: nil)
    report(project, plan, 0, shard_report_revision: 99, status: "processing", scheme: "Wrong")
    assert {:ok, run} = Tests.get_test(plan.id)
    assert run.status == "success"
    assert run.scheme == ""
  end

  test "facts are written before the immutable receipt and replay uses stable fact IDs", %{project: project} do
    %{plan: plan} = plan(project, 1)
    modules = [%{name: "Tests", status: "success", test_cases: [%{name: "test_one", status: "success", duration: 10}]}]

    expect(IngestRepo, :insert_all, 2, fn TestReport, rows ->
      assert IngestRepo.aggregate(from(r in TestCaseRun, where: r.test_run_id == ^plan.id), :count) >= 1
      Mimic.call_original(IngestRepo, :insert_all, [TestReport, rows])
    end)

    assert {:ok, first} = report(project, plan, 0, test_modules: modules)
    [first_run] = first.test_case_runs
    assert {:ok, second} = report(project, plan, 0, test_modules: modules)
    [second_run] = second.test_case_runs
    assert first_run.id == second_run.id
    assert {:ok, %{id: id}} = Tests.get_test_case_run_by_id(first_run.id)
    assert id == first_run.id

    assert ClickHouseRepo.aggregate(from(m in TestModuleRun, where: m.test_run_id == ^plan.id, select: m.id), :count, :id) >=
             1
  end

  @tag capture_log: true
  test "xcresult replay identities ignore extraction paths and keep UUIDv7 facts", %{project: project} do
    %{plan: plan} = plan(project, 1)

    [first, replay] =
      for root <- ["/tmp/first", "/tmp/replay"] do
        assert {:ok, run} =
                 report(project, plan, 0,
                   xcode_coverage: %{path: root <> "/coverage.ndjson"},
                   test_modules: [
                     %{
                       name: "Tests",
                       status: "success",
                       test_cases: [
                         %{
                           name: "test_one",
                           status: "success",
                           duration: 10,
                           crash_report: %{file_path: root <> "/report.ips", exception_type: "EXC_CRASH"}
                         }
                       ]
                     }
                   ]
                 )

        run
      end

    assert [first_case] = first.test_case_runs
    assert [replay_case] = replay.test_case_runs
    assert first_case.id == replay_case.id
    assert Tuist.UUIDv7.valid?(first_case.id)

    assert {:ok, %{rows: [[1]]}} =
             ClickHouseRepo.query(
               "SELECT uniqExact(fact_set_id) FROM shard_test_reports WHERE project_id = {project_id:Int64}",
               %{project_id: project.id}
             )
  end

  test "dictionary-derived module and suite ordering cannot change fact identities", %{project: project} do
    %{plan: plan} = plan(project, 1)

    [first, replay] =
      for names <- [["B", "A"], ["A", "B"]] do
        modules =
          Enum.map(names, fn name ->
            %{
              name: name,
              status: "success",
              test_suites: Enum.map(names, &%{name: &1, status: "success", duration: 10}),
              test_cases:
                Enum.map(["A", "B"], fn suite ->
                  %{name: "test_one", test_suite_name: suite, status: "success", duration: 10}
                end)
            }
          end)

        assert {:ok, run} = report(project, plan, 0, test_modules: modules)
        run
      end

    assert Enum.map(first.test_case_runs, & &1.id) == Enum.map(replay.test_case_runs, & &1.id)

    assert {:ok, %{rows: [[1]]}} =
             ClickHouseRepo.query(
               "SELECT uniqExact(fact_set_id) FROM shard_test_reports WHERE project_id = {project_id:Int64}",
               %{project_id: project.id}
             )

    assert %{total_count: 4} = Tuist.Tests.Analytics.get_test_run_metrics(replay)
  end

  test "replays do not multiply children or collapse genuine identical failures", %{project: project} do
    %{plan: plan} = plan(project, 1)
    failure = %{message: "failed", path: "Tests.swift", line_number: 1}
    repetition = %{repetition_number: 1, name: "test_one", status: "failure", duration: 10}
    argument = %{name: "x", status: "failure", duration: 10, failures: [failure, failure], repetitions: [repetition]}

    modules = [
      %{
        name: "Tests",
        status: "failure",
        test_cases: [
          %{
            name: "test_one",
            status: "failure",
            duration: 10,
            failures: [failure, failure],
            repetitions: [repetition],
            arguments: [argument],
            attachments: [%{file_name: "log.txt", repetition_number: 1}]
          }
        ]
      }
    ]

    for _ <- 1..2, do: report(project, plan, 0, status: "failure", test_modules: modules)

    {[loaded], _} =
      Tests.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: plan.id}]},
        preload: [:failures, :repetitions, :attachments, arguments: [:failures, :repetitions]]
      )

    assert length(loaded.failures) == 4
    assert length(loaded.repetitions) == 2
    assert length(loaded.attachments) == 1
    assert [arg] = loaded.arguments
    assert length(arg.failures) == 2
    assert length(arg.repetitions) == 1
    assert length(Tests.list_test_case_run_arguments([loaded.id])) == 1
  end

  test "runner job lists include immutable runs", %{project: project} do
    %{plan: plan} = plan(project, 1)
    report(project, plan, 0, ci_provider: "github", ci_run_id: "123")
    assert [%{id: id}] = Jobs.list_runner_test_runs([project], 123)
    assert id == plan.id
  end

  test "repeated case identities stay distinct while replaying their facts is stable", %{project: project} do
    %{plan: plan} = plan(project, 1)

    modules = [
      %{
        name: "Tests",
        status: "success",
        test_cases: [
          %{name: "test_one", status: "failure", duration: 10},
          %{name: "test_one", status: "success", duration: 20}
        ]
      }
    ]

    assert {:ok, first} = report(project, plan, 0, test_modules: modules)
    assert {:ok, second} = report(project, plan, 0, test_modules: modules)
    assert Enum.sort(Enum.map(first.test_case_runs, & &1.id)) == Enum.sort(Enum.map(second.test_case_runs, & &1.id))
    {cases, meta} = Tests.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: plan.id}]})
    assert meta.total_count == 2
    assert Enum.sort(Enum.map(cases, & &1.status)) == ["failure", "success"]
  end

  test "repetition flakiness is present in the immutable report before followups", %{project: project} do
    %{plan: plan} = plan(project, 1)

    repetitions = [
      %{repetition_number: 0, status: "failure", duration: 10},
      %{repetition_number: 1, status: "success", duration: 10}
    ]

    modules = [
      %{
        name: "Tests",
        status: "success",
        test_cases: [
          %{name: "test_one", status: "success", duration: 20, repetitions: repetitions}
        ]
      }
    ]

    assert {:ok, %{is_flaky: true}} = report(project, plan, 0, test_modules: modules)
    assert {:ok, %{is_flaky: true}} = Tests.get_test(plan.id)
  end

  test "current run details select the winning report's facts, not older attempts", %{project: project} do
    %{plan: plan} = plan(project, 1)
    failed = [%{name: "Tests", status: "failure", test_cases: [%{name: "test_one", status: "failure", duration: 10}]}]
    passed = [%{name: "Tests", status: "success", test_cases: [%{name: "test_one", status: "success", duration: 20}]}]
    report(project, plan, 0, shard_attempt: 2, test_modules: passed)
    report(project, plan, 0, shard_attempt: 1, status: "failure", test_modules: failed)
    assert {:ok, run} = Tests.get_test(plan.id)
    assert run.status == "success"
    {cases, meta} = Tests.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: plan.id}]})
    assert meta.total_count == 1
    assert [%{status: "success", duration: 20}] = cases
    assert Tests.get_test_run_failures_count(plan.id) == 0
    assert %{total_count: 1, failed_count: 0} = Tuist.Tests.Analytics.get_test_run_metrics(plan.id)
    assert %{passed: 1, failed: 0, skipped: 0} = Tuist.Tests.Analytics.test_case_counts(project.id, [run])
    assert [%{total_tests: 1}] = Tuist.Tests.Analytics.test_runs_metrics(project.id, [run])
    {modules, _} = Tests.list_test_module_runs(%{filters: [%{field: :test_run_id, op: :==, value: plan.id}]})
    assert [%{status: "success"}] = modules

    reject(Tests, :get_test, 1)
    reject(Tests, :get_test, 2)
    reject_parent_lookups()
    assert Tests.get_test_run_failures_count(run) == 0
    assert %{total_count: 1, failed_count: 0} = Tuist.Tests.Analytics.get_test_run_metrics(run)

    {cases, _} =
      Tests.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: plan.id}]}, test_run: run)

    assert [%{status: "success", duration: 20}] = cases
  end

  test "unpublished facts are absent from current-run views", %{project: project} do
    %{plan: plan} = plan(project, 1)
    modules = [%{name: "Tests", status: "success", test_cases: [%{name: "test_one", status: "success", duration: 10}]}]
    expect(IngestRepo, :insert_all, fn TestReport, _ -> raise "report unavailable" end)
    assert_raise RuntimeError, "report unavailable", fn -> report(project, plan, 0, test_modules: modules) end
    assert IngestRepo.aggregate(from(r in TestCaseRun, where: r.test_run_id == ^plan.id), :count) == 1
    assert IngestRepo.aggregate(from(r in TestCaseRun.query(), where: r.test_run_id == ^plan.id), :count) == 0
  end

  test "a core fact write failure cannot publish the report", %{project: project} do
    %{plan: plan} = plan(project, 1)
    modules = [%{name: "Tests", status: "success", test_cases: []}]
    expect(IngestRepo, :query, fn _, _, _ -> {:error, :unavailable} end)
    reject(IngestRepo, :insert_all, 2)
    assert_raise MatchError, fn -> report(project, plan, 0, test_modules: modules) end
    assert {:error, :not_found} = Tests.get_test(plan.id)
  end

  test "creation flags do not change an existing plan's reporting contract", %{project: project} do
    %{plan: plan} = plan(project)
    stub(FeatureFlags, :immutable_shard_reports_enabled?, fn _ -> false end)
    report(project, plan, 0)
    report(project, plan, 1)
    assert {:ok, %{reporting_version: 1, status: "success"}} = Tests.get_test(plan.id)
    assert %{plan: %{reporting_version: 0}} = plan(project)
  end

  test "invalid indexes, revisions and cross-project plans are rejected", %{project: project} do
    %{plan: plan} = plan(project)
    assert {:error, :invalid_shard_report} = report(project, plan, -1)
    assert {:error, :invalid_shard_report} = report(project, plan, 2)
    assert {:error, :invalid_shard_report} = report(project, plan, 0, shard_attempt: -1)
    other = ProjectsFixtures.project_fixture()
    assert {:error, :not_found} = report(other, plan, 0)
  end

  defp reject_parent_lookups do
    stub(ClickHouseRepo, :one, fn query ->
      refute match?(%Ecto.Query{from: %{source: {_table, Test}}}, query)
      Mimic.call_original(ClickHouseRepo, :one, [query])
    end)
  end

  defp plan(project, count \\ 2) do
    Shards.create_shard_plan(project, %{
      reference: "plan-#{System.unique_integer([:positive])}",
      modules: Enum.map(1..count, &"Tests#{&1}"),
      shard_total: count
    })
  end

  defp report(project, plan, index, overrides \\ []) do
    attrs = %{
      id: Ecto.UUID.generate(),
      project_id: project.id,
      account_id: project.account_id,
      shard_plan_id: plan.id,
      shard_index: index,
      status: "success",
      duration: 100,
      is_ci: true,
      scheme: "App",
      git_branch: "feature",
      ran_at: NaiveDateTime.utc_now(),
      test_modules: []
    }

    Tests.create_test(Map.merge(attrs, Map.new(overrides)))
  end
end
