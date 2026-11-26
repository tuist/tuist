defmodule Tuist.TestImpactAnalysis.RunsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.GitHistory
  alias Tuist.GitHistory.FileChanges
  alias Tuist.Shards
  alias Tuist.TestImpactAnalysis.Decision
  alias Tuist.TestImpactAnalysis.Runs
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.TestImpactAnalysis.Snapshots
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
        modules: [%{name: "AppTests", skipped: false}, %{name: "CoreTests", skipped: false}],
        changed_files: [%{path: "Sources/Math.swift", status: "M", blob: "new", affected_modules: ["AppTests"]}],
        xcode: %{scheme: "App"}
      },
      attrs
    )
  end

  # The tests the run's stored decision selected, with their reason and the
  # changed file that matched, named from `test_cases`.
  defp selected(project, run) do
    case Decision.stored(project.id, run.id) do
      nil -> []
      decision -> named_selected(project, decision)
    end
  end

  defp named_selected(project, %{snapshot_id: snapshot_id, tests: tests}) do
    tests = Enum.filter(tests, &(&1.decision == :selected))
    names = Snapshots.names(project.id, %{checkpoint: %Snapshot{id: snapshot_id}}, Enum.map(tests, & &1.idx))

    tests
    |> Enum.map(&{&1.module_name, &1.suite_name, names[&1.idx].name, to_string(&1.reason), &1.matched_path})
    |> Enum.sort()
  end

  describe "create/2" do
    test "selects the impacted tests and those without evidence, and skips the rest", %{project: project, run: baseline} do
      assert {:ok, %{run: run, skipped_tests: skip}} = Runs.create(project, params())

      assert run.outcome == "selected"
      assert run.commit_sha == "c2"
      assert run.baseline_run_ids == [baseline.id]
      assert {run.requested_count, run.selected_count, run.skipped_count} == {5, 2, 3}
      assert run.rules_version == "4"
      assert List.last(run.rule_trace).rule == "unaffected"
      assert run.build_context == %{"scheme" => "App"}

      assert selected(project, run) == [
               {"AppTests", "MathTests", "testAdd()", "impacted", "Sources/Math.swift"},
               {"AppTests", "SumTests", "sum()", "no_evidence", nil}
             ]

      assert skip == [
               %{module: "AppTests", suite: "MathTests", name: "testSub()"},
               %{module: "AppTests", suite: "StringTests", name: "testUpper()"},
               %{module: "CoreTests"}
             ]

      assert {:ok, %{changed_files_count: 1}} = Storage.get_diff(project.id, "c2", "c1")
    end

    test "selects every test of the modules left when the baseline's tests recorded no evidence" do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      CoverageFixtures.seed_history(account, [
        CoverageFixtures.commit("c1", [], 0),
        CoverageFixtures.commit("c2", ["c1"], 1)
      ])

      CoverageFixtures.seed_listing(account, "c1", @sources)

      baseline =
        CoverageFixtures.run_with_coverage(project, account, Enum.map(@sources, &CoverageFixtures.file(&1, [1])), %{
          git_commit_sha: "c1",
          test_modules: [
            %{
              name: "AppTests",
              status: "success",
              duration: 1,
              test_cases: [
                %{name: "sum()", test_suite_name: "SumTests", status: "success", duration: 10},
                %{name: "upper()", test_suite_name: "StringTests", status: "success", duration: 10}
              ]
            }
          ]
        })

      assert {:ok, %{run: run, skipped_tests: []}} =
               Runs.create(project, params(%{modules: [%{name: "AppTests", skipped: false}]}))

      assert run.outcome == "selected"
      assert run.baseline_sha == "c1"
      assert run.baseline_run_ids == [baseline.id]
      assert {run.requested_count, run.selected_count, run.skipped_count} == {2, 2, 0}

      assert selected(project, run) == [
               {"AppTests", "StringTests", "upper()", "no_evidence", nil},
               {"AppTests", "SumTests", "sum()", "no_evidence", nil}
             ]
    end

    test "counts the tests of modules skipped by hash as requested and skipped", %{project: project} do
      modules = [
        %{name: "AppTests", skipped: false},
        %{name: "CoreTests", skipped: true},
        %{name: "NewTests", skipped: true}
      ]

      assert {:ok, %{run: run, skipped_tests: skip}} = Runs.create(project, params(%{modules: modules}))

      assert {run.outcome, run.requested_modules} == {"selected", ["AppTests"]}
      assert run.skipped_modules == %{"CoreTests" => 1, "NewTests" => 0}
      assert {run.requested_count, run.selected_count, run.skipped_count} == {5, 2, 3}
      refute Enum.any?(skip, &(&1.module == "CoreTests"))
    end

    test "counts every test of the modules left as selected on a fallback after the baseline", %{project: project} do
      modules = [%{name: "AppTests", skipped: false}, %{name: "CoreTests", skipped: true}]
      changed = [%{path: "Package.resolved", status: "M", blob: "new"}]

      assert {:ok, %{run: run}} = Runs.create(project, params(%{modules: modules, changed_files: changed}))

      assert {run.outcome, run.reason, run.skipped_modules} == {"fallback", "tracked_file_changed", %{"CoreTests" => 1}}
      assert {run.requested_count, run.selected_count, run.skipped_count} == {5, 4, 1}
    end

    test "records a selection of nothing when hashing skipped every module, whatever the diff", %{project: project} do
      modules = [%{name: "AppTests", skipped: true}, %{name: "CoreTests", skipped: true}]
      changed = [%{path: "Package.resolved", status: "M", blob: "new"}]

      assert {:ok, %{run: run, skipped_tests: []}} =
               Runs.create(project, params(%{modules: modules, changed_files: changed}))

      assert {run.outcome, run.reason, run.rule_trace, run.requested_modules} == {"selected", "", [], []}
      assert {run.requested_count, run.selected_count, run.skipped_count} == {5, 0, 5}
      assert run.skipped_modules == %{"AppTests" => 4, "CoreTests" => 1}
      assert Storage.get_diff(project.id, "c2", "c1") == {:error, :not_found}

      # Without a baseline the modules are kept, with no counts.
      assert {:ok, %{run: %{outcome: "selected", baseline_sha: nil, requested_count: 0, reason: "no_baseline"} = run}} =
               Runs.create(project, params(%{modules: modules, baseline_sha: nil, fallback_reason: "no_baseline"}))

      assert run.skipped_modules == %{"AppTests" => 0, "CoreTests" => 0}
    end

    test "reuses the stored diff when the client sends none", %{project: project} do
      {:ok, _} = Runs.create(project, params())

      assert {:ok, %{run: %{outcome: "selected", selected_count: 2}}} =
               Runs.create(project, Map.delete(params(), :changed_files))
    end

    test "falls back on a dirty checkout once the baseline is confirmed, without reading or storing a diff", %{
      project: project
    } do
      modules = [%{name: "AppTests", skipped: false}, %{name: "CoreTests", skipped: true}]

      # The diff names only a source file, which would select on a clean checkout.
      assert {:ok, %{run: run, skipped_tests: nil}} =
               Runs.create(project, params(%{dirty: true, modules: modules}))

      assert {run.outcome, run.reason, run.dirty, run.baseline_sha} == {"fallback", "dirty_checkout", true, "c1"}
      assert {run.requested_count, run.selected_count, run.skipped_count} == {5, 4, 1}
      assert run.skipped_modules == %{"CoreTests" => 1}
      assert Storage.get_diff(project.id, "c2", "c1") == {:error, :not_found}

      # It wins over a tracked file, and needs no diff at all.
      tracked = [%{path: "Package.resolved", status: "M", blob: "new"}]

      assert {:ok, %{run: %{reason: "dirty_checkout", matched_path: ""}}} =
               Runs.create(project, params(%{dirty: true, changed_files: tracked}))

      assert {:ok, %{run: %{reason: "dirty_checkout"}}} =
               Runs.create(project, %{dirty: true} |> params() |> Map.delete(:changed_files))

      # A baseline the server can't confirm keeps that reason.
      assert {:ok, %{run: %{reason: "no_baseline", baseline_sha: nil}}} =
               Runs.create(project, params(%{dirty: true, baseline_sha: "unknown"}))

      # The same commit from a clean checkout still selects.
      assert {:ok, %{run: %{outcome: "selected", dirty: false}}} = Runs.create(project, params())
    end

    test "keeps only the changed files the client marked dirty, with the run", %{project: project} do
      changed_files = [
        %{path: "Sources/Math.swift", status: "M", blob: "committed", affected_modules: ["AppTests"]},
        %{path: "Sources/Cache.swift", status: "M", blob: "edited", dirty: true},
        %{path: "Sources/Gone.swift", status: "D", dirty: true},
        %{path: "Sources/Other.swift", status: "M", blob: "other", dirty: false}
      ]

      assert {:ok, %{run: run}} = Runs.create(project, params(%{dirty: true, changed_files: changed_files}))
      assert run.reason == "dirty_checkout"

      assert Storage.dirty_files(project.id, run.id) == [
               %{path: "Sources/Cache.swift", status: "M", blob: "edited"},
               %{path: "Sources/Gone.swift", status: "D", blob: ""}
             ]

      assert Storage.get_diff(project.id, "c2", "c1") == {:error, :not_found}

      # Reading the run doesn't load them; an older client's run has none.
      assert {:ok, %{dirty_files: []}} = Storage.get_run(project.id, run.id)
      assert {:ok, %{run: old}} = Runs.create(project, params(%{dirty: true}))
      assert Storage.dirty_files(project.id, old.id) == []

      # A clean run never keeps any, even if a client marked some.
      assert {:ok, %{run: clean}} = Runs.create(project, params(%{changed_files: changed_files}))
      assert Storage.dirty_files(project.id, clean.id) == []
    end

    test "records the client's reason when there's no baseline", %{project: project} do
      assert {:ok, %{run: run, skipped_tests: nil}} =
               Runs.create(project, params(%{baseline_sha: nil, fallback_reason: "history_unavailable"}))

      assert {run.outcome, run.reason, run.baseline_sha} == {"fallback", "history_unavailable", nil}
      assert selected(project, run) == []
    end

    test "selects on the default branch like on any other", %{project: project} do
      assert {:ok, %{run: %{outcome: "selected"}}} = Runs.create(project, params(%{git_branch: project.default_branch}))
    end

    test "falls back when the diff is over 5,000 files, counting the baseline's tests", %{project: project} do
      modules = [%{name: "AppTests", skipped: false}, %{name: "CoreTests", skipped: true}]

      assert {:ok, %{run: run, skipped_tests: nil}} =
               Runs.create(project, params(%{modules: modules, changed_files_count: 5_001}))

      assert {run.outcome, run.reason, run.baseline_sha} == {"fallback", "diff_too_large", "c1"}
      assert run.skipped_modules == %{"CoreTests" => 1}
      assert {run.requested_count, run.selected_count, run.skipped_count} == {5, 4, 1}

      # A baseline the server can't confirm isn't stored.
      assert {:ok, %{run: %{reason: "diff_too_large", baseline_sha: nil, requested_count: 0}}} =
               Runs.create(project, params(%{head_sha: "unknown", changed_files_count: 5_001}))
    end

    test "falls back when a tracked file changed, with the rule's trace", %{project: project} do
      changed_files = [%{path: "Package.resolved", status: "M", blob: "new"}]

      assert {:ok, %{run: run, skipped_tests: nil}} = Runs.create(project, params(%{changed_files: changed_files}))
      assert {run.outcome, run.reason, run.matched_path} == {"fallback", "tracked_file_changed", "Package.resolved"}
      assert [%{rule: "tracked_files", verdict: "abort"}] = run.rule_trace
      assert {run.requested_count, run.selected_count, run.skipped_count} == {5, 5, 0}
      assert run.matched_pattern == "**/Package.resolved"
    end

    test "falls back on the project's tracked files, and a ! pattern opts out of a default", %{project: project} do
      readme = %{path: "Docs/Setup.md", status: "M", blob: "new", affected_modules: []}
      pin = %{path: "Package.resolved", status: "M", blob: "new", affected_modules: []}

      # A file no evidence includes and no pattern tracks selects nothing.
      assert {:ok, %{run: %{outcome: "selected", tracked_files: []} = run}} =
               Runs.create(project, params(%{changed_files: [readme]}))

      assert selected(project, run) == [{"AppTests", "SumTests", "sum()", "no_evidence", nil}]

      tracked_files = ["Docs/**", "!**/Package.resolved"]

      assert {:ok, %{run: run}} =
               Runs.create(project, params(%{changed_files: [pin, readme], tracked_files: tracked_files}))

      assert {run.outcome, run.reason, run.matched_path, run.matched_pattern, run.tracked_files} ==
               {"fallback", "tracked_file_changed", "Docs/Setup.md", "Docs/**", tracked_files}

      # Excluded, the default pin no longer falls back.
      assert {:ok, %{run: %{outcome: "selected"}}} =
               Runs.create(project, params(%{changed_files: [pin], tracked_files: tracked_files}))

      # A ! pattern also wins over the project's own include.
      assert {:ok, %{run: %{outcome: "selected"}}} =
               Runs.create(project, params(%{changed_files: [readme], tracked_files: ["Docs/**", "!Docs/*.md"]}))
    end

    test "never skips whole a module that gained a file, so a test the file adds runs", %{project: project} do
      new_file = %{path: "Tests/CoreTests/NewTests.swift", status: "A", blob: "new", affected_modules: ["CoreTests"]}

      assert {:ok, %{run: run, skipped_tests: skip}} =
               Runs.create(project, params(%{changed_files: [new_file | params().changed_files]}))

      # The added file selects nothing.
      assert {run.selected_count, run.skipped_count} == {2, 3}

      assert skip == [
               %{module: "AppTests", suite: "MathTests", name: "testSub()"},
               %{module: "AppTests", suite: "StringTests", name: "testUpper()"},
               %{module: "CoreTests", suite: "CoreSuite", name: "testCore()"}
             ]

      assert skip_list_of(project, run) == skip
    end

    test "falls back with history_unknown when the history doesn't have the checkout", %{project: project} do
      assert {:ok, %{run: %{outcome: "fallback", reason: "history_unknown", baseline_sha: nil}}} =
               Runs.create(project, params(%{head_sha: "unknown"}))

      modules = [%{name: "AppTests", skipped: true}, %{name: "CoreTests", skipped: true}]

      assert {:ok, %{run: %{outcome: "selected", reason: "history_unknown", baseline_sha: nil}}} =
               Runs.create(project, params(%{head_sha: "unknown", modules: modules}))
    end

    test "resolves the baseline from the ancestors sent when the history doesn't have the checkout", %{
      project: project
    } do
      params = params(%{head_sha: "x2", parent_shas: ["x1"], ancestor_shas: ["x1", "c2"]})

      assert {:ok, %{run: %{outcome: "selected", baseline_sha: "c1"}}} = Runs.create(project, params)
    end

    test "falls back when the baseline isn't in the checkout's window", %{project: project} do
      assert {:ok, %{run: %{outcome: "fallback", reason: "no_baseline"}}} =
               Runs.create(project, params(%{baseline_sha: "unknown"}))
    end

    test "walks a merge checkout's window from the parents", %{project: project} do
      assert {:ok, %{run: %{outcome: "selected"}}} =
               Runs.create(project, params(%{commit_sha: "merge", parent_shas: ["c2"]}))
    end

    test "keeps to the requested modules", %{project: project} do
      assert {:ok, %{run: run, skipped_tests: skip}} = Runs.create(project, params(%{modules: [%{name: "CoreTests"}]}))
      assert {run.requested_count, run.selected_count, run.requested_modules} == {1, 0, ["CoreTests"]}
      assert skip == [%{module: "CoreTests"}]
    end
  end

  describe "the checked-out commit's file changes" do
    # The baseline c1 on main, its file changes written.
    setup %{repository_id: repository_id} do
      GitHistory.record_branch_head(repository_id, "main", "c1", "main")
      Oban.drain_queue(queue: :coverage_deltas, with_recursion: true, with_safety: false)
      assert FileChanges.current(repository_id, "c1")
      :ok
    end

    defp tree(repository_id, sha), do: Map.new(GitHistory.commit_files(repository_id, sha), &{&1.path, &1.git_blob_id})

    test "are written from a clean checkout's diff, so its listing isn't asked for", %{
      project: project,
      repository_id: repository_id
    } do
      assert GitHistory.missing_listings(repository_id, ["c2"]) == ["c2"]

      assert {:ok, %{run: %{outcome: "selected"}}} = Runs.create(project, params())

      assert GitHistory.missing_listings(repository_id, ["c2"]) == []

      assert tree(repository_id, "c2") ==
               (@sources ++ ["Package.resolved"])
               |> Map.new(&{&1, "blob-" <> &1})
               |> Map.put("Sources/Math.swift", "new")
    end

    test "are not written from a dirty checkout's diff, nor from a capped one", %{
      project: project,
      repository_id: repository_id
    } do
      assert {:ok, _} = Runs.create(project, params(%{dirty: true}))
      assert {:ok, _} = Runs.create(project, params(%{changed_files_count: 2}))

      assert GitHistory.missing_listings(repository_id, ["c2"]) == ["c2"]
      assert CoverageFixtures.listing(repository_id, "c2") == nil
    end

    test "are written from the stored diff once the commit reaches the graph", %{
      project: project,
      repository_id: repository_id
    } do
      assert {:ok, %{run: %{outcome: "selected"}}} =
               Runs.create(project, params(%{head_sha: "c3", parent_shas: ["c1"]}))

      assert GitHistory.missing_listings(repository_id, ["c3"]) == ["c3"]

      GitHistory.record_commits(repository_id, "sha1", [CoverageFixtures.commit("c3", ["c1"], 2)])

      assert Runs.write_file_changes(project, repository_id, ["c3", "c4"]) == ["c3"]
      assert GitHistory.missing_listings(repository_id, ["c3"]) == []
      assert tree(repository_id, "c3")["Sources/Math.swift"] == "new"
    end

    test "a failed write doesn't fail the request", %{project: project, repository_id: repository_id} do
      stub(FileChanges, :write_from_diff, fn _repository_id, _sha, _base_sha, _diff, _limit -> raise "boom" end)

      assert {:ok, %{run: %{outcome: "selected"}}} = Runs.create(project, params())
      assert GitHistory.missing_listings(repository_id, ["c2"]) == ["c2"]
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

    test "the catch-all shard names a module that gained a file test by test", %{project: project} do
      new_file = %{path: "Tests/CoreTests/NewTests.swift", status: "A", blob: "new", affected_modules: ["CoreTests"]}
      {:ok, %{run: run}} = Runs.create(project, params(%{changed_files: [new_file | params().changed_files]}))

      Shards.create_shard_plan(project, %{
        reference: "added",
        granularity: "module",
        modules: ["AppTests", "CoreTests"],
        shard_total: 2,
        test_impact_run_id: run.id
      })

      assert {:ok, catch_all} = Shards.get_shard(project, project.account, "added", 1, suite_catch_all?: true)

      assert catch_all.skipped_tests == [
               %{module: "AppTests", suite: "MathTests"},
               %{module: "AppTests", suite: "StringTests", name: "testUpper()"},
               %{module: "CoreTests", suite: "CoreSuite", name: "testCore()"}
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

  describe "Mix" do
    # The baseline c1 ran MyApp.MathTest (`adds` and `subtracts` outside any
    # describe, `upcase/1 upcases` in one, and `doubles`, which overlapped a
    # test of another module and has no evidence of its own) and
    # MyApp.CoreTest (`boots`), as `mix tuist.test --cover` reports them.
    @mix_sources ~w(lib/my_app/math.ex lib/my_app/strings.ex lib/my_app/core.ex)

    setup %{project: project} do
      account = Tuist.Repo.preload(project, :account).account
      test_case = &%{name: &1, test_suite_name: &2, status: "success", duration: 20}
      scope = &%{kind: "test", module: &1, suite: &2, name: &3, files: [&4], lines: [[1, 1]]}

      CoverageFixtures.run_with_coverage(project, account, [], %{
        build_system: "mix",
        scheme: nil,
        git_commit_sha: "c1",
        xcode_coverage: nil,
        coverage: %{tool: "cover", partial: false, files: Enum.map(@mix_sources, &CoverageFixtures.file(&1, [1]))},
        test_modules: [
          %{
            name: "MyApp.MathTest",
            status: "success",
            duration: 1,
            test_cases: [
              test_case.("adds", nil),
              test_case.("subtracts", nil),
              test_case.("upcases", "upcase/1"),
              test_case.("doubles", nil)
            ]
          },
          %{name: "MyApp.CoreTest", status: "success", duration: 1, test_cases: [test_case.("boots", nil)]}
        ],
        coverage_evidence: %{
          paths: @mix_sources,
          scopes: [
            scope.("MyApp.MathTest", "", "adds", 0),
            scope.("MyApp.MathTest", "", "subtracts", 0),
            scope.("MyApp.MathTest", "upcase/1", "upcases", 1),
            scope.("MyApp.CoreTest", "", "boots", 2),
            %{kind: "target", module: "MyApp.MathTest", suite: "", files: [0, 1]},
            %{kind: "target", module: "MyApp.CoreTest", suite: "", files: [2]}
          ],
          overlapped_tests: [%{module: "MyApp.MathTest", suite: "", name: "doubles"}]
        }
      })

      :ok
    end

    defp mix_params(attrs \\ %{}) do
      Map.merge(
        %{
          build_system: "mix",
          head_sha: "c2",
          baseline_sha: "c1",
          git_branch: "feature",
          modules: [%{name: "MyApp.CoreTest"}, %{name: "MyApp.MathTest"}],
          changed_files: [
            %{path: "lib/my_app/strings.ex", status: "M", blob: "new", affected_modules: ["MyApp.MathTest"]}
          ],
          mix: %{app: "my_app"}
        },
        attrs
      )
    end

    test "selects from a Mix run's evidence and stores the mix block as the build context", %{project: project} do
      assert {:ok, %{run: run, skipped_tests: skip}} = Runs.create(project, mix_params())

      assert run.outcome == "selected"
      assert run.build_system == "mix"
      assert run.build_context == %{"app" => "my_app"}
      assert {run.requested_count, run.selected_count, run.skipped_count} == {5, 2, 3}

      assert selected(project, run) == [
               {"MyApp.MathTest", "", "doubles", "no_evidence", nil},
               {"MyApp.MathTest", "upcase/1", "upcases", "impacted", "lib/my_app/strings.ex"}
             ]

      assert skip == [
               %{module: "MyApp.CoreTest"},
               %{module: "MyApp.MathTest", suite: "", name: "adds"},
               %{module: "MyApp.MathTest", suite: "", name: "subtracts"}
             ]
    end

    # A migration changes the schema every test's database starts from, which
    # no test's evidence shows.
    test "falls back when a migration changed", %{project: project} do
      project = project |> Ecto.Changeset.change(build_system: :mix) |> Tuist.Repo.update!()
      migration = "server/priv/repo/migrations/20261126000000_add_column.exs"
      changed_files = [%{path: migration, status: "A", blob: "new", affected_modules: ["MyApp.MathTest"]}]

      assert {:ok, %{run: run, skipped_tests: nil}} = Runs.create(project, mix_params(%{changed_files: changed_files}))
      assert {run.outcome, run.reason, run.matched_path} == {"fallback", "tracked_file_changed", migration}
    end

    test "scopes the baseline to the mix block's scheme", %{project: project} do
      assert {:ok, %{run: run, skipped_tests: nil}} =
               Runs.create(project, mix_params(%{mix: %{scheme: "postgres-16", app: "my_app"}}))

      assert {run.outcome, run.reason} == {"fallback", "no_baseline"}
      assert run.build_context == %{"scheme" => "postgres-16", "app" => "my_app"}
    end

    test "ignores another build system's block", %{project: project} do
      assert {:ok, %{run: run}} = Runs.create(project, mix_params(%{mix: nil, xcode: %{scheme: "postgres-16"}}))

      assert run.outcome == "selected"
      assert run.build_context == %{}
    end

    test "a shard plan balances the modules sent, and each shard reads the whole skip list and the run", %{
      project: project
    } do
      stub(Tuist.Storage, :object_exists?, fn _key, _account -> false end)
      {:ok, %{run: run}} = Runs.create(project, mix_params())

      %{plan: plan} =
        Shards.create_shard_plan(project, %{
          reference: "mix-ref",
          granularity: "module",
          modules: ["MyApp.MathTest"],
          shard_total: 1,
          test_impact_run_id: run.id
        })

      assert {plan.granularity, plan.test_impact_run_id} == {"module", run.id}
      assert {:ok, shard} = Shards.get_shard(project, project.account, "mix-ref", 0)
      assert shard.modules == ["MyApp.MathTest"]
      assert shard.test_impact_run_id == run.id
      assert shard.skipped_tests == skip_list_of(project, run)
      assert length(shard.skipped_tests) == 3
    end

    test "a shard plan keeps a run that fell back, whose shards read the run without a skip list", %{
      project: project
    } do
      stub(Tuist.Storage, :object_exists?, fn _key, _account -> false end)
      {:ok, %{run: run}} = Runs.create(project, mix_params(%{mix: %{scheme: "postgres-16", app: "my_app"}}))
      assert {run.outcome, run.reason} == {"fallback", "no_baseline"}

      %{plan: plan} =
        Shards.create_shard_plan(project, %{
          reference: "mix-fallback-ref",
          granularity: "module",
          modules: ["MyApp.CoreTest", "MyApp.MathTest"],
          shard_total: 1,
          test_impact_run_id: run.id
        })

      assert {plan.granularity, plan.test_impact_run_id} == {"module", run.id}
      assert {:ok, shard} = Shards.get_shard(project, project.account, "mix-fallback-ref", 0)
      assert Enum.sort(shard.modules) == ["MyApp.CoreTest", "MyApp.MathTest"]
      assert shard.test_impact_run_id == run.id
      refute Map.has_key?(shard, :skipped_tests)
    end
  end

  defp skip_list_of(project, run), do: Runs.skipped_tests(project.id, run.id)

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
