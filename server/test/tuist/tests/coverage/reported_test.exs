defmodule Tuist.Tests.Coverage.ReportedTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.KeyValueStore
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.GapReasons
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Reported
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")

    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("base", [], 0),
      CoverageFixtures.commit("head", ["base"], 1)
    ])

    # The carry rules are exercised without tracked files, whose default globs
    # need both commits' listings; the tests about tracked files use them.
    stub(GitHistory, :settings, fn project ->
      GitHistory |> call_original(:settings, [project]) |> Map.put(:tracked_file_globs, [])
    end)

    %{account: account, project: project}
  end

  defp track_default_files, do: stub(GitHistory, :settings, &call_original(GitHistory, :settings, [&1]))

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
        git_commit_sha: Keyword.get(opts, :sha, "base"),
        scheme: Keyword.get(opts, :scheme, "App"),
        test_modules:
          modules([
            test_case("testAdd()", "MathTests"),
            test_case("testTrim()", "TextTests", Keyword.get(opts, :trim_status, "success"))
          ]),
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
      skip_test_identifiers: ["AppTests/TextTests/testTrim()"]
    })
  end

  defp reasons(%{gap_reasons: mask}), do: GapReasons.decode(mask)

  # A skipped test without evidence of its own: what the base's run collected
  # tells why.
  defp missing_evidence_runs(project, account, status, target_scope?, opts \\ []) do
    target = %{kind: "target", module: "AppTests", suite: "", name: "", files: [0, 1], lines: [[1, 2], [1, 3]]}

    CoverageFixtures.run_with_coverage(
      project,
      account,
      [file("Sources/Math.swift", [1, 1, 0]), file("Sources/Text.swift", [1, 1, 1, 0])],
      Map.merge(
        %{
          git_commit_sha: "base",
          test_modules: modules([test_case("testAdd()", "MathTests"), test_case("testTrim()", "TextTests")]),
          coverage_evidence:
            Map.merge(
              %{
                paths: ["Sources/Math.swift", "Sources/Text.swift"],
                scopes:
                  [
                    %{
                      kind: "test",
                      module: "AppTests",
                      suite: "MathTests",
                      name: "testAdd()",
                      files: [0],
                      lines: [[1, 2]]
                    }
                  ] ++
                    if(target_scope?, do: [target], else: []),
                overlapped_tests: Keyword.get(opts, :overlapped_tests, [])
              },
              if(status, do: %{status: status}, else: %{})
            )
        },
        Map.new(Keyword.take(opts, [:ran_at]))
      )
    )

    head_run(project, account, head_files())
    Reported.compute(project, "head")
  end

  test "tells why a skipped test without evidence of its own is a gap", %{project: project, account: account} do
    assert %{kind: "partial", carried_tests_count: 0} = reported = missing_evidence_runs(project, account, nil, false)
    assert reasons(reported) == [:collection_off]
  end

  test "a target that recorded nothing where evidence was collected doesn't link the package", %{
    project: project,
    account: account
  } do
    assert reasons(missing_evidence_runs(project, account, "collected", false)) == [:not_linked]
    assert [%{coverage_evidence_status: "collected"}] = Commits.runs(project.id, "base")
  end

  test "a test of a target that recorded evidence has no attribution of its own", %{project: project, account: account} do
    assert reasons(missing_evidence_runs(project, account, "collected", true)) == [:no_evidence]
  end

  test "a test recorded only as overlapping another has no attribution because of the overlap", %{
    project: project,
    account: account
  } do
    overlapped = [%{module: "AppTests", suite: "TextTests", name: "testTrim()"}]

    assert reasons(missing_evidence_runs(project, account, "collected", true, overlapped_tests: overlapped)) ==
             [:overlapped]
  end

  test "evidence collected past the file retention has expired", %{project: project, account: account} do
    ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -100 * 86_400, :second)

    assert reasons(missing_evidence_runs(project, account, "collected", true, ran_at: ran_at)) == [:evidence_expired]
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
             gap_reasons: 0,
             carried_from: ["base"]
           }

    assert %{kind: "measured", covered_lines: 5, executable_lines: 7, skipped_tests_count: 0} =
             Reported.compute(project, "base")
  end

  test "carries a skipped test's lines from the nearest ancestor run that holds its evidence", %{
    project: project,
    account: account
  } do
    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("root", [], -1),
      CoverageFixtures.commit("base", ["root"], 0)
    ])

    root = base_run(project, account, sha: "root", trim_lines: [1, 2, 4])
    base_run(project, account)
    head_run(project, account, head_files())

    test_pid = self()

    # A read of evidence lines merges them per file in ClickHouse.
    report = fn query ->
      query = inspect(query)
      if query =~ "groupUniqArrayArray", do: send(test_pid, {:evidence_lines, query})
    end

    stub(ClickHouseRepo, :all, fn query ->
      report.(query)
      call_original(ClickHouseRepo, :all, [query])
    end)

    stub(ClickHouseRepo, :all, fn query, opts ->
      report.(query)
      call_original(ClickHouseRepo, :all, [query, opts])
    end)

    assert %{kind: "reported", covered_lines: 5, carried_tests_count: 1, carried_from: ["base"]} =
             Reported.compute(project, "head")

    queries = Stream.repeatedly(fn -> receive(do: ({:evidence_lines, query} -> query), after: (0 -> nil)) end)
    queries = Enum.take_while(queries, & &1)

    assert queries != []
    refute Enum.any?(queries, &(&1 =~ root.id))
  end

  test "a scheme whose runs took targets from the binary cache, none of them from sources, is partial", %{
    project: project,
    account: account
  } do
    head = CoverageFixtures.run_with_coverage(project, account, head_files(), %{git_commit_sha: "head"})
    binary_cache(project, head, ["Core"])

    assert %{kind: "partial", covered_lines: 2, executable_lines: 7} = reported = Reported.compute(project, "head")
    # No ancestor measured the scheme, so what the run didn't build is unknown too.
    assert reasons(reported) == [:unbuilt_file_unknown, :uninstrumented_code]
  end

  test "a run that took only remote packages from the binary cache is measured", %{project: project, account: account} do
    head = CoverageFixtures.run_with_coverage(project, account, head_files(), %{git_commit_sha: "head"})
    binary_cache(project, head, ["Alamofire"], external_hash: "alamofire-revision")

    assert %{kind: "measured", gap_reasons: 0} = Reported.compute(project, "head")
  end

  test "a scheme with a run that ran every test from sources is measured, whatever its other runs took from the cache",
       %{project: project, account: account} do
    cached = CoverageFixtures.run_with_coverage(project, account, head_files(), %{git_commit_sha: "head", partial: true})
    binary_cache(project, cached, ["Core"])
    CoverageFixtures.run_with_coverage(project, account, head_files(), %{git_commit_sha: "head"})

    assert %{kind: "measured", gap_reasons: 0} = Reported.compute(project, "head")
  end

  test "carries the tests of a scheme selective testing skipped whole", %{project: project, account: account} do
    # Two schemes at the base, each running its own test.
    CoverageFixtures.run_with_coverage(
      project,
      account,
      [file("Sources/Math.swift", [1, 1, 0]), file("Tests/AppTests.swift", [1, 1], is_test: true)],
      %{
        git_commit_sha: "base",
        scheme: "AppScheme",
        test_modules: modules([test_case("testAdd()", "MathTests")]),
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
    # never built: its run carries no coverage, and only its target's hit
    # says what it skipped.
    CoverageFixtures.run_with_coverage(
      project,
      account,
      head_files(),
      %{
        git_commit_sha: "head",
        scheme: "AppScheme",
        test_modules: modules([test_case("testAdd()", "MathTests")])
      }
    )

    skipped =
      CoverageFixtures.run_with_coverage(project, account, [], %{
        git_commit_sha: "head",
        scheme: "TextScheme",
        partial: true,
        test_modules: []
      })

    selective_testing(project, skipped, [{"AppTests", :local}])

    assert %{kind: "reported", skipped_tests_count: 1, carried_tests_count: 1, gap_files_count: 0, carried_from: ["base"]} =
             Reported.compute(project, "head")

    # No scheme ran partially, yet the figure carries testTrim()'s lines: the
    # commit's files add up to it.
    assert %{partial_schemes: [], reported_covered_lines: 5} = summary = Commits.recompute(project, "head")
    assert Commits.carried?(summary)
    {files, _count} = Commits.list_files(project.id, "head", 1, 10)
    assert {"Sources/Text.swift", 3, 4} in Enum.map(files, &{&1.path, &1.covered_lines, &1.executable_lines})
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
      test_modules: modules([test_case("testAdd()", "MathTests")])
    })
  end

  # Targets the run took from the binary cache: prebuilt, without coverage counters.
  defp binary_cache(project, run, targets, opts \\ []) do
    event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test", test_run_id: run.id)

    for target <- targets do
      XcodeFixtures.xcode_target_fixture([command_event_id: event.id, name: target, binary_cache_hit: :local] ++ opts)
    end
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
          coverage_evidence: target_only_evidence(Keyword.get(opts, :untracked, false))
        }
      )

    selective_testing(project, base, [{"AppTests", :miss, "app"}, {"TextKitTests", :miss, "text"}])

    case Keyword.get(opts, :head, :measured) do
      :measured -> target_only_head(project, account, opts)
      :skipped -> skipped_head(project, account, [{"AppTests", :local, "app"}, {"TextKitTests", :local, "text"}])
    end
  end

  # With `untracked`, both tests also executed a file in a submodule: the
  # repository's Git tracks none of its files, so no run reports it and no
  # listing holds its blob.
  defp target_only_evidence(untracked) do
    {paths, extra, extra_lines} =
      if untracked, do: {["Vendor/Private/Sources/Secret.swift"], [3], [[1, 1]]}, else: {[], [], []}

    %{
      paths: ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"] ++ paths,
      scopes: [
        %{
          kind: "test",
          module: "AppTests",
          suite: "MathTests",
          name: "testAdd()",
          files: [0, 2] ++ extra,
          lines: [[1, 2], [1, 1]] ++ extra_lines
        },
        %{
          kind: "target",
          module: "TextKitTests",
          suite: "",
          name: "",
          files: [1] ++ extra,
          lines: [[1, 3]] ++ extra_lines
        }
      ]
    }
  end

  # The scheme skipped whole at the head: its run measured nothing and listed
  # no candidates, and only its targets' hits say what it skipped.
  defp skipped_head(project, account, hits) do
    CoverageFixtures.seed_listing(account, "head", ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"])

    {:ok, head} =
      Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1,
        status: "success",
        scheme: "App",
        git_branch: "feature/skipped",
        git_remote_url_origin: CoverageFixtures.remote_url(),
        git_commit_sha: "head",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: []
      })

    selective_testing(project, head, hits)
  end

  defp target_only_head(project, account, opts) do
    head =
      CoverageFixtures.run_with_coverage(project, account, head_files(), %{
        git_commit_sha: "head",
        partial: true,
        test_modules: modules([test_case("testAdd()", "MathTests")])
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
      %Ecto.Query{from: %{source: {"xcode_targets", _schema}}, joins: joins} = query ->
        if inspect(query) =~ "selective_testing_hash", do: send(self(), {:xcode_targets_query, joins})

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

  test "walks no ancestor window, and reads tracked files only where evidence comes from", %{
    project: project,
    account: account
  } do
    track_default_files()
    target_only_runs(project, account)

    # An older measured commit the evidence never comes from.
    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("root", [], -1),
      CoverageFixtures.commit("base", ["root"], 0)
    ])

    CoverageFixtures.run_with_coverage(project, account, [file("Sources/Math.swift", [1, 1, 0])], %{
      git_commit_sha: "root"
    })

    repository_id = CoverageFixtures.repository_id(account)
    listing = [%{path: "Package.resolved", git_blob_id: "one", mode: 0o100644}]
    for sha <- ["root", "base", "head"], do: GitHistory.record_listing(repository_id, sha, listing, files_count: 1)

    test_pid = self()

    stub(GitHistory, :ancestors, fn repository_id, sha ->
      send(test_pid, :window_walk)
      call_original(GitHistory, :ancestors, [repository_id, sha])
    end)

    stub(GitHistory, :tracked_files, fn project, repository_id, sha ->
      send(test_pid, {:tracked_files, sha})
      call_original(GitHistory, :tracked_files, [project, repository_id, sha])
    end)

    assert %{kind: "reported", carried_tests_count: 1} = Reported.compute(project, "head")

    refute_received :window_walk
    refute_received {:tracked_files, "root"}
  end

  test "carries a target selective testing skipped whole when its scheme was skipped whole", %{
    project: project,
    account: account
  } do
    target_only_runs(project, account, head: :skipped)

    assert %{
             kind: "reported",
             covered_lines: 5,
             executable_lines: 7,
             skipped_tests_count: 2,
             carried_tests_count: 2,
             gap_files_count: 0,
             carried_from: ["base"]
           } = Reported.compute(project, "head")
  end

  test "carries a target of a scheme skipped whole beside a scheme that measured", %{
    project: project,
    account: account
  } do
    base_app =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [file("Sources/Math.swift", [1, 1, 0]), file("Tests/AppTests.swift", [1, 1], is_test: true)],
        %{
          git_commit_sha: "base",
          test_modules: modules([test_case("testAdd()", "MathTests")]),
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

    base_text =
      CoverageFixtures.run_with_coverage(project, account, [file("Sources/Text.swift", [1, 1, 1, 0])], %{
        git_commit_sha: "base",
        scheme: "TextScheme",
        test_modules: [
          %{name: "TextKitTests", status: "success", duration: 1, test_cases: [test_case("testTrim()", "TextTests")]}
        ],
        coverage_evidence: %{
          paths: ["Sources/Text.swift"],
          scopes: [%{kind: "target", module: "TextKitTests", suite: "", name: "", files: [0], lines: [[1, 3]]}]
        }
      })

    selective_testing(project, base_app, [{"AppTests", :miss, "app"}])
    selective_testing(project, base_text, [{"TextKitTests", :miss, "text"}])

    CoverageFixtures.seed_listing(account, "head", ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"])

    head =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [file("Sources/Math.swift", [1, 1, 0]), file("Tests/AppTests.swift", [1, 1], is_test: true)],
        %{
          git_commit_sha: "head",
          test_modules: modules([test_case("testAdd()", "MathTests")])
        }
      )

    selective_testing(project, head, [{"AppTests", :miss, "app-changed"}])

    {:ok, silent} =
      Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1,
        status: "success",
        scheme: "TextScheme",
        git_branch: "main",
        git_remote_url_origin: CoverageFixtures.remote_url(),
        git_commit_sha: "head",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: []
      })

    selective_testing(project, silent, [{"TextKitTests", :local, "text"}])

    assert %{skipped_tests_count: 1, carried_tests_count: 1, carried_from: ["base"]} = Reported.compute(project, "head")
  end

  test "carries what executed a file the repository's Git does not track, such as a submodule's", %{
    project: project,
    account: account
  } do
    target_only_runs(project, account, head: :skipped, untracked: true)

    assert %{
             kind: "reported",
             covered_lines: 5,
             executable_lines: 7,
             carried_tests_count: 2,
             gap_files_count: 0
           } = Reported.compute(project, "head")
  end

  test "carries each of more skipped tests than one query names, from their recorded versions", %{
    project: project,
    account: account
  } do
    names = Enum.map(1..600, &"test#{&1}()")

    base =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [file("Sources/Math.swift", [1, 1, 0]), file("Tests/AppTests.swift", [1, 1], is_test: true)],
        %{
          git_commit_sha: "base",
          test_modules: modules(Enum.map(names, &test_case(&1, "MathTests"))),
          coverage_evidence: %{
            paths: ["Sources/Math.swift", "Tests/AppTests.swift"],
            scopes:
              Enum.map(
                names,
                &%{kind: "test", module: "AppTests", suite: "MathTests", name: &1, files: [0, 1], lines: [[1, 2], [1, 1]]}
              )
          }
        }
      )

    # The target's inputs changed, so its tests carry one by one.
    selective_testing(project, base, [{"AppTests", :miss, "app"}])
    skipped_head(project, account, [{"AppTests", :local, "app-changed"}])

    test_pid = self()

    stub(ClickHouseRepo, :all, fn query ->
      # Which runs hold the tests' evidence: the walk's question.
      if inspect(query) =~ "argMin" or
           (inspect(query) =~ ~s(scope_kind == ^"test") and inspect(query) =~ "select: {c0.scope_id, c0.test_run_id}"),
         do: send(test_pid, :walked_test_evidence)

      call_original(ClickHouseRepo, :all, [query])
    end)

    assert %{kind: "reported", skipped_tests_count: 600, carried_tests_count: 600, carried_from: ["base"]} =
             Reported.compute(project, "head")

    # The versions say where each test comes from: no run is searched for its evidence.
    refute_received :walked_test_evidence
  end

  # The base ran AppTests' testAdd() from its test file, and its hashes landed
  # after its fold, so nothing is recorded under them: at the head, which
  # skipped AppTests with a new hash, the target's tests come from the base.
  # `head_test_files` are the head's test files with their blobs.
  defp baseline_lists_runs(project, account, head_test_files) do
    repository_id = CoverageFixtures.repository_id(account)
    sources = [{"Sources/Math.swift", "blob-Sources/Math.swift"}, {"Sources/Text.swift", "blob-Sources/Text.swift"}]
    listing = fn files -> Enum.map(files, fn {path, blob} -> %{path: path, git_blob_id: blob, mode: 0o100644} end) end
    base_files = sources ++ [{"Tests/AppTests.swift", "blob-Tests/AppTests.swift"}]
    GitHistory.record_listing(repository_id, "base", listing.(base_files), files_count: length(base_files))

    GitHistory.record_listing(repository_id, "head", listing.(sources ++ head_test_files),
      files_count: 2 + length(head_test_files)
    )

    base =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [
          file("Sources/Math.swift", [1, 1, 0]),
          file("Tests/AppTests.swift", [1, 1], is_test: true, targets: ["AppTests.xctest"])
        ],
        %{
          git_commit_sha: "base",
          test_modules: modules([test_case("testAdd()", "MathTests")]),
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

    selective_testing(project, base, [{"AppTests", :miss, "app"}])

    {:ok, head} =
      Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1,
        status: "success",
        scheme: "App",
        git_branch: "feature/lists",
        git_remote_url_origin: CoverageFixtures.remote_url(),
        git_commit_sha: "head",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: []
      })

    selective_testing(project, head, [{"AppTests", :local, "app-new"}])
  end

  test "takes a skipped target's tests from the baseline while its test files are unchanged", %{
    project: project,
    account: account
  } do
    baseline_lists_runs(project, account, [{"Tests/AppTests.swift", "blob-Tests/AppTests.swift"}])

    assert %{skipped_tests_count: 1, carried_tests_count: 1, carried_from: ["base"]} = Reported.compute(project, "head")
  end

  test "a skipped target whose test files changed since the baseline is a gap", %{project: project, account: account} do
    baseline_lists_runs(project, account, [{"Tests/AppTests.swift", "blob-changed"}])

    assert %{kind: "partial", skipped_tests_count: 0} = reported = Reported.compute(project, "head")
    assert :test_list_changed in reasons(reported)
  end

  test "a skipped target with a test file added beside its own since the baseline is a gap", %{
    project: project,
    account: account
  } do
    baseline_lists_runs(project, account, [
      {"Tests/AppTests.swift", "blob-Tests/AppTests.swift"},
      {"Tests/NewTests.swift", "blob-Tests/NewTests.swift"}
    ])

    assert %{kind: "partial", skipped_tests_count: 0} = reported = Reported.compute(project, "head")
    assert :test_list_changed in reasons(reported)
  end

  test "carries a test from the run whose version of it the commit reproduces, on another branch", %{
    project: project,
    account: account
  } do
    CoverageFixtures.seed_history(account, [CoverageFixtures.commit("s1", ["base"], 2)])

    evidence = %{
      paths: ["Sources/Math.swift", "Tests/AppTests.swift"],
      scopes: [
        %{kind: "test", module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0, 1], lines: [[1, 2], [1, 1]]}
      ]
    }

    # The base ran testAdd() over a Math.swift the head no longer has; a
    # branch off it ran it over the head's.
    for {sha, blob} <- [{"base", "blob-before"}, {"s1", "blob-Sources/Math.swift"}] do
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [file("Sources/Math.swift", [1, 1, 0], git_blob_id: blob), file("Tests/AppTests.swift", [1, 1], is_test: true)],
        %{git_commit_sha: sha, test_modules: modules([test_case("testAdd()", "MathTests")]), coverage_evidence: evidence}
      )
    end

    # The target's inputs changed, so its tests carry one by one.
    skipped_head(project, account, [{"AppTests", :local, "app-changed"}])

    assert %{skipped_tests_count: 1, carried_tests_count: 1, carried_from: ["s1"]} = Reported.compute(project, "head")
  end

  # TextKitTests run whole on a branch off the base, then folded once its
  # hashes landed, so the run is recorded as the target's source.
  defp recorded_source(project, account, text_opts \\ []) do
    CoverageFixtures.seed_history(account, [CoverageFixtures.commit("s1", ["base"], 2)])

    run =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [file("Sources/Text.swift", [1, 1, 1, 0], text_opts), file("Tests/AppTests.swift", [1, 1], is_test: true)],
        %{
          git_commit_sha: "s1",
          git_branch: "feature/text",
          recompute: false,
          test_modules: [
            %{name: "TextKitTests", status: "success", duration: 1, test_cases: [test_case("testTrim()", "TextTests")]}
          ],
          coverage_evidence: %{
            paths: ["Sources/Text.swift", "Tests/AppTests.swift"],
            scopes: [
              %{kind: "target", module: "TextKitTests", suite: "", name: "", files: [0, 1], lines: [[1, 3], [1, 1]]}
            ]
          }
        }
      )

    selective_testing(project, run, [{"TextKitTests", :miss, "text"}])
    CoverageFixtures.recompute_commit(run)
    run
  end

  test "carries a target from the run recorded under the hash it was skipped with, on another branch", %{
    project: project,
    account: account
  } do
    recorded_source(project, account)
    skipped_head(project, account, [{"TextKitTests", :local, "text"}])

    test_pid = self()

    stub(ClickHouseRepo, :all, fn query ->
      # Which runs hold the target's evidence: the walk's question.
      if inspect(query) =~ ~s(scope_kind == ^"target") and inspect(query) =~ "select: {c0.scope_id, c0.test_run_id}",
        do: send(test_pid, :walked_target_evidence)

      call_original(ClickHouseRepo, :all, [query])
    end)

    # The branch isn't an ancestor: walking the history alone finds no source.
    assert %{skipped_tests_count: 1, carried_tests_count: 1, carried_from: ["s1"]} = Reported.compute(project, "head")
    refute_received :walked_target_evidence
  end

  test "carries a recorded target although a file it executed has another blob: the hash is trusted", %{
    project: project,
    account: account
  } do
    recorded_source(project, account, git_blob_id: "blob-before")
    skipped_head(project, account, [{"TextKitTests", :local, "text"}])

    assert %{skipped_tests_count: 1, carried_tests_count: 1, carried_from: ["s1"]} = Reported.compute(project, "head")
  end

  test "carries no target recorded under another hash", %{project: project, account: account} do
    recorded_source(project, account)
    skipped_head(project, account, [{"TextKitTests", :local, "text-changed"}])

    assert %{carried_tests_count: 0} = Reported.compute(project, "head")
  end

  test "falls back to the baseline for a target with no recorded source", %{project: project, account: account} do
    # The base's hashes landed after its fold, so nothing recorded it.
    target_only_runs(project, account, head: :skipped)

    test_pid = self()

    stub(ClickHouseRepo, :all, fn query ->
      if inspect(query) =~ ~s(scope_kind == ^"target") and inspect(query) =~ "select: {c0.scope_id, c0.test_run_id}",
        do: send(test_pid, :walked_target_evidence)

      call_original(ClickHouseRepo, :all, [query])
    end)

    assert %{kind: "reported", carried_tests_count: 2, carried_from: ["base"]} = Reported.compute(project, "head")
    assert_received :walked_target_evidence
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

    assert %{kind: "partial", skipped_tests_count: 1, carried_tests_count: 0} =
             reported = Reported.compute(project, "head")

    assert reasons(reported) == [:test_failed]
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
    # it reports a run with no coverage, and its target's hit.
    {:ok, skipped} =
      Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1,
        status: "success",
        scheme: "App",
        git_branch: "feature/skipped",
        is_pull_request: true,
        pull_request_number: 9,
        base_branch: "main",
        git_remote_url_origin: CoverageFixtures.remote_url(),
        git_commit_sha: "head",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: []
      })

    selective_testing(project, skipped, [{"AppTests", :local}])

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

    # It is on its branch and its pull request, as its runs said, like a
    # measured commit.
    assert %{git_branch: "feature/skipped", pull_request_number: 9, base_branch: "main"} = row
    assert %{git_commit_sha: "head"} = History.head_commit(project, "feature/skipped")
  end

  test "a fully carried commit is in the branch's history and trend, and lists what it carried", %{
    project: project,
    account: account
  } do
    CoverageFixtures.seed_history(account, [], branch_heads: [{"main", "head"}])
    base_run(project, account)
    CoverageFixtures.seed_listing(account, "head", ["Sources/Math.swift", "Sources/Text.swift", "Tests/AppTests.swift"])

    {:ok, skipped} =
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

    selective_testing(project, skipped, [{"AppTests", :local}])
    assert Commits.fully_carried?(Commits.recompute(project, "head"))

    assert %{"head" => _row} = Commits.by_shas(project.id, ["head"])
    assert "head" in Enum.map(Commits.all(project.id), & &1.git_commit_sha)

    assert [%{git_commit_sha: "head", measured: true, coverage: 71.4}, %{git_commit_sha: "base", coverage: 71.4}] =
             History.commit_cursor_page(project, "main").commits

    assert %{git_commit_sha: "head", coverage: 71.4} = History.head_commit(project, "main")

    assert {[%{path: "Sources/Math.swift", covered_lines: 2}, %{path: "Sources/Text.swift", covered_lines: 3}], 2} =
             Commits.list_files(project.id, "head", 1, 10)

    assert {[%{path: "Sources/Text.swift"}, %{path: "Sources/Math.swift"}], 2} =
             Commits.list_files(project.id, "head", 1, 10, sort: {:path, :desc})

    assert {[%{path: "Sources/Text.swift"}], 1} = Commits.list_files(project.id, "head", 1, 10, search: "text")

    assert [%{name: "App", files_count: 2, covered_lines: 5, executable_lines: 7}] = Commits.targets(project.id, "head")

    assert %{carried_lines: [1, 2, 3], covered_lines: 3, executable_lines: text_lines} =
             Commits.file_detail(project.id, "head", "Sources/Text.swift")

    # Its files compare with the base's as they read with what was carried in.
    {base_files, _} = Commits.list_files(project.id, "base", 1, 10)
    {head_files, _} = Commits.list_files(project.id, "head", 1, 10)
    base_by_path = Map.new(base_files, &{&1.path, &1})

    expected =
      for file <- head_files,
          previous = base_by_path[file.path],
          change =
            Float.round(
              Coverage.percentage(file.covered_lines, file.executable_lines) -
                Coverage.percentage(previous.covered_lines, previous.executable_lines),
              1
            ),
          change != 0.0,
          do: {file.path, change}

    assert project.id |> Commits.changed_files("base", "head", 5) |> Enum.map(&{&1.path, &1.change}) |> Enum.sort() ==
             Enum.sort(expected)

    # The file's trend ends on the figure its page shows, carried lines included,
    # though no run at the head compiled it.
    for sha <- ~w(base head), do: Commits.signal_complete(project, sha)
    %{points: points} = History.trend_points(project, "main")

    assert %{git_commit_sha: "head", covered_lines: 3, executable_lines: ^text_lines} =
             project |> History.file_points("Sources/Text.swift", points) |> List.last()
  end

  test "carries nothing for a test one of whose files changed", %{project: project, account: account} do
    base_run(project, account)
    head_run(project, account, head_files(git_blob_id: "blob-changed"))

    assert %{kind: "partial", covered_lines: 2, executable_lines: 7, skipped_tests_count: 1, carried_tests_count: 0} =
             reported = Reported.compute(project, "head")

    assert reasons(reported) == [:executed_file_changed]
    assert %{gap_reasons: gap_reasons} = Commits.summary(project.id, "head")
    assert GapReasons.decode(gap_reasons) == [:executed_file_changed]
  end

  test "a test that failed where its evidence comes from is a gap", %{project: project, account: account} do
    base_run(project, account, trim_status: "failure")
    head_run(project, account, head_files())

    assert %{kind: "partial", covered_lines: 2, carried_tests_count: 0} = reported = Reported.compute(project, "head")
    assert reasons(reported) == [:test_failed]
  end

  test "evidence without lines for a file that counts is a gap", %{project: project, account: account} do
    base_run(project, account, trim_lines: [])
    head_run(project, account, head_files())

    assert %{kind: "partial", covered_lines: 2, carried_tests_count: 0} = reported = Reported.compute(project, "head")
    assert reasons(reported) == [:evidence_without_lines]
  end

  test "the pages read what the commit's published version settled, until it is folded again", %{
    project: project,
    account: account
  } do
    track_default_files()
    base_run(project, account)
    head_run(project, account, head_files())

    repository_id = CoverageFixtures.repository_id(account)
    listing = fn blob -> [%{path: "Package.resolved", git_blob_id: blob, mode: 0o100644}] end
    GitHistory.record_listing(repository_id, "base", listing.("one"), files_count: 1)
    GitHistory.record_listing(repository_id, "head", listing.("one"), files_count: 1)
    Commits.recompute(project, "head")

    measured = Commits.merged_files(project.id, "head")

    carried = fn ->
      project |> Reported.merged_files("head", measured) |> Enum.find(&(&1.path == "Sources/Text.swift"))
    end

    assert %{covered_lines: 3} = carried.()

    # The tracked file changes at the commit: the published version still
    # says what it said, and a fold settles the new answer.
    GitHistory.record_listing(repository_id, "head", listing.("two"), files_count: 1)
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
    track_default_files()
    base_run(project, account)
    head_run(project, account, head_files())

    repository_id = CoverageFixtures.repository_id(account)
    listing = fn blob -> [%{path: "Package.resolved", git_blob_id: blob, mode: 0o100644}] end
    GitHistory.record_listing(repository_id, "base", listing.("one"), files_count: 1)
    GitHistory.record_listing(repository_id, "head", listing.("two"), files_count: 1)

    assert %{kind: "partial", carried_tests_count: 0} = reported = Reported.compute(project, "head")
    assert reasons(reported) == [:tracked_file_changed]

    GitHistory.record_listing(repository_id, "head", listing.("one"), files_count: 1)
    assert %{kind: "reported", carried_tests_count: 1} = Reported.compute(project, "head")
  end

  test "a commit that changes a tracked file carries nothing without reading any evidence", %{
    project: project,
    account: account
  } do
    track_default_files()

    # The head undoes the base's change, so the root's evidence would match
    # it again; it is not carried for.
    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("root", [], -1),
      CoverageFixtures.commit("base", ["root"], 0)
    ])

    base_run(project, account, sha: "root")
    head_run(project, account, head_files())

    repository_id = CoverageFixtures.repository_id(account)
    listing = fn blob -> [%{path: "Package.resolved", git_blob_id: blob, mode: 0o100644}] end
    GitHistory.record_listing(repository_id, "root", listing.("one"), files_count: 1)
    GitHistory.record_listing(repository_id, "base", listing.("two"), files_count: 1)
    GitHistory.record_listing(repository_id, "head", listing.("one"), files_count: 1)

    test_pid = self()

    stub(GitHistory, :ancestors, fn repository_id, sha ->
      send(test_pid, :window_walk)
      call_original(GitHistory, :ancestors, [repository_id, sha])
    end)

    assert %{kind: "partial", carried_tests_count: 0} = reported = Reported.compute(project, "head")
    assert reasons(reported) == [:tracked_file_changed]
    refute_received :window_walk
  end

  test "without the first parent's listing, each source is checked for changed tracked files", %{
    project: project,
    account: account
  } do
    track_default_files()

    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("root", [], -1),
      CoverageFixtures.commit("base", ["root"], 0)
    ])

    base_run(project, account, sha: "root")
    head_run(project, account, head_files())

    repository_id = CoverageFixtures.repository_id(account)
    listing = [%{path: "Package.resolved", git_blob_id: "one", mode: 0o100644}]
    GitHistory.record_listing(repository_id, "root", listing, files_count: 1)
    GitHistory.record_listing(repository_id, "head", listing, files_count: 1)

    assert %{kind: "reported", carried_tests_count: 1, carried_from: ["root"]} = Reported.compute(project, "head")
  end

  test "a merge commit carries from the merged side that made its tracked-file change", %{
    project: project,
    account: account
  } do
    track_default_files()

    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("feature", ["base"], 0),
      CoverageFixtures.commit("head", ["base", "feature"], 1)
    ])

    base_run(project, account, sha: "feature")
    head_run(project, account, head_files())

    repository_id = CoverageFixtures.repository_id(account)
    listing = fn blob -> [%{path: "Package.resolved", git_blob_id: blob, mode: 0o100644}] end
    GitHistory.record_listing(repository_id, "base", listing.("one"), files_count: 1)
    GitHistory.record_listing(repository_id, "feature", listing.("two"), files_count: 1)
    GitHistory.record_listing(repository_id, "head", listing.("two"), files_count: 1)

    assert %{kind: "reported", carried_tests_count: 1, carried_from: ["feature"]} = Reported.compute(project, "head")
  end

  test "without the head's listing, whether a tracked file changed is unknown and nothing is carried", %{
    project: project,
    account: account
  } do
    track_default_files()
    base_run(project, account)
    head_run(project, account, head_files())

    repository_id = CoverageFixtures.repository_id(account)
    listing = [%{path: "Package.resolved", git_blob_id: "one", mode: 0o100644}]
    GitHistory.record_listing(repository_id, "base", listing, files_count: 1)

    assert %{kind: "partial", carried_tests_count: 0} = reported = Reported.compute(project, "head")
    assert reasons(reported) == [:listing_missing]
  end

  test "a truncated listing cannot say a tracked file is unchanged, and nothing is carried", %{
    project: project,
    account: account
  } do
    track_default_files()
    base_run(project, account)
    head_run(project, account, head_files())

    repository_id = CoverageFixtures.repository_id(account)
    listing = [%{path: "Package.resolved", git_blob_id: "one", mode: 0o100644}]
    GitHistory.record_listing(repository_id, "base", listing, files_count: 1)
    GitHistory.record_listing(repository_id, "head", listing, files_count: 1, truncated: true)

    assert %{kind: "partial", carried_tests_count: 0} = reported = Reported.compute(project, "head")
    assert reasons(reported) == [:listing_missing]
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

  test "lists as without coverage data only the unbuilt files the reported coverage does not keep", %{
    project: project,
    account: account
  } do
    base_run(project, account)
    paths = ["Sources/Math.swift", "Sources/Text.swift", "Sources/Untested.swift", "Tests/AppTests.swift"]
    repository_id = CoverageFixtures.seed_listing(account, "head", paths)

    head_run(project, account, [
      file("Sources/Math.swift", [1, 1, 0]),
      file("Tests/AppTests.swift", [1, 0], is_test: true)
    ])

    # Text.swift is unchanged since the base, so the reported coverage keeps
    # it; no run ever measured Untested.swift.
    assert Commits.summary(project.id, "head").unmeasured_files_count == 1

    # Changed since the base, Text.swift is a gap in the reported coverage and
    # has no coverage data at the commit.
    GitHistory.record_listing(
      repository_id,
      "head",
      Enum.map(paths, fn
        "Sources/Text.swift" = path -> %{path: path, git_blob_id: "blob-changed", mode: 0o100644}
        path -> %{path: path, git_blob_id: "blob-" <> path, mode: 0o100644}
      end),
      files_count: length(paths)
    )

    Commits.recompute(project, "head")

    assert Commits.summary(project.id, "head").unmeasured_files_count == 2
  end

  test "an unbuilt file whose coverage came from tests the caller left out is a gap", %{
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
        only_test_identifiers: ["AppTests/MathTests"]
      }
    )

    assert %{kind: "partial", covered_lines: 2, executable_lines: 7, skipped_tests_count: 0, gap_files_count: 1} =
             reported = Reported.compute(project, "head")

    # Nothing Tuist skipped is carried for what the caller left out.
    assert reasons(reported) == [:unbuilt_file_uncarried, :caller_selected_tests]
  end

  test "a scheme whose every run executed only the tests its caller selected is partial", %{
    project: project,
    account: account
  } do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/Math.swift", [1, 0])], %{
      git_commit_sha: "head",
      only_test_identifiers: ["AppTests/MathTests"]
    })

    assert %{kind: "partial", skipped_tests_count: 0} = reported = Reported.compute(project, "head")
    assert reasons(reported) == [:unbuilt_file_unknown, :caller_selected_tests]
  end

  test "a scheme the caller narrowed in one run and ran whole in another is measured", %{
    project: project,
    account: account
  } do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/Math.swift", [1, 0])], %{
      git_commit_sha: "head",
      only_test_identifiers: ["AppTests/MathTests"]
    })

    CoverageFixtures.run_with_coverage(project, account, [file("Sources/Math.swift", [1, 0])], %{git_commit_sha: "head"})

    assert %{kind: "measured"} = Reported.compute(project, "head")
  end

  defp skipping(project, account, skips) do
    base_run(project, account)

    CoverageFixtures.run_with_coverage(project, account, head_files(), %{
      git_commit_sha: "head",
      test_modules: modules([test_case("testAdd()", "MathTests")]),
      skip_test_identifiers: skips
    })

    Reported.compute(project, "head")
  end

  test "carries the tests a skip identifier names by suite", %{project: project, account: account} do
    assert %{kind: "reported", skipped_tests_count: 1, carried_tests_count: 1} =
             skipping(project, account, ["AppTests/TextTests"])
  end

  test "carries a test a skip identifier names without its parentheses", %{project: project, account: account} do
    assert %{kind: "reported", skipped_tests_count: 1, carried_tests_count: 1} =
             skipping(project, account, ["AppTests/TextTests/testTrim"])
  end

  test "carries every test of a target a skip identifier names", %{project: project, account: account} do
    assert %{kind: "reported", skipped_tests_count: 1, carried_tests_count: 1} =
             skipping(project, account, ["AppTests"])
  end

  test "carries nothing for a skip identifier that names a test no ancestor ran", %{project: project, account: account} do
    base_run(project, account)

    CoverageFixtures.run_with_coverage(project, account, head_files(), %{
      git_commit_sha: "head",
      test_modules: modules([test_case("testAdd()", "MathTests")]),
      skip_test_identifiers: ["AppTests/TextTests/testGone()"]
    })

    assert %{kind: "measured", skipped_tests_count: 0} = Reported.compute(project, "head")
  end

  test "a target selective testing skipped that no ancestor run executed is a gap", %{
    project: project,
    account: account
  } do
    base_run(project, account)

    head =
      CoverageFixtures.run_with_coverage(project, account, head_files(), %{
        git_commit_sha: "head",
        test_modules: modules([test_case("testAdd()", "MathTests"), test_case("testTrim()", "TextTests")])
      })

    selective_testing(project, head, [{"AppTests", :miss}, {"NewKitTests", :remote}])

    assert %{kind: "partial", skipped_tests_count: 0} = reported = Reported.compute(project, "head")
    assert reasons(reported) == [:target_without_history]
  end

  test "takes a skipped target's tests from the run recorded under the hash it was skipped with", %{
    project: project,
    account: account
  } do
    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("root", [], -1),
      CoverageFixtures.commit("base", ["root"], 0)
    ])

    # The root hashed TextKitTests as the head does and ran testTrim(); the
    # base changed the target, ran testTrim() and a test the head reverted.
    root = target_only_base(project, account, "root", [test_case("testTrim()", "TextTests")])
    selective_testing(project, root, [{"TextKitTests", :miss, "text"}])
    # Its hashes landed before its fold, so the fold recorded it.
    CoverageFixtures.recompute_commit(root)

    base =
      target_only_base(project, account, "base", [
        test_case("testTrim()", "TextTests"),
        test_case("testReverted()", "TextTests")
      ])

    selective_testing(project, base, [{"TextKitTests", :miss, "text-changed"}])

    head =
      CoverageFixtures.run_with_coverage(project, account, head_files(), %{
        git_commit_sha: "head",
        test_modules: modules([test_case("testAdd()", "MathTests")])
      })

    selective_testing(project, head, [{"AppTests", :miss}, {"TextKitTests", :local, "text"}])

    assert %{skipped_tests_count: 1} = Reported.compute(project, "head")
  end

  defp target_only_base(project, account, sha, cases) do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/Text.swift", [1, 1, 1, 0])], %{
      git_commit_sha: sha,
      scheme: "TextScheme",
      test_modules: [%{name: "TextKitTests", status: "success", duration: 1, test_cases: cases}],
      coverage_evidence: %{
        paths: ["Sources/Text.swift"],
        scopes: [%{kind: "target", module: "TextKitTests", suite: "", name: "", files: [0], lines: [[1, 3]]}]
      }
    })
  end

  # base → kit → tip: the base ran App, kit only Kit, and at the tip a
  # selective App run compiled part of what the base did.
  defp scheme_split_runs(project, account, base_scheme) do
    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("kit", ["base"], 2),
      CoverageFixtures.commit("tip", ["kit"], 3)
    ])

    base_run(project, account, scheme: base_scheme)

    CoverageFixtures.run_with_coverage(project, account, [file("Sources/Unused.swift", [0, 0])], %{
      git_commit_sha: "base",
      scheme: base_scheme
    })

    CoverageFixtures.run_with_coverage(project, account, [file("Sources/Kit.swift", [1, 0], targets: ["Kit"])], %{
      git_commit_sha: "kit",
      scheme: "Kit"
    })

    CoverageFixtures.seed_listing(account, "tip", [
      "Sources/Math.swift",
      "Sources/Text.swift",
      "Sources/Unused.swift",
      "Sources/Kit.swift",
      "Tests/AppTests.swift"
    ])

    CoverageFixtures.run_with_coverage(
      project,
      account,
      [file("Sources/Math.swift", [1, 1, 0]), file("Tests/AppTests.swift", [1, 0], is_test: true)],
      %{
        git_commit_sha: "tip",
        partial: true,
        test_modules: modules([test_case("testAdd()", "MathTests")]),
        skip_test_identifiers: ["AppTests/TextTests/testTrim()"]
      }
    )
  end

  test "reads the unbuilt files from the nearest ancestor that measured the commit's schemes", %{
    project: project,
    account: account
  } do
    scheme_split_runs(project, account, "App")

    # Unused.swift is only in the base's App run: nothing carried touches it.
    assert %{kind: "reported", covered_lines: 5, executable_lines: 9, gap_files_count: 0} =
             Reported.compute(project, "tip")
  end

  test "a selective commit no ancestor measured the schemes of is partial", %{project: project, account: account} do
    scheme_split_runs(project, account, "AppAll")

    assert %{kind: "partial", carried_tests_count: 1, gap_files_count: 1} = reported = Reported.compute(project, "tip")
    assert reasons(reported) == [:unbuilt_file_unknown]
  end

  test "a selective commit joins the trend with its reported coverage, and is partial with a gap", %{
    project: project,
    account: account
  } do
    CoverageFixtures.seed_history(account, [], branch_heads: [{"main", "head"}])
    base_run(project, account)
    head_run(project, account, head_files())

    for sha <- ~w(base head), do: Commits.signal_complete(project, sha)

    assert [%{git_commit_sha: "base", coverage: 71.4}, %{git_commit_sha: "head", coverage: 71.4}] =
             History.trend_points(project, "main").points

    head_run(project, account, head_files(git_blob_id: "blob-changed"))
    assert %{reported_kind: "partial"} = Commits.summary(project.id, "head")
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
             executable_lines: 4
           } = Commits.file_detail(project.id, "head", "Sources/Text.swift")

    assert %{carried_lines: [], covered_lines: 2} = Commits.file_detail(project.id, "head", "Sources/Math.swift")
    assert Commits.file_detail(project.id, "head", "Sources/Text.swift", measured: true) == nil
  end

  test "is the measured figure when Tuist skipped nothing", %{project: project, account: account} do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/Math.swift", [1, 0])], %{git_commit_sha: "head"})

    assert %{kind: "measured", covered_lines: 1, executable_lines: 2} = Reported.compute(project, "head")
    assert Reported.compute(project, "unknown") == nil
  end
end
