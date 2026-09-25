defmodule Tuist.Tests.Coverage.ReportedTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.ClickHouseRepo
  alias Tuist.KeyValueStore
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Reported
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  @tests [
    %{module: "AppTests", suite: "MathTests", name: "testAdd()"},
    %{module: "AppTests", suite: "TextTests", name: "testTrim()"}
  ]

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")

    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("base", [], 0),
      CoverageFixtures.commit("head", ["base"], 1)
    ])

    %{account: account, project: project}
  end

  defp file(path, counts, opts \\ []), do: CoverageFixtures.file(path, counts, opts)

  defp test_case(name, suite, status \\ "success"), do: %{name: name, test_suite_name: suite, status: status, duration: 1}

  defp modules(cases), do: [%{name: "AppTests", status: "success", duration: 1, test_cases: cases}]

  # The full run at the base: both tests ran, each with the lines it covered.
  defp base_run(project, account, opts \\ []) do
    CoverageFixtures.run_with_coverage(
      project,
      account,
      [
        file("Sources/Math.swift", [1, 1, 0]),
        file("Sources/Text.swift", [1, 1, 1, 0]),
        file("Tests/AppTests.swift", [1, 1], is_test: true)
      ],
      %{
        git_commit_sha: "base",
        test_modules:
          modules([
            test_case("testAdd()", "MathTests"),
            test_case("testTrim()", "TextTests", Keyword.get(opts, :trim_status, "success"))
          ]),
        enumerated_tests: @tests,
        coverage_evidence: %{
          paths: ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"],
          scopes: [
            %{
              kind: "test",
              module: "AppTests",
              suite: "MathTests",
              name: "testAdd()",
              files: [0, 2],
              lines: [[1, 2], [1, 1]]
            },
            %{
              kind: "test",
              module: "AppTests",
              suite: "TextTests",
              name: "testTrim()",
              files: [1, 2],
              lines: [Keyword.get(opts, :trim_lines, [1, 2]), [2, 2]]
            },
            %{kind: "suite", module: "AppTests", suite: "TextTests", name: "", files: [1], lines: [[3, 3]]}
          ]
        }
      }
    )
  end

  # The selective run at the head: only `testAdd()` ran, and Text.swift is
  # reported with nothing covered.
  defp head_run(project, account, files) do
    CoverageFixtures.run_with_coverage(project, account, files, %{
      git_commit_sha: "head",
      partial: true,
      test_modules: modules([test_case("testAdd()", "MathTests")]),
      enumerated_tests: @tests
    })
  end

  defp head_files(text_opts \\ []) do
    [
      file("Sources/Math.swift", [1, 1, 0]),
      file("Sources/Text.swift", [0, 0, 0, 0], text_opts),
      file("Tests/AppTests.swift", [1, 0], is_test: true)
    ]
  end

  test "carries a skipped test's lines, and its suite's, when every file it ran is unchanged", %{
    project: project,
    account: account
  } do
    base_run(project, account)
    head_run(project, account, head_files())

    assert project |> Reported.compute("head") |> Map.drop([:files, :carried_lines]) == %{
             kind: "reported",
             covered_lines: 5,
             executable_lines: 7,
             skipped_tests_count: 1,
             carried_tests_count: 1,
             gap_files_count: 0,
             carried_from: ["base"]
           }

    assert %{kind: "measured", covered_lines: 5, executable_lines: 7, skipped_tests_count: 0} =
             Reported.compute(project, "base")
  end

  test "carries the tests of a scheme selective testing skipped whole", %{project: project, account: account} do
    # Two schemes at the base, each running and enumerating its own test.
    CoverageFixtures.run_with_coverage(
      project,
      account,
      [file("Sources/Math.swift", [1, 1, 0]), file("Tests/AppTests.swift", [1, 1], is_test: true)],
      %{
        git_commit_sha: "base",
        scheme: "AppScheme",
        test_modules: modules([test_case("testAdd()", "MathTests")]),
        enumerated_tests: [Enum.at(@tests, 0)],
        coverage_evidence: %{
          paths: ["Sources/Math.swift", "Tests/AppTests.swift"],
          scopes: [
            %{
              kind: "test",
              module: "AppTests",
              suite: "MathTests",
              name: "testAdd()",
              files: [0, 1],
              lines: [[1, 2], [1, 1]]
            }
          ]
        }
      }
    )

    CoverageFixtures.run_with_coverage(
      project,
      account,
      [file("Sources/Text.swift", [1, 1, 1, 0])],
      %{
        git_commit_sha: "base",
        scheme: "TextScheme",
        test_modules: modules([test_case("testTrim()", "TextTests")]),
        enumerated_tests: [Enum.at(@tests, 1)],
        coverage_evidence: %{
          paths: ["Sources/Text.swift"],
          scopes: [
            %{kind: "test", module: "AppTests", suite: "TextTests", name: "testTrim()", files: [0], lines: [[1, 2]]},
            %{kind: "suite", module: "AppTests", suite: "TextTests", name: "", files: [0], lines: [[3, 3]]}
          ]
        }
      }
    )

    # At the head only AppScheme ran. TextScheme was skipped whole, so it
    # never built: its run carries no coverage and lists no candidates, and
    # nothing at the commit says `testTrim()` exists.
    CoverageFixtures.run_with_coverage(
      project,
      account,
      head_files(),
      %{
        git_commit_sha: "head",
        scheme: "AppScheme",
        partial: true,
        test_modules: modules([test_case("testAdd()", "MathTests")]),
        enumerated_tests: [Enum.at(@tests, 0)]
      }
    )

    CoverageFixtures.run_with_coverage(project, account, [], %{
      git_commit_sha: "head",
      scheme: "TextScheme",
      partial: true,
      test_modules: []
    })

    assert %{kind: "reported", skipped_tests_count: 1, carried_tests_count: 1, gap_files_count: 0, carried_from: ["base"]} =
             Reported.compute(project, "head")
  end

  # Two test targets at the base; at the head selective testing skipped
  # TextKitTests, and the generated workspace no longer had it, so the head
  # neither ran nor listed `testTrim()`.
  defp pruned_target_runs(project, account) do
    CoverageFixtures.run_with_coverage(
      project,
      account,
      [
        file("Sources/Math.swift", [1, 1, 0]),
        file("Sources/Text.swift", [1, 1, 1, 0]),
        file("Tests/AppTests.swift", [1, 1], is_test: true)
      ],
      %{
        git_commit_sha: "base",
        test_modules: [
          %{name: "AppTests", status: "success", duration: 1, test_cases: [test_case("testAdd()", "MathTests")]},
          %{name: "TextKitTests", status: "success", duration: 1, test_cases: [test_case("testTrim()", "TextTests")]}
        ],
        enumerated_tests: [
          %{module: "AppTests", suite: "MathTests", name: "testAdd()"},
          %{module: "TextKitTests", suite: "TextTests", name: "testTrim()"}
        ],
        coverage_evidence: %{
          paths: ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"],
          scopes: [
            %{
              kind: "test",
              module: "AppTests",
              suite: "MathTests",
              name: "testAdd()",
              files: [0, 2],
              lines: [[1, 2], [1, 1]]
            },
            %{kind: "test", module: "TextKitTests", suite: "TextTests", name: "testTrim()", files: [1], lines: [[1, 3]]}
          ]
        }
      }
    )

    CoverageFixtures.run_with_coverage(project, account, head_files(), %{
      git_commit_sha: "head",
      partial: true,
      test_modules: modules([test_case("testAdd()", "MathTests")]),
      enumerated_tests: [%{module: "AppTests", suite: "MathTests", name: "testAdd()"}]
    })
  end

  defp selective_testing(project, run, hits) do
    event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test", test_run_id: run.id)

    for hit <- hits do
      {target, hit, hash} =
        case hit do
          {target, hit} -> {target, hit, "#{target}-hash"}
          {target, hit, hash} -> {target, hit, hash}
        end

      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: target,
        selective_testing_hash: hash,
        selective_testing_hit: hit
      )
    end
  end

  test "carries the tests of a target selective testing skipped and the workspace left out", %{
    project: project,
    account: account
  } do
    head = pruned_target_runs(project, account)
    selective_testing(project, head, [{"AppTests", :miss}, {"TextKitTests", :local}])

    assert %{kind: "reported", skipped_tests_count: 1, carried_tests_count: 1, gap_files_count: 0, carried_from: ["base"]} =
             Reported.compute(project, "head")
  end

  test "inherits nothing for a target that is merely missing from the run", %{project: project, account: account} do
    head = pruned_target_runs(project, account)
    selective_testing(project, head, [{"AppTests", :miss}])

    assert %{skipped_tests_count: 0, carried_tests_count: 0} = Reported.compute(project, "head")
  end

  # TextKitTests at the base as a Swift Testing target without the
  # attribution trait: its test recorded no evidence of its own, only the
  # target's floor. At the head selective testing skipped it.
  defp target_only_runs(project, account, opts \\ []) do
    base =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [
          file("Sources/Math.swift", [1, 1, 0]),
          file("Sources/Text.swift", [1, 1, 1, 0]),
          file("Tests/AppTests.swift", [1, 1], is_test: true)
        ],
        %{
          git_commit_sha: "base",
          test_modules: [
            %{name: "AppTests", status: "success", duration: 1, test_cases: [test_case("testAdd()", "MathTests")]},
            %{
              name: "TextKitTests",
              status: "success",
              duration: 1,
              test_cases: [test_case("testTrim()", "TextTests", Keyword.get(opts, :trim_status, "success"))]
            }
          ],
          enumerated_tests: [
            %{module: "AppTests", suite: "MathTests", name: "testAdd()"},
            %{module: "TextKitTests", suite: "TextTests", name: "testTrim()"}
          ],
          coverage_evidence: %{
            paths: ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"],
            scopes: [
              %{
                kind: "test",
                module: "AppTests",
                suite: "MathTests",
                name: "testAdd()",
                files: [0, 2],
                lines: [[1, 2], [1, 1]]
              },
              %{kind: "target", module: "TextKitTests", suite: "", name: "", files: [1], lines: [[1, 3]]}
            ]
          }
        }
      )

    selective_testing(project, base, [{"AppTests", :miss, "app"}, {"TextKitTests", :miss, "text"}])

    head =
      CoverageFixtures.run_with_coverage(project, account, head_files(), %{
        git_commit_sha: "head",
        partial: true,
        test_modules: modules([test_case("testAdd()", "MathTests")]),
        enumerated_tests: [%{module: "AppTests", suite: "MathTests", name: "testAdd()"}]
      })

    selective_testing(project, head, [
      {"AppTests", :miss, "app-changed"},
      {"TextKitTests", :local, Keyword.get(opts, :head_hash, "text")}
    ])
  end

  test "carries a target selective testing skipped whole, from its floor, when its inputs hash the same", %{
    project: project,
    account: account
  } do
    target_only_runs(project, account)

    assert %{
             kind: "reported",
             covered_lines: 5,
             executable_lines: 7,
             skipped_tests_count: 1,
             carried_tests_count: 1,
             gap_files_count: 0,
             carried_from: ["base"]
           } = Reported.compute(project, "head")
  end

  test "reads the runs' selective-testing hashes by command event, once per set of runs", %{
    project: project,
    account: account
  } do
    target_only_runs(project, account)

    report = fn
      %Ecto.Query{from: %{source: {"xcode_targets", _schema}}, joins: joins} ->
        send(self(), {:xcode_targets_query, joins})

      _query ->
        :ok
    end

    stub(ClickHouseRepo, :all, fn query ->
      report.(query)
      call_original(ClickHouseRepo, :all, [query])
    end)

    stub(ClickHouseRepo, :all, fn query, opts ->
      report.(query)
      call_original(ClickHouseRepo, :all, [query, opts])
    end)

    assert %{kind: "reported", carried_tests_count: 1} = Reported.compute(project, "head")

    # The head's runs, then the runs the target's evidence comes from.
    assert_received {:xcode_targets_query, []}
    assert_received {:xcode_targets_query, []}
    refute_received {:xcode_targets_query, _joins}
  end

  test "carries no target whose inputs hashed differently where its evidence comes from", %{
    project: project,
    account: account
  } do
    target_only_runs(project, account, head_hash: "text-changed")

    assert %{kind: "partial", skipped_tests_count: 1, carried_tests_count: 0} = Reported.compute(project, "head")
  end

  test "carries no target a test failed in where its evidence comes from", %{project: project, account: account} do
    target_only_runs(project, account, trim_status: "failure")

    assert %{kind: "partial", skipped_tests_count: 1, carried_tests_count: 0} = Reported.compute(project, "head")
  end

  test "a run that measured nothing refolds its commit, and only a measured one", %{
    project: project,
    account: account
  } do
    base_run(project, account)
    head_run(project, account, head_files())

    # A scheme skipped whole never builds: its run reports no coverage at all,
    # and it can land after the completion signal already folded the commit.
    silent = fn sha ->
      {:ok, run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account.id,
          duration: 1,
          status: "success",
          scheme: "TextScheme",
          git_branch: "main",
          git_remote_url_origin: CoverageFixtures.remote_url(),
          git_commit_sha: sha,
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: []
        })

      run
    end

    silent.("unmeasured")
    refute_enqueued(worker: CommitWorker, args: %{project_id: project.id, git_commit_sha: "unmeasured"})

    silent.("head")
    assert_enqueued(worker: CommitWorker, args: %{project_id: project.id, git_commit_sha: "head"})
  end

  test "carries a commit whose every scheme was skipped whole", %{
    project: project,
    account: account
  } do
    base_run(project, account)

    # With nothing measured at the commit there are no coverage rows to read a
    # blob from, so the listing the client uploads is the only thing that says
    # the files are unchanged.
    CoverageFixtures.seed_listing(account, "head", [
      "Sources/Math.swift",
      "Sources/Text.swift",
      "Tests/AppTests.swift"
    ])

    # Nothing at the head measured anything: the scheme was skipped whole, so
    # it reports a run with no coverage and no candidates of its own.
    {:ok, _} =
      Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1,
        status: "success",
        scheme: "App",
        git_branch: "main",
        git_remote_url_origin: CoverageFixtures.remote_url(),
        git_commit_sha: "head",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: []
      })

    assert %{
             kind: "reported",
             skipped_tests_count: 2,
             carried_tests_count: 2,
             gap_files_count: 0,
             carried_from: ["base"]
           } = reported = Reported.compute(project, "head")

    # Everything the base measured, carried: its own figure.
    assert {reported.covered_lines, reported.executable_lines} == {5, 7}

    row = Commits.recompute(project, "head")
    assert row.covered_lines == 0
    assert row.schemes == []
    assert row.reported_kind == "reported"
    assert row.reported_coverage == 71.4

    # The commit measured nothing, so it would read as a different measured set
    # than its baseline; carrying everything forward makes it comparable again.
    assert Commits.fully_carried?(row)
  end

  test "a fully carried commit is in the branch's history and trend, and lists what it carried", %{
    project: project,
    account: account
  } do
    CoverageFixtures.seed_history(account, [], branch_heads: [{"main", "head"}])
    base_run(project, account)
    CoverageFixtures.seed_listing(account, "head", ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"])

    {:ok, _} =
      Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1,
        status: "success",
        scheme: "App",
        git_branch: "main",
        git_remote_url_origin: CoverageFixtures.remote_url(),
        git_commit_sha: "head",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: []
      })

    assert Commits.fully_carried?(Commits.recompute(project, "head"))

    assert %{"head" => _row} = Commits.by_shas(project.id, ["head"])
    assert "head" in Enum.map(Commits.all(project.id), & &1.git_commit_sha)

    assert [%{git_commit_sha: "base", coverage: 71.4}, %{git_commit_sha: "head", coverage: 71.4, chained: true}] =
             History.branch_points(project, "main")

    assert [%{git_commit_sha: "head", measured: true, coverage: 71.4} | _] =
             History.branch_history(project, "main").commits

    assert {[%{path: "Sources/Math.swift", covered_lines: 2}, %{path: "Sources/Text.swift", covered_lines: 3}], 2} =
             Commits.list_files(project.id, "head", 1, 10)

    assert [%{name: "App", files_count: 2, covered_lines: 5, executable_lines: 7}] = Commits.targets(project.id, "head")

    assert %{carried_lines: [1, 2, 3], covered_lines: 3} =
             Commits.file_detail(project.id, "head", "Sources/Text.swift")
  end

  test "carries nothing for a test one of whose files changed", %{project: project, account: account} do
    base_run(project, account)
    head_run(project, account, head_files(git_blob_id: "blob-changed"))

    assert %{kind: "partial", covered_lines: 2, executable_lines: 7, skipped_tests_count: 1, carried_tests_count: 0} =
             Reported.compute(project, "head")
  end

  test "a test that failed where its evidence comes from is a gap", %{project: project, account: account} do
    base_run(project, account, trim_status: "failure")
    head_run(project, account, head_files())

    assert %{kind: "partial", covered_lines: 2, carried_tests_count: 0} = Reported.compute(project, "head")
  end

  test "evidence without lines for a file that counts is a gap", %{project: project, account: account} do
    base_run(project, account, trim_lines: [])
    head_run(project, account, head_files())

    assert %{kind: "partial", covered_lines: 2, carried_tests_count: 0} = Reported.compute(project, "head")
  end

  test "the pages read what the commit's published version settled, until it is folded again", %{
    project: project,
    account: account
  } do
    {:ok, project} = Projects.update_project(project, %{tracked_file_globs: ["Package.resolved"]})
    base_run(project, account)
    head_run(project, account, head_files())

    repository_id = CoverageFixtures.repository_id(account)
    listing = fn blob -> [%{path: "Package.resolved", git_blob_id: blob, mode: 0o100644}] end
    Tuist.GitHistory.record_listing(repository_id, "base", listing.("one"), files_count: 1)
    Tuist.GitHistory.record_listing(repository_id, "head", listing.("one"), files_count: 1)
    Commits.recompute(project, "head")

    measured = Commits.merged_files(project.id, "head")

    carried = fn ->
      project |> Reported.merged_files("head", measured) |> Enum.find(&(&1.path == "Sources/Text.swift"))
    end

    assert %{covered_lines: 3} = carried.()

    # The tracked file changes at the commit: the published version still
    # says what it said, and a fold settles the new answer.
    Tuist.GitHistory.record_listing(repository_id, "head", listing.("two"), files_count: 1)
    assert %{covered_lines: 3} = carried.()

    Commits.recompute(project, "head")
    assert %{covered_lines: 0} = carried.()
  end

  test "the pages settle the reported coverage without taking the cache's lock", %{project: project, account: account} do
    base_run(project, account)
    head_run(project, account, head_files())
    Commits.recompute(project, "head")

    stub(KeyValueStore, :get_or_update, fn key, opts, fun ->
      if match?([:coverage_reported | _], key), do: send(self(), {:coverage_reported_opts, opts})
      fun.()
    end)

    Reported.merged_files(project, "head", Commits.merged_files(project.id, "head"))

    assert_received {:coverage_reported_opts, opts}
    assert Keyword.get(opts, :locking) == false
  end

  test "a changed tracked file carries nothing", %{project: project, account: account} do
    {:ok, project} = Projects.update_project(project, %{tracked_file_globs: ["Package.resolved"]})
    base_run(project, account)
    head_run(project, account, head_files())

    repository_id = CoverageFixtures.repository_id(account)
    listing = fn blob -> [%{path: "Package.resolved", git_blob_id: blob, mode: 0o100644}] end
    Tuist.GitHistory.record_listing(repository_id, "base", listing.("one"), files_count: 1)
    Tuist.GitHistory.record_listing(repository_id, "head", listing.("two"), files_count: 1)

    assert %{kind: "partial", carried_tests_count: 0} = Reported.compute(project, "head")

    Tuist.GitHistory.record_listing(repository_id, "head", listing.("one"), files_count: 1)
    assert %{kind: "reported", carried_tests_count: 1} = Reported.compute(project, "head")
  end

  test "keeps an unchanged file no run at the commit compiled, with what was carried into it", %{
    project: project,
    account: account
  } do
    base_run(project, account)
    CoverageFixtures.seed_listing(account, "head", ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"])

    head_run(project, account, [
      file("Sources/Math.swift", [1, 1, 0]),
      file("Tests/AppTests.swift", [1, 0], is_test: true)
    ])

    assert %{kind: "reported", covered_lines: 5, executable_lines: 7, gap_files_count: 0} =
             Reported.compute(project, "head")
  end

  test "an unbuilt file whose coverage came from tests the run never listed is a gap", %{
    project: project,
    account: account
  } do
    base_run(project, account)
    CoverageFixtures.seed_listing(account, "head", ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"])

    CoverageFixtures.run_with_coverage(
      project,
      account,
      [file("Sources/Math.swift", [1, 1, 0]), file("Tests/AppTests.swift", [1, 0], is_test: true)],
      %{
        git_commit_sha: "head",
        partial: true,
        test_modules: modules([test_case("testAdd()", "MathTests")]),
        enumerated_tests: [hd(@tests), %{module: "AppTests", suite: "MathTests", name: "testNew()"}]
      }
    )

    assert %{kind: "partial", covered_lines: 2, executable_lines: 7, skipped_tests_count: 1, gap_files_count: 1} =
             Reported.compute(project, "head")
  end

  test "a selective commit joins the trend with its reported coverage, and stays out of it with a gap", %{
    project: project,
    account: account
  } do
    CoverageFixtures.seed_history(account, [], branch_heads: [{"main", "head"}])
    base_run(project, account)
    head_run(project, account, head_files())

    assert [%{git_commit_sha: "base", coverage: 71.4}, %{git_commit_sha: "head", coverage: 71.4, measured_coverage: 28.6}] =
             History.branch_points(project, "main")

    head_run(project, account, head_files(git_blob_id: "blob-changed"))
    assert [%{git_commit_sha: "base"}] = History.branch_points(project, "main")
  end

  test "a carried commit lists its files and targets, and details a file, over its reported coverage", %{
    project: project,
    account: account
  } do
    base_run(project, account)
    CoverageFixtures.seed_listing(account, "head", ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"])

    head_run(project, account, [
      file("Sources/Math.swift", [1, 1, 0]),
      file("Tests/AppTests.swift", [1, 0], is_test: true)
    ])

    assert {[
              %{path: "Sources/Math.swift", covered_lines: 2},
              %{path: "Sources/Text.swift", covered_lines: 3, executable_lines: 4}
            ], 2} =
             Commits.list_files(project.id, "head", 1, 10)

    assert {[%{path: "Sources/Math.swift"}], 1} = Commits.list_files(project.id, "head", 1, 10, measured: true)
    assert [%{name: "App", files_count: 2, covered_lines: 5, executable_lines: 7}] = Commits.targets(project.id, "head")

    # No run at the commit compiled Text.swift: its lines come from the run the
    # skipped test last executed in, none of them executed here.
    assert %{
             lines: [{1, 0}, {2, 0}, {3, 0}, {4, 0}],
             carried_lines: [1, 2, 3],
             covered_lines: 3,
             executable_lines: 4,
             uncovered_ranges: [{4, 4}]
           } = Commits.file_detail(project.id, "head", "Sources/Text.swift")

    assert %{carried_lines: [], covered_lines: 2} = Commits.file_detail(project.id, "head", "Sources/Math.swift")
    assert Commits.file_detail(project.id, "head", "Sources/Text.swift", measured: true) == nil
  end

  test "is the observed figure when the runs listed no candidates", %{project: project, account: account} do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/Math.swift", [1, 0])], %{git_commit_sha: "head"})

    assert %{kind: "observed", covered_lines: 1, executable_lines: 2} = Reported.compute(project, "head")
    assert Reported.compute(project, "unknown") == nil
  end
end
