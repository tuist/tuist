defmodule Tuist.TestImpactAnalysis.DecisionTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.TestImpactAnalysis.Candidate
  alias Tuist.TestImpactAnalysis.Carry
  alias Tuist.TestImpactAnalysis.Decision
  alias Tuist.TestImpactAnalysis.Runs
  alias Tuist.TestImpactAnalysis.Snapshots
  alias Tuist.Tests.Coverage.Reported
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @sources ~w(Sources/Math.swift Sources/Sub.swift Sources/Strings.swift Sources/Core.swift Sources/Boot.swift)
  @test_file "Tests/MathTests.swift"
  @paths @sources ++ [@test_file]

  # The baseline c1 is a full run of AppTests (MathTests: testAdd() over
  # Math.swift and the suite's test file, testSub() over Sub.swift;
  # StringTests: testUpper() over Strings.swift; SumTests: sum(), without
  # evidence) and CoreTests (CoreSuite: testCore() over Core.swift, its
  # processes also running Boot.swift outside the test).
  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("c1", [], 0),
      CoverageFixtures.commit("c2", ["c1"], 1),
      CoverageFixtures.commit("c3", ["c2"], 2),
      CoverageFixtures.commit("c4", ["c3"], 3)
    ])

    CoverageFixtures.seed_listing(account, "c1", @paths ++ ["Package.resolved"])
    full_run(project, account, "c1", files())

    %{project: project, account: account}
  end

  defp full_run(project, account, sha, files) do
    test_case = fn name, suite -> %{name: name, test_suite_name: suite, status: "success", duration: 10} end

    scope = fn module, suite, name, files ->
      %{kind: "test", module: module, suite: suite, name: name, files: files, lines: Enum.map(files, fn _ -> [1, 1] end)}
    end

    CoverageFixtures.run_with_coverage(project, account, files, %{
      git_commit_sha: sha,
      test_modules: [
        %{
          name: "AppTests",
          status: "success",
          duration: 1,
          test_cases: [
            test_case.("testAdd()", "MathTests"),
            test_case.("testSub()", "MathTests"),
            test_case.("testUpper()", "StringTests"),
            test_case.("sum()", "SumTests")
          ]
        },
        %{name: "CoreTests", status: "success", duration: 1, test_cases: [test_case.("testCore()", "CoreSuite")]}
      ],
      coverage_evidence: %{
        paths: @paths,
        scopes: [
          scope.("AppTests", "MathTests", "testAdd()", [0, 5]),
          scope.("AppTests", "MathTests", "testSub()", [1]),
          scope.("AppTests", "StringTests", "testUpper()", [2]),
          scope.("CoreTests", "CoreSuite", "testCore()", [3]),
          %{kind: "target", module: "CoreTests", files: [3, 4], lines: [[1, 1], [1, 1]]}
        ]
      }
    })
  end

  # Every file with its line covered (`count` 1), at `blobs`' blob where it names one.
  defp files(blobs \\ %{}, count \\ 1) do
    blob = fn path -> [git_blob_id: Map.get(blobs, path, "blob-" <> path)] end

    Enum.map(@sources, &CoverageFixtures.file(&1, [count], blob.(&1))) ++
      [CoverageFixtures.file(@test_file, [count], [is_test: true] ++ blob.(@test_file))]
  end

  defp params(head_sha, changed_files, baseline_sha \\ "c1") do
    %{
      build_system: "xcode",
      head_sha: head_sha,
      baseline_sha: baseline_sha,
      git_branch: "feature",
      modules: [%{name: "AppTests", skipped: false}, %{name: "CoreTests", skipped: false}],
      changed_files: changed_files,
      xcode: %{scheme: "App"}
    }
  end

  defp changed(path, blob, modules \\ ["AppTests"]), do: %{path: path, status: "M", blob: blob, affected_modules: modules}

  defp decide(project, head_sha, changed_files, baseline_sha \\ "c1") do
    {:ok, %{run: run}} = Runs.create(project, params(head_sha, changed_files, baseline_sha))
    %{tests: tests} = Decision.stored(project.id, run.id)

    result = %{
      decisions: Map.new(tests, &{&1.test_case_id, &1}),
      evidence: tests |> Enum.map(& &1.evidence_snapshot_id) |> Enum.uniq()
    }

    {run, result}
  end

  # Each test's `{decision, reason}` by name, named from the checkpoint at
  # `sha`.
  defp by_name(project, %{decisions: decisions}, sha \\ "c1") do
    snapshot = Snapshots.at(project.id, sha, "App", "")
    tests = Candidate.evaluate(project.id, snapshot, [])
    named = Snapshots.names(project.id, snapshot, Enum.map(tests, & &1.idx))
    names = Map.new(tests, &{&1.test_case_id, named[&1.idx].name})

    Map.new(decisions, fn {id, d} -> {names[id], {d.decision, d.reason}} end)
  end

  test "a full run writes a checkpoint that decides each test with its reason", %{project: project} do
    {_run, result} = decide(project, "c2", [changed("Sources/Math.swift", "m2"), changed("Sources/Zeta.swift", "z2", [])])

    # The changed file that selected it, and none for a test no file decided.
    assert result.decisions |> Map.values() |> Enum.map(& &1.matched_path) |> Enum.frequencies() ==
             %{"Sources/Math.swift" => 1, nil => 4}

    assert by_name(project, result) == %{
             "testAdd()" => {:selected, :impacted},
             "testSub()" => {:skipped, :unaffected},
             "testUpper()" => {:skipped, :unaffected},
             "sum()" => {:selected, :no_evidence},
             "testCore()" => {:skipped, :unaffected}
           }
  end

  test "selects a changed test file's whole suite and a module's target-level evidence, and nothing for a file no evidence includes",
       %{project: project} do
    {_run, result} = decide(project, "c2", [changed(@test_file, "t2")])
    decisions = by_name(project, result)
    # testSub() never executed the test file; its suite did.
    assert decisions["testAdd()"] == {:selected, :test_file_changed}
    assert decisions["testSub()"] == {:selected, :test_file_changed}
    assert decisions["testUpper()"] == {:skipped, :unaffected}

    {_run, result} = decide(project, "c3", [changed("Sources/Boot.swift", "b2", ["CoreTests"])])
    assert by_name(project, result)["testCore()"] == {:selected, :impacted}
    assert by_name(project, result)["testAdd()"] == {:skipped, :unaffected}

    # Only a tracked pattern makes a file no evidence includes run anything.
    {_run, result} = decide(project, "c4", [changed("Resources/Image.png", "i2", ["CoreTests"])])

    assert by_name(project, result) == %{
             "testAdd()" => {:skipped, :unaffected},
             "testSub()" => {:skipped, :unaffected},
             "testUpper()" => {:skipped, :unaffected},
             "sum()" => {:selected, :no_evidence},
             "testCore()" => {:skipped, :unaffected}
           }
  end

  # 5,000 paths of 250 bytes are 1.3 MB, ten times what open-source
  # ClickHouse accepts in one parameter by default.
  test "reads a diff of long paths in parameters ClickHouse accepts", %{project: project} do
    snapshot = Snapshots.at(project.id, "c1", "App", "")
    deep = for i <- 1..5_000, do: changed("Sources/#{String.duplicate("Deep/", 46)}File#{i}'s.swift", "d#{i}", [])
    tests = Candidate.evaluate(project.id, snapshot, deep ++ [changed("Sources/Math.swift", "m2")])

    assert tests |> Enum.reject(&(&1.reason == :unaffected)) |> Enum.map(& &1.reason) |> Enum.sort() == [
             :impacted,
             :no_evidence
           ]
  end

  test "decides nothing, without a diff, when hashing skipped every module", %{project: project} do
    modules = [%{name: "AppTests", skipped: true}, %{name: "CoreTests", skipped: true}]
    {:ok, %{run: run}} = Runs.create(project, %{params("c2", nil) | modules: modules})
    assert %{outcome: "selected", requested_modules: []} = run

    assert Decision.stored(project.id, run.id) == nil
  end

  # A run's fold at its creation comes before its results are processed:
  # a checkpoint written then would hold no tests, and its id would stop the
  # fold after processing from writing the real one.
  test "writes no snapshot for a run whose results aren't processed yet", %{project: project, account: account} do
    id = UUIDv7.generate()
    attrs = %{id: id, git_commit_sha: "c2", test_modules: []}
    CoverageFixtures.run_with_coverage(project, account, files(), attrs)
    assert Snapshots.at(project.id, "c2", "App", "") == nil

    modules = [
      %{
        name: "AppTests",
        status: "success",
        duration: 1,
        test_cases: [%{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 10}]
      }
    ]

    CoverageFixtures.run_with_coverage(project, account, files(), %{attrs | test_modules: modules})
    assert %{checkpoint: %{tests_count: 1}} = Snapshots.at(project.id, "c2", "App", "")
  end

  test "a later full run that ran the same lines points to the line sets already stored",
       %{project: project, account: account} do
    count = fn table ->
      [[count]] =
        Snapshots.query!("SELECT count() FROM #{table} FINAL WHERE project_id = {project_id:Int64}", %{
          project_id: project.id
        })

      count
    end

    sets = count.("test_impact_line_sets")
    refs = count.("test_impact_snapshot_lines")

    # Math.swift's content changed without changing the lines the tests ran.
    full_run(project, account, "c2", files(%{"Sources/Math.swift" => "m2"}))

    assert %{checkpoint: %{commit_sha: "c2"}} = Snapshots.at(project.id, "c2", "App", "")
    assert count.("test_impact_line_sets") == sets
    assert count.("test_impact_snapshot_lines") == 2 * refs
  end

  test "a changed file no evidence includes selects nothing, so the branch's previous run decides what it ran",
       %{project: project, account: account} do
    # Both pushes change Math.swift and add an image no evidence includes.
    changes = [changed("Sources/Math.swift", "m2"), changed("Resources/Image.png", "i1")]

    {:ok, %{run: previous_run}} = Runs.create(project, params("c2", changes))

    CoverageFixtures.run_with_coverage(project, account, files(%{"Sources/Math.swift" => "m2"}), %{
      git_commit_sha: "c2",
      git_branch: "feature",
      partial: true,
      test_impact_run_id: previous_run.id,
      test_modules: [
        %{
          name: "AppTests",
          status: "success",
          duration: 1,
          test_cases: [%{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 10}]
        }
      ],
      coverage_evidence: %{
        paths: @paths,
        scopes: [
          %{
            kind: "test",
            module: "AppTests",
            suite: "MathTests",
            name: "testAdd()",
            files: [0, 5],
            lines: [[1, 1], [1, 1]]
          }
        ]
      }
    })

    {_run, result} = decide(project, "c3", changes)
    assert %{overlay: %{commit_sha: "c2"}} = Snapshots.at(project.id, "c2", "App", "")

    assert by_name(project, result) == %{
             # The previous run ran it with the same Math.swift; the image no
             # evidence includes doesn't select it.
             "testAdd()" => {:skipped, :unaffected},
             "testSub()" => {:skipped, :unaffected},
             "testUpper()" => {:skipped, :unaffected},
             "sum()" => {:selected, :no_evidence},
             "testCore()" => {:skipped, :unaffected}
           }
  end

  test "a failure at a newer baseline stands against older evidence the branch's overlay keeps",
       %{project: project, account: account} do
    CoverageFixtures.seed_history(account, [CoverageFixtures.commit("p1", ["c1"], 5)])
    CoverageFixtures.seed_listing(account, "c2", @paths ++ ["Package.resolved"])
    test_case = fn name, suite, status -> %{name: name, test_suite_name: suite, status: status, duration: 10} end

    scope = fn suite, name, files ->
      %{
        kind: "test",
        module: "AppTests",
        suite: suite,
        name: name,
        files: files,
        lines: Enum.map(files, fn _ -> [1, 1] end)
      }
    end

    # Main's full run at c2 adds testDiv(), which shifts the numbers after it,
    # and testUpper() fails there.
    CoverageFixtures.run_with_coverage(project, account, files(), %{
      git_commit_sha: "c2",
      test_modules: [
        %{
          name: "AppTests",
          status: "failure",
          duration: 1,
          test_cases: [
            test_case.("testAdd()", "MathTests", "success"),
            test_case.("testDiv()", "MathTests", "success"),
            test_case.("testSub()", "MathTests", "success"),
            test_case.("testUpper()", "StringTests", "failure"),
            test_case.("sum()", "SumTests", "success")
          ]
        },
        %{
          name: "CoreTests",
          status: "success",
          duration: 1,
          test_cases: [test_case.("testCore()", "CoreSuite", "success")]
        }
      ],
      coverage_evidence: %{
        paths: @paths,
        scopes: [
          scope.("MathTests", "testAdd()", [0, 5]),
          scope.("MathTests", "testDiv()", [0]),
          scope.("MathTests", "testSub()", [1]),
          scope.("StringTests", "testUpper()", [2]),
          %{kind: "test", module: "CoreTests", suite: "CoreSuite", name: "testCore()", files: [3], lines: [[1, 1]]},
          %{kind: "target", module: "CoreTests", files: [3, 4], lines: [[1, 1], [1, 1]]}
        ]
      }
    })

    # Afterwards, the branch's previous push, against c1, runs testAdd() over
    # Math.swift at m2 and a new testMul(); testUpper() keeps c1's pass there.
    previous = [changed("Sources/Math.swift", "m2")]
    {:ok, %{run: previous_run}} = Runs.create(project, params("p1", previous))

    CoverageFixtures.run_with_coverage(project, account, files(%{"Sources/Math.swift" => "m2"}), %{
      git_commit_sha: "p1",
      git_branch: "feature",
      partial: true,
      test_impact_run_id: previous_run.id,
      test_modules: [
        %{
          name: "AppTests",
          status: "success",
          duration: 1,
          test_cases: [test_case.("testAdd()", "MathTests", "success"), test_case.("testMul()", "MathTests", "success")]
        }
      ],
      coverage_evidence: %{
        paths: @paths,
        scopes: [scope.("MathTests", "testAdd()", [0, 5]), scope.("MathTests", "testMul()", [0])]
      }
    })

    {run, result} = decide(project, "c3", previous, "c2")
    assert length(result.evidence) == 2

    assert by_name(project, result, "c2") == %{
             # Ran on the previous push's tree, with the same Math.swift.
             "testAdd()" => {:skipped, :unaffected},
             "testDiv()" => {:selected, :impacted},
             "testSub()" => {:skipped, :unaffected},
             # The overlay's pass is c1's, older than c2's failure.
             "testUpper()" => {:selected, :failed_last_run},
             "sum()" => {:selected, :no_evidence},
             "testCore()" => {:skipped, :unaffected}
           }

    # The skip list is read in c2's numbering, not the overlay's c1 one.
    snapshot = Snapshots.at(project.id, "c2", "App", "")
    tests = Candidate.evaluate(project.id, snapshot, [])
    named = Snapshots.names(project.id, snapshot, Enum.map(tests, & &1.idx))
    names = Map.new(tests, &{&1.test_case_id, named[&1.idx].name})

    assert project.id |> Carry.skipped_tests(run.id) |> Enum.map(&names[&1.test_case_id]) |> Enum.sort() ==
             ["testAdd()", "testCore()", "testSub()"]
  end

  test "lists the files a test depends on in a snapshot", %{project: project} do
    snapshot = Snapshots.at(project.id, "c1", "App", "")
    tests = Candidate.evaluate(project.id, snapshot, [])
    named = Snapshots.names(project.id, snapshot, Enum.map(tests, & &1.idx))
    names = Map.new(tests, &{named[&1.idx].name, &1.test_case_id})

    assert Snapshots.test_files(project.id, snapshot, names["testAdd()"]) == [
             %{path: "Sources/Math.swift", executed: true, target: false},
             %{path: @test_file, executed: true, target: false}
           ]

    assert Snapshots.test_files(project.id, snapshot, names["testCore()"]) == [
             %{path: "Sources/Boot.swift", executed: false, target: true},
             # testCore() executed it, so it isn't target-only.
             %{path: "Sources/Core.swift", executed: true, target: false}
           ]

    assert Snapshots.test_files(project.id, snapshot, Ecto.UUID.generate()) == nil
  end

  test "skips what the branch's previous run already ran against the same files, and not what it left stale",
       %{project: project, account: account} do
    # c2 changes Math.swift and Strings.swift; its selective run executes
    # testAdd() and sum(), which records no evidence.
    previous = [changed("Sources/Math.swift", "m2"), changed("Sources/Strings.swift", "s2")]
    {:ok, %{run: impact_run}} = Runs.create(project, params("c2", previous))

    CoverageFixtures.run_with_coverage(project, account, files(), %{
      git_commit_sha: "c2",
      git_branch: "feature",
      partial: true,
      test_impact_run_id: impact_run.id,
      test_modules: [
        %{
          name: "AppTests",
          status: "success",
          duration: 1,
          test_cases: [
            %{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 10},
            # Without evidence of its own, as at c1.
            %{name: "sum()", test_suite_name: "SumTests", status: "success", duration: 10}
          ]
        }
      ],
      coverage_evidence: %{
        paths: @paths,
        scopes: [
          %{
            kind: "test",
            module: "AppTests",
            suite: "MathTests",
            name: "testAdd()",
            files: [0, 5],
            lines: [[1, 1], [1, 1]]
          }
        ]
      }
    })

    # The overlay ends with the checkpoint it numbers its tests by.
    {overlay, checkpoint} =
      Snapshots.latest_branch_overlay(project.id, "feature", %{scheme: "App", platform: ""}, "c3", DateTime.utc_now())

    assert DateTime.compare(overlay.expires_at, checkpoint.expires_at) != :gt

    # A second full run at c1 writes c1 a newer checkpoint; the overlay
    # keeps the one it was written against.
    full_run(project, account, "c1", files())

    # c3 carries the same two blobs and changes Sub.swift too.
    {_run, result} = decide(project, "c3", previous ++ [changed("Sources/Sub.swift", "b3")])

    assert length(result.evidence) == 2

    assert by_name(project, result) == %{
             # Ran on c2's tree with Math.swift at m2 and passed.
             "testAdd()" => {:skipped, :unaffected},
             # Sub.swift changed since both candidates.
             "testSub()" => {:selected, :impacted},
             # c2 didn't run it although Strings.swift changed: stale there.
             "testUpper()" => {:selected, :impacted},
             # c2 ran it, but without evidence it's still unknown what it executed.
             "sum()" => {:selected, :no_evidence},
             "testCore()" => {:skipped, :unaffected}
           }
  end

  test "carries a test skipped through the branch's previous run from that run's evidence",
       %{project: project, account: account} do
    for sha <- ~w(c2 c3), do: CoverageFixtures.seed_listing(account, sha, @paths ++ ["Package.resolved"])
    test_case = fn name, suite -> %{name: name, test_suite_name: suite, status: "success", duration: 10} end

    # c2 changes Math.swift, now two lines, and Strings.swift; its selective
    # run executes only testAdd(), over both lines, so the overlay replaces it.
    previous = [changed("Sources/Math.swift", "m2"), changed("Sources/Strings.swift", "s2")]
    {:ok, %{run: previous_run}} = Runs.create(project, params("c2", previous))
    c2_blobs = %{"Sources/Math.swift" => "m2", "Sources/Strings.swift" => "s2"}

    with_math = fn files, count ->
      [CoverageFixtures.file("Sources/Math.swift", [count, count], git_blob_id: "m2") | tl(files)]
    end

    CoverageFixtures.run_with_coverage(project, account, with_math.(files(c2_blobs), 1), %{
      git_commit_sha: "c2",
      git_branch: "feature",
      partial: true,
      test_impact_run_id: previous_run.id,
      test_modules: [
        %{name: "AppTests", status: "success", duration: 1, test_cases: [test_case.("testAdd()", "MathTests")]}
      ],
      coverage_evidence: %{
        paths: @paths,
        scopes: [
          %{
            kind: "test",
            module: "AppTests",
            suite: "MathTests",
            name: "testAdd()",
            files: [0, 5],
            lines: [[1, 2], [1, 1]]
          }
        ]
      }
    })

    # c3 changes Sub.swift too. testAdd() is skipped through c2's run, where
    # it ran over Math.swift at m2, and testCore() through the baseline.
    {run, result} = decide(project, "c3", previous ++ [changed("Sources/Sub.swift", "b3")])
    assert %{"testAdd()" => {:skipped, :unaffected}, "testCore()" => {:skipped, :unaffected}} = by_name(project, result)

    c3_files = with_math.(files(Map.put(c2_blobs, "Sources/Sub.swift", "b3"), 0), 0)

    CoverageFixtures.run_with_coverage(project, account, c3_files, %{
      git_commit_sha: "c3",
      git_branch: "feature",
      partial: true,
      test_impact_run_id: run.id,
      test_modules: [
        %{
          name: "AppTests",
          status: "success",
          duration: 1,
          test_cases: [
            test_case.("testSub()", "MathTests"),
            test_case.("testUpper()", "StringTests"),
            test_case.("sum()", "SumTests")
          ]
        }
      ]
    })

    reported = Reported.compute(project, "c3")

    assert %{kind: "reported", skipped_tests_count: 2, carried_tests_count: 2, carried_from: ["c1", "c2"]} =
             reported

    assert Reported.carried_lines(project, reported) == %{
             "Sources/Core.swift" => [[1, 1]],
             "Sources/Math.swift" => [[1, 2]]
           }
  end

  describe "compose/3" do
    test "keeps the paths whose blobs differ between the two trees" do
      previous = [changed("A", "a2"), changed("B", "b2"), %{path: "C", status: "D", blob: "", affected_modules: []}]
      between = [%{path: "D", from: "d1", to: "d2"}, %{path: "B", from: "b1", to: "b1"}]
      current = [changed("A", "a2"), changed("B", "b3")]

      assert previous |> Decision.compose(between, current) |> Enum.map(&{&1.path, &1.status, &1.blob}) == [
               # B moved on; C was deleted only in the previous tree; D changed between the checkpoints.
               {"B", "M", "b3"},
               {"C", "M", nil},
               {"D", "M", "d2"}
             ]
    end
  end
end
