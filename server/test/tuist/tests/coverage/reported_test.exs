defmodule Tuist.Tests.Coverage.ReportedTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Gates
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Reported
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

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

  test "a selective commit is compared, and gated, through its reported coverage", %{project: project, account: account} do
    base_run(project, account)
    head_run(project, account, head_files())

    comparison = Comparison.compare(project, Comparison.from_commit(project, "head"))

    assert %{partial: true, coverage: 28.6, reported: %{kind: "reported", coverage: 71.4, carried_from: ["base"]}} =
             comparison.commit

    assert comparison.total_delta == 0.0

    # Text.swift, which only the skipped test covers, did not fall.
    assert Enum.reject(comparison.files, &(&1.delta == 0.0)) == []
    assert Enum.reject(comparison.targets, &(&1.delta == 0.0)) == []

    assert %{status: :passed, value: 0.0} =
             Enum.find(
               Gates.evaluate(%{project | coverage_gate_max_total_drop: 1.0}, comparison).checks,
               &(&1.gate == :max_total_drop)
             )
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

  test "a selective commit with a gap is still not compared", %{project: project, account: account} do
    base_run(project, account)
    head_run(project, account, head_files(git_blob_id: "blob-changed"))

    comparison = Comparison.compare(project, Comparison.from_commit(project, "head"))

    assert %{reported: %{kind: "partial", skipped_tests_count: 1, carried_tests_count: 0}} = comparison.commit
    assert comparison.total_delta == nil
  end

  test "is the observed figure when the runs listed no candidates", %{project: project, account: account} do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/Math.swift", [1, 0])], %{git_commit_sha: "head"})

    assert %{kind: "observed", covered_lines: 1, executable_lines: 2} = Reported.compute(project, "head")
    assert Reported.compute(project, "unknown") == nil
  end
end
