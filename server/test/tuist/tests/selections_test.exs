defmodule Tuist.Tests.SelectionsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Tests.Selections
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures
  alias TuistTestSupport.Fixtures.TestSelectionFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture()}
  end

  # An impact run that selected `test_load()` (impacted) and the new
  # `test_gone()` (no evidence) and skipped the baseline's `test_refresh()`
  # and `test_reset()`. Its test run ran `test_load()` (passed) but never
  # reported `test_gone()`. A two-shard plan put each selected test's suite
  # on its own shard.
  defp run(project, attrs \\ []) do
    [load, refresh, reset, gone] = for _ <- 1..4, do: UUIDv7.generate()

    TestSelectionFixtures.baseline_fixture(
      project_id: project.id,
      tests: [
        %{
          test_case_id: load,
          module_name: "SearchTests",
          suite_name: "SearchViewModelTests",
          name: "test_load()",
          duration: 300
        },
        %{
          test_case_id: refresh,
          module_name: "AuthTests",
          suite_name: "SessionTests",
          name: "test_refresh()",
          duration: 500
        },
        %{test_case_id: reset, module_name: "AuthTests", suite_name: "SessionTests", name: "test_reset()", duration: 200},
        %{
          test_case_id: UUIDv7.generate(),
          module_name: "BillingTests",
          suite_name: "InvoiceTests",
          name: "test_total()",
          duration: 1000
        }
      ]
    )

    run =
      TestSelectionFixtures.run_fixture(
        Keyword.merge(
          [
            project_id: project.id,
            requested_modules: ["SearchTests", "AuthTests"],
            skipped_modules: %{"BillingTests" => 3, "ProfileTests" => 1},
            rule_trace: [%{rule: "unaffected", selected: 0, skipped: 2, verdict: "done"}],
            selected: [
              %{
                test_case_id: load,
                module_name: "SearchTests",
                suite_name: "SearchViewModelTests",
                name: "test_load()",
                matched_path: "Sources/Search/Search.swift"
              },
              %{
                test_case_id: gone,
                module_name: "SearchTests",
                suite_name: "SearchGoneTests",
                name: "test_gone()",
                reason: "no_evidence"
              }
            ]
          ],
          attrs
        )
      )

    {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, test_impact_run_id: run.id)

    RunsFixtures.test_case_run_fixture(
      project_id: project.id,
      test_run_id: test_run.id,
      test_case_id: load,
      module_name: "SearchTests",
      suite_name: "SearchViewModelTests",
      name: "test_load()",
      status: 0
    )

    plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, granularity: "suite", test_impact_run_id: run.id)

    for {suite, index} <- [{"SearchViewModelTests", 0}, {"SearchGoneTests", 1}] do
      ShardsFixtures.shard_plan_test_suite_fixture(
        shard_plan_id: plan.id,
        project_id: project.id,
        shard_index: index,
        module_name: "SearchTests",
        test_suite_name: suite,
        estimated_duration_ms: 400
      )
    end

    %{run: run, test_run: test_run, plan: plan}
  end

  describe "list_runs/3" do
    test "lists the period's impact runs a test run reported, newest first, filtered, with that test run", %{
      project: project
    } do
      older =
        TestSelectionFixtures.run_fixture(
          project_id: project.id,
          commit_sha: "older",
          build_context: %{"scheme" => "Core"},
          outcome: "fallback",
          reason: "no_baseline",
          baseline_sha: nil,
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
        )

      newer = TestSelectionFixtures.run_fixture(project_id: project.id, commit_sha: "newer")
      TestSelectionFixtures.run_fixture(project_id: project.id, commit_sha: "orphan")

      before_period =
        TestSelectionFixtures.run_fixture(
          project_id: project.id,
          commit_sha: "before",
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3, :day)
        )

      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, test_impact_run_id: older.id)
      {:ok, newer_test_run} = RunsFixtures.test_fixture(project_id: project.id, test_impact_run_id: newer.id)
      {:ok, _test_run} = RunsFixtures.test_fixture(project_id: project.id, test_impact_run_id: before_period.id)
      period = {DateTime.add(DateTime.utc_now(), -1, :day), DateTime.add(DateTime.utc_now(), 60, :second)}

      {rows, meta} = Selections.list_runs(project.id, period)

      assert Enum.map(rows, &{&1.commit_sha, &1.test_run_id}) == [
               {"newer", newer_test_run.id},
               {"older", test_run.id}
             ]

      assert meta.total_count == 2
      assert {[%{commit_sha: "older"}], _meta} = Selections.list_runs(project.id, period, search: "core")
    end
  end

  describe "get_run/2 and run_for_test_run/2" do
    test "find an impact run by its id and by the test run that points to it", %{project: project} do
      run = TestSelectionFixtures.run_fixture(project_id: project.id)
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, test_impact_run_id: run.id)
      id = run.id

      assert {:ok, %{id: ^id}} = Selections.get_run(project.id, id)
      assert {:error, :not_found} = Selections.get_run(project.id, UUIDv7.generate())
      assert {:error, :not_found} = Selections.get_run(project.id, "not-a-uuid")
      assert {:ok, %{id: ^id}} = Selections.run_for_test_run(project.id, test_run)
      assert {:ok, %{id: ^id}} = Selections.run_for_test_run(project.id, test_run.id)
      assert {:error, :none} = Selections.run_for_test_run(project.id, %{test_impact_run_id: nil})
      assert {:error, :expired} = Selections.run_for_test_run(project.id, %{test_impact_run_id: UUIDv7.generate()})
    end
  end

  describe "run_summary/2" do
    test "adds up the run's tests, those hashing skipped, the skipped tests' baseline duration and the selected tests that never reported",
         %{project: project} do
      %{run: run, test_run: test_run} = run(project)
      summary = Selections.run_summary(run, test_run.id)

      assert summary.requested == 8
      assert summary.selected == 2
      assert summary.skipped == 6
      assert summary.unaffected == 2
      assert summary.module_skipped == 4
      assert summary.skipped_modules == 2
      assert summary.modules == 4
      assert summary.skip_rate == 75.0
      # The not-affected AuthTests and BillingTests, which hashing skipped.
      assert summary.skipped_duration == 1700
      assert summary.not_run == 1
      assert summary.reported

      assert summary.reasons == [
               %{decision: "selected", reason: "impacted", count: 1},
               %{decision: "selected", reason: "no_evidence", count: 1},
               %{decision: "skipped", reason: "unaffected", count: 2}
             ]
    end
  end

  describe "run_tests/3" do
    test "lists the selected tests, then the skipped ones derived from the baseline, those in modules hashing skipped included",
         %{project: project} do
      %{run: run, test_run: test_run} = run(project)
      {rows, meta} = Selections.run_tests(run, test_run.id)

      assert Enum.map(rows, &{&1.name, &1.decision, &1.outcome, &1.shard_index, &1.duration}) == [
               {"test_gone()", "selected", nil, 1, 0},
               {"test_load()", "selected", "success", 0, 300},
               {"test_refresh()", "skipped", nil, nil, 500},
               {"test_reset()", "skipped", nil, nil, 200},
               {"test_total()", "skipped", nil, nil, 1000}
             ]

      assert meta.total_count == 5
    end

    test "filters by decision, reason, shard and search, and sorts by duration", %{project: project} do
      %{run: run, test_run: test_run} = run(project)

      assert {[%{name: "test_gone()"}], _meta} = Selections.run_tests(run, test_run.id, shard: 1)
      assert {[%{name: "test_gone()"}], _meta} = Selections.run_tests(run, test_run.id, reason: "no_evidence")
      assert {rows, _meta} = Selections.run_tests(run, test_run.id, decision: "skipped")
      assert Enum.map(rows, & &1.name) == ["test_refresh()", "test_reset()", "test_total()"]
      assert {[%{name: "test_total()"}], _meta} = Selections.run_tests(run, test_run.id, reason: "module_skipped")
      assert {[%{name: "test_load()"}], _meta} = Selections.run_tests(run, test_run.id, search: "load")

      assert {rows, _meta} = Selections.run_tests(run, test_run.id, sort_by: "duration", sort_order: "desc")
      assert Enum.map(rows, & &1.duration) == [1000, 500, 300, 200, 0]
    end

    test "lists only the selected tests without a baseline", %{project: project} do
      run =
        TestSelectionFixtures.run_fixture(
          project_id: project.id,
          baseline_sha: nil,
          selected: [%{name: "test_a()", reason: "no_evidence"}]
        )

      assert {[%{name: "test_a()", decision: "selected"}], _meta} = Selections.run_tests(run, UUIDv7.generate())
    end

    test "lists only the tests of modules hashing skipped when it left no module to decide", %{project: project} do
      %{run: run, test_run: test_run} =
        run(project, requested_modules: [], selected: [], skipped_modules: %{"SearchTests" => 4}, rule_trace: [])

      {tests, _meta} = Selections.run_tests(run, test_run.id)
      assert tests != []
      assert Enum.all?(tests, &(&1.module_name == "SearchTests" and &1.reason == "module_skipped"))
      assert {[], _meta} = Selections.run_tests(run, test_run.id, reason: "unaffected")

      assert %{requested: 4, module_skipped: 4, unaffected: 0, skip_rate: 100.0} =
               Selections.run_summary(run, test_run.id)
    end
  end

  describe "a fallback that found its baseline" do
    test "lists the requested modules' baseline tests as ran under its reason and saves the hash-skipped ones' time",
         %{project: project} do
      %{run: run, test_run: test_run} =
        run(project,
          outcome: "fallback",
          reason: "tracked_file_changed",
          matched_path: "Package.resolved",
          selected: [],
          rule_trace: [%{rule: "tracked_files", selected: 0, skipped: 0, verdict: "abort"}],
          requested_count: 7,
          selected_count: 3,
          skipped_count: 4
        )

      assert Selections.counted_fallback?(run)
      assert Selections.selection?(run)
      {rows, _meta} = Selections.run_tests(run, test_run.id)

      assert Enum.map(rows, &{&1.name, &1.decision, &1.reason, &1.matched_path}) == [
               {"test_refresh()", "selected", "tracked_file_changed", "Package.resolved"},
               {"test_reset()", "selected", "tracked_file_changed", "Package.resolved"},
               {"test_load()", "selected", "tracked_file_changed", "Package.resolved"},
               {"test_total()", "skipped", "module_skipped", ""}
             ]

      assert {[_, _, _], _meta} = Selections.run_tests(run, test_run.id, reason: "tracked_file_changed")
      # Derived rows come first here, and their ids must still be UUID strings.
      assert Enum.all?(rows, &match?({:ok, _}, Ecto.UUID.cast(&1.test_case_id)))
      assert Enum.all?(rows, &(byte_size(&1.test_case_id) == 36))
      assert Selections.run_summary(run, test_run.id).skipped_duration == 1000
    end
  end

  describe "get_run_test/3" do
    test "returns one of the run's tests with its outcome", %{project: project} do
      %{run: run, test_run: test_run} = run(project)
      {[test], _meta} = Selections.run_tests(run, test_run.id, search: "load")
      {[skipped | _], _meta} = Selections.run_tests(run, test_run.id, decision: "skipped")

      assert {:ok, %{name: "test_load()", outcome: "success"}} =
               Selections.get_run_test(run, test_run.id, test.test_case_id)

      assert {:ok, %{decision: "skipped", reason: "unaffected"}} =
               Selections.get_run_test(run, test_run.id, skipped.test_case_id)

      assert {:error, :not_found} = Selections.get_run_test(run, test_run.id, UUIDv7.generate())
    end
  end

  describe "run_shards/3 and run_targets/1" do
    test "add up the run's tests per shard and per module", %{project: project} do
      %{run: run, test_run: test_run, plan: plan} = run(project)

      assert Selections.shard_plan(run).id == plan.id

      assert Selections.run_shards(run, plan, test_run.id) == [
               %{shard_index: 0, planned: 1, estimated_duration: 400, ran: 1, failed: 0, not_run: 0},
               %{shard_index: 1, planned: 1, estimated_duration: 400, ran: 0, failed: 0, not_run: 1}
             ]

      assert [
               %{module_name: "SearchTests", requested: 2, selected: 2, skipped: 0},
               %{module_name: "AuthTests", requested: 2, selected: 0, skipped: 2, estimated_skipped_duration: 700}
             ] = Selections.run_targets(run)

      assert Selections.skipped_modules(run) == [
               %{module_name: "BillingTests", tests: 3},
               %{module_name: "ProfileTests", tests: 1}
             ]
    end
  end

  describe "changed files" do
    test "list a run's diff with tracked files and the tests each selected", %{project: project} do
      %{run: run} = run(project)

      TestSelectionFixtures.diff_fixture(
        project_id: project.id,
        changed_files_count: 4,
        changed_files: [
          %{path: "docs/README.md"},
          %{path: "Sources/Search/Search.swift"},
          %{path: "App/Project.swift"}
        ]
      )

      diff = Selections.get_diff(run)
      assert diff.changed_files_count == 4

      {rows, meta} = Selections.changed_files(project, run, diff)

      assert Enum.map(rows, &{&1.path, &1.tracked, &1.selected_tests_count}) == [
               {"Sources/Search/Search.swift", false, 1},
               {"App/Project.swift", true, 0},
               {"docs/README.md", false, 0}
             ]

      assert meta.total_count == 3
      assert {[%{path: "App/Project.swift"}], _meta} = Selections.changed_files(project, run, diff, tracked: true)
      assert {[%{path: "docs/README.md"}], _meta} = Selections.changed_files(project, run, diff, search: "readme")
      assert Selections.get_diff(%{run | baseline_sha: nil}) == nil
    end
  end

  describe "run_all?/1, counted_by_module?/1 and module_counts/1" do
    test "tell a fallback that runs every test from one to selective testing, and count its modules" do
      run = %Tuist.TestImpactAnalysis.Run{
        outcome: "fallback",
        reason: "tracked_file_changed",
        requested_modules: ["A", "B", "C"],
        skipped_modules: %{"D" => 0}
      }

      refute Selections.run_all?(run)
      assert Selections.run_all?(%{run | reason: "no_baseline"})
      refute Selections.run_all?(%{run | outcome: "selected", reason: ""})
      assert Selections.counted_by_module?(run)
      refute Selections.counted_by_module?(%{run | requested_count: 19})
      refute Selections.counted_by_module?(%{run | reason: "no_baseline"})
      assert Selections.module_counts(run) == %{ran: 3, total: 4}
      assert Selections.module_skip_rate(run) == 25.0
      assert Selections.skip_rate(run) == 25.0
      assert Selections.skip_rate(%{run | reason: "no_baseline"}) == 0.0
    end
  end

  describe "analytics/2" do
    test "adds up the period's impact runs that a test run reported", %{project: project} do
      run(project)
      fallback = TestSelectionFixtures.run_fixture(project_id: project.id, outcome: "fallback", reason: "no_baseline")
      RunsFixtures.test_fixture(project_id: project.id, test_impact_run_id: fallback.id)
      TestSelectionFixtures.run_fixture(project_id: project.id, skipped_count: 5, selected: [%{name: "test_orphan()"}])

      now = DateTime.utc_now()
      analytics = Selections.analytics(project.id, {DateTime.add(now, -7, :day), DateTime.add(now, 60, :second)})

      assert analytics.totals.runs == 2
      assert analytics.totals.fallbacks == 1
      assert analytics.totals.selected == 2
      assert analytics.totals.skipped == 6
      # The mean of the runs' skip rates: 75% and the fallback's 0%, since it ran every test.
      assert analytics.totals.skip_rate == 37.5
      assert Enum.max(analytics.skip_rates) == 37.5
      assert Enum.sum(analytics.selected) == 2
      assert length(analytics.dates) == 8
    end
  end
end
