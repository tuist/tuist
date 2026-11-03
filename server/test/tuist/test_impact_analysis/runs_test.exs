defmodule Tuist.TestImpactAnalysis.RunsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Shards
  alias Tuist.TestImpactAnalysis.Runs
  alias Tuist.TestImpactAnalysis.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @sources ~w(Sources/Math.swift Sources/Sub.swift Sources/Strings.swift Sources/Core.swift)

  # The baseline c1 ran AppTests (MathTests: testAdd() and testSub();
  # StringTests: testUpper(); SumTests: sum(), a Swift Testing test without
  # evidence) and CoreTests (CoreSuite: testCore()), each XCTest test over its
  # own source file. c2 is the commit checked out on top of it.
  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    repository_id =
      CoverageFixtures.seed_history(account, [
        CoverageFixtures.commit("c1", [], 0),
        CoverageFixtures.commit("c2", ["c1"], 1)
      ])

    CoverageFixtures.seed_listing(account, "c1", @sources ++ ["Package.resolved"])

    test_case = fn name, suite, duration ->
      %{name: name, test_suite_name: suite, status: "success", duration: duration}
    end

    scope = fn module, suite, name, file ->
      %{kind: "test", module: module, suite: suite, name: name, files: [file], lines: [[1, 1]]}
    end

    run =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        Enum.map(@sources, &CoverageFixtures.file(&1, [1])),
        %{
          git_commit_sha: "c1",
          test_modules: [
            %{
              name: "AppTests",
              status: "success",
              duration: 1,
              test_cases: [
                test_case.("testAdd()", "MathTests", 50),
                test_case.("testSub()", "MathTests", 50),
                test_case.("testUpper()", "StringTests", 50),
                test_case.("sum()", "SumTests", 10)
              ]
            },
            %{name: "CoreTests", status: "success", duration: 1, test_cases: [test_case.("testCore()", "CoreSuite", 50)]}
          ],
          coverage_evidence: %{
            paths: @sources,
            scopes: [
              scope.("AppTests", "MathTests", "testAdd()", 0),
              scope.("AppTests", "MathTests", "testSub()", 1),
              scope.("AppTests", "StringTests", "testUpper()", 2),
              scope.("CoreTests", "CoreSuite", "testCore()", 3)
            ]
          }
        }
      )

    %{project: project, run: run, repository_id: repository_id}
  end

  defp params(attrs \\ %{}) do
    Map.merge(
      %{
        build_system: "xcode",
        head_sha: "c2",
        baseline_sha: "c1",
        git_branch: "feature",
        changed_files: [%{path: "Sources/Math.swift", status: "M", blob: "new", affected_modules: ["AppTests"]}],
        xcode: %{scheme: "App"}
      },
      attrs
    )
  end

  defp selected(project, run) do
    project.id
    |> Storage.list_run_tests(run.id)
    |> Enum.map(&{&1.module_name, &1.suite_name, &1.name, &1.reason})
  end

  describe "create/2" do
    test "selects the impacted tests and those without evidence, and skips the rest", %{project: project, run: baseline} do
      assert {:ok, %{run: run, skipped_tests: skip}} = Runs.create(project, params())

      assert run.outcome == "selected"
      assert run.commit_sha == "c2"
      assert run.baseline_run_ids == [baseline.id]
      assert {run.requested_count, run.selected_count, run.skipped_count} == {5, 2, 3}
      assert run.rules_version == "1"
      assert List.last(run.rule_trace).rule == "unaffected"
      assert run.build_context == %{"scheme" => "App"}

      assert selected(project, run) == [
               {"AppTests", "MathTests", "testAdd()", "impacted"},
               {"AppTests", "SumTests", "sum()", "no_evidence"}
             ]

      assert skip == [
               %{module: "AppTests", suite: "MathTests", name: "testSub()"},
               %{module: "AppTests", suite: "StringTests", name: "testUpper()"},
               %{module: "CoreTests"}
             ]

      assert {:ok, %{changed_files_count: 1}} = Storage.get_diff(project.id, "c2", "c1")
    end

    test "reuses the stored diff when the client sends none", %{project: project} do
      {:ok, _} = Runs.create(project, params())

      assert {:ok, %{run: %{outcome: "selected", selected_count: 2}}} =
               Runs.create(project, Map.delete(params(), :changed_files))
    end

    test "doesn't store a dirty checkout's diff", %{project: project} do
      assert {:ok, %{run: %{outcome: "selected", dirty: true}}} = Runs.create(project, params(%{dirty: true}))
      assert Storage.get_diff(project.id, "c2", "c1") == {:error, :not_found}

      assert {:ok, %{run: %{outcome: "fallback", reason: "diff_unavailable"}}} =
               Runs.create(project, %{dirty: true} |> params() |> Map.delete(:changed_files))
    end

    test "records the client's reason when there's no baseline", %{project: project} do
      assert {:ok, %{run: run, skipped_tests: nil}} =
               Runs.create(project, params(%{baseline_sha: nil, fallback_reason: "history_unavailable"}))

      assert {run.outcome, run.reason, run.baseline_sha} == {"fallback", "history_unavailable", nil}
      assert selected(project, run) == []
    end

    test "falls back on the default branch", %{project: project} do
      assert {:ok, %{run: %{outcome: "fallback", reason: "excluded_branch"}}} =
               Runs.create(project, params(%{git_branch: project.default_branch}))
    end

    test "falls back when the diff is over 5,000 files", %{project: project} do
      assert {:ok, %{run: %{outcome: "fallback", reason: "diff_too_large"}}} =
               Runs.create(project, params(%{changed_files_count: 5_001}))
    end

    test "falls back when a tracked file changed, with the rule's trace", %{project: project} do
      changed_files = [%{path: "Package.resolved", status: "M", blob: "new"}]

      assert {:ok, %{run: run, skipped_tests: nil}} = Runs.create(project, params(%{changed_files: changed_files}))
      assert {run.outcome, run.reason, run.matched_path} == {"fallback", "tracked_file_changed", "Package.resolved"}
      assert [%{rule: "tracked_files", verdict: "abort"}] = run.rule_trace
      assert {run.requested_count, run.selected_count, run.skipped_count} == {0, 0, 0}
    end

    test "falls back when the baseline isn't in the checkout's window", %{project: project} do
      assert {:ok, %{run: %{outcome: "fallback", reason: "no_baseline"}}} =
               Runs.create(project, params(%{head_sha: "unknown"}))
    end

    test "walks a merge checkout's window from the parents", %{project: project} do
      assert {:ok, %{run: %{outcome: "selected"}}} =
               Runs.create(project, params(%{commit_sha: "merge", parent_shas: ["c2"]}))
    end

    test "keeps to the requested modules", %{project: project} do
      assert {:ok, %{run: run, skipped_tests: skip}} = Runs.create(project, params(%{modules: ["CoreTests"]}))
      assert {run.requested_count, run.selected_count, run.requested_modules} == {1, 0, ["CoreTests"]}
      assert skip == [%{module: "CoreTests"}]
    end
  end

  describe "shard plans" do
    setup do
      stub(Tuist.Storage, :object_exists?, fn _key, _account -> false end)
      stub(Tuist.Storage, :generate_download_url, fn _key, _account -> "https://download.example.com" end)
      :ok
    end

    test "distribute the suites with selected tests, and each shard skips what selection skipped", %{
      project: project
    } do
      {:ok, %{run: run}} = Runs.create(project, params())

      %{plan: plan, shard_count: 2} =
        Shards.create_shard_plan(project, %{
          reference: "ref",
          granularity: "module",
          modules: ["AppTests", "CoreTests"],
          shard_total: 2,
          test_impact_run_id: run.id
        })

      assert plan.granularity == "suite"
      assert plan.test_impact_run_id == run.id

      # MathTests' selected test takes longer, so it gets a shard of its own.
      opts = [suite_catch_all?: true]
      assert {:ok, first} = Shards.get_shard(project, project.account, "ref", 0, opts)
      assert first.suites == %{"AppTests" => ["MathTests"]}
      assert first.skipped_tests == [%{module: "AppTests", suite: "MathTests", name: "testSub()"}]

      assert {:ok, catch_all} = Shards.get_shard(project, project.account, "ref", 1, opts)

      assert catch_all.skipped_tests == [
               %{module: "AppTests", suite: "MathTests"},
               %{module: "AppTests", suite: "StringTests", name: "testUpper()"},
               %{module: "CoreTests"}
             ]
    end

    test "plan as without a run when the run fell back", %{project: project} do
      {:ok, %{run: run}} = Runs.create(project, params(%{baseline_sha: nil}))

      %{plan: plan} =
        Shards.create_shard_plan(project, %{
          reference: "ref",
          modules: ["AppTests"],
          shard_total: 1,
          test_impact_run_id: run.id
        })

      assert plan.granularity == "module"
      assert plan.test_impact_run_id == nil
      assert {:ok, shard} = Shards.get_shard(project, project.account, "ref", 0)
      refute Map.has_key?(shard, :skipped_tests)
    end
  end

  describe "skip_entries/2" do
    test "skips a module whole only when none of its tests is selected" do
      tests = [
        %{test_case_id: "a", module_name: "A", suite_name: "S", name: "t1"},
        %{test_case_id: "b", module_name: "A", suite_name: "S", name: "t2"},
        %{test_case_id: "c", module_name: "B", suite_name: "S", name: "t1"},
        %{test_case_id: "d", module_name: "C", suite_name: "S", name: "t1"}
      ]

      assert Runs.skip_entries(tests, MapSet.new(["a", "d"])) == [
               %{module: "A", suite: "S", name: "t2"},
               %{module: "B"}
             ]
    end
  end
end
