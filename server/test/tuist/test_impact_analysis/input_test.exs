defmodule Tuist.TestImpactAnalysis.InputTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import TuistTestSupport.Fixtures.TestImpactAnalysisFixtures, only: [changed: 2]

  alias Tuist.ClickHouseRepo
  alias Tuist.TestImpactAnalysis.Input
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    CoverageFixtures.seed_history(account, [CoverageFixtures.commit("c1", [], 0)])

    CoverageFixtures.seed_listing(account, "c1", [
      "Sources/Math.swift",
      "Sources/Setup.swift",
      "Sources/Launch.swift",
      "Tests/AppTests.swift"
    ])

    # testAdd() ran Math.swift and its test file, its suite's setup ran
    # Setup.swift, and the target's process also launched the app. sum() is a
    # Swift Testing test: nothing is attributed to it.
    run =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [
          CoverageFixtures.file("Sources/Math.swift", [1, 1]),
          CoverageFixtures.file("Sources/Setup.swift", [1]),
          CoverageFixtures.file("Sources/Launch.swift", [1]),
          CoverageFixtures.file("Tests/AppTests.swift", [1], is_test: true)
        ],
        %{
          git_commit_sha: "c1",
          test_modules: [
            %{
              name: "AppTests",
              status: "success",
              duration: 1,
              test_cases: [
                %{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 1},
                %{name: "sum()", test_suite_name: "SumTests", status: "success", duration: 1}
              ]
            }
          ],
          coverage_evidence: %{
            paths: ["Sources/Math.swift", "Tests/AppTests.swift", "Sources/Setup.swift", "Sources/Launch.swift"],
            scopes: [
              %{
                kind: "test",
                module: "AppTests",
                suite: "MathTests",
                name: "testAdd()",
                files: [0, 1],
                lines: [[1, 2], [1, 1]]
              },
              %{kind: "suite", module: "AppTests", suite: "MathTests", name: "", files: [2], lines: [[1, 1]]},
              %{kind: "target", module: "AppTests", suite: "", name: "", files: [0, 1, 2, 3], lines: []}
            ]
          }
        }
      )

    %{project: project, run: run, repository_id: CoverageFixtures.repository_id(account)}
  end

  defp load(project, run, repository_id, opts \\ []) do
    Input.load(
      project,
      Keyword.merge(
        [repository_id: repository_id, baseline_sha: "c1", baseline_run_ids: [run.id]],
        opts
      )
    )
  end

  defp test_case_id(input, name), do: Enum.find(input.tests, &(&1.name == name)).test_case_id

  test "reads the baseline's tests and evidence", %{project: project, run: run, repository_id: repository_id} do
    input = load(project, run, repository_id)

    assert input.tests |> Enum.map(&{&1.module_name, &1.suite_name, &1.name}) |> Enum.sort() == [
             {"AppTests", "MathTests", "testAdd()"},
             {"AppTests", "SumTests", "sum()"}
           ]

    assert input.target_evidence == %{"AppTests" => ["Sources/Launch.swift"]}
    assert MapSet.to_list(input.test_paths) == ["Tests/AppTests.swift"]
    assert Input.evidenced?(input, "Sources/Launch.swift")
    assert input.tracked_file_globs != []

    assert %{newest: newest, reproduced: newest} = Input.evidence(input, test_case_id(input, "testAdd()"))
    assert newest.paths == ["Sources/Math.swift", "Sources/Setup.swift", "Tests/AppTests.swift"]
    assert Input.evidence(input, test_case_id(input, "sum()")) == nil
  end

  test "resolves evidence against the baseline overlaid with the diff", %{
    project: project,
    run: run,
    repository_id: repository_id
  } do
    input = load(project, run, repository_id, changed_files: [changed("Sources/Setup.swift", affected_modules: [])])

    assert %{reproduced: nil} = Input.evidence(input, test_case_id(input, "testAdd()"))
  end

  test "reads the baseline's blobs from its file changes once they are written", %{
    project: project,
    run: run,
    repository_id: repository_id
  } do
    # What the baseline's blobs decide: the version each test reproduces.
    evidence = fn ->
      for changed_files <- [[], [changed("Sources/Math.swift", [])]],
          do: load(project, run, repository_id, changed_files: changed_files).evidence
    end

    listed = evidence.()
    Oban.drain_queue(queue: :coverage_deltas, with_recursion: true, with_safety: false)

    assert Tuist.GitHistory.FileChanges.current(repository_id, "c1")
    assert evidence.() == listed
    assert [[%{reproduced: %{sha: "c1"}}], [%{reproduced: nil}]] = Enum.map(listed, &Map.values/1)
  end

  test "keeps only the requested modules", %{project: project, run: run, repository_id: repository_id} do
    assert load(project, run, repository_id, modules: ["OtherTests"]).tests == []
  end

  test "uses a version recorded last by a run on another branch when the checkout reproduces it", %{
    project: project,
    run: run,
    repository_id: repository_id
  } do
    # A later run on another branch executed testAdd() over the same blobs, so
    # coverage_test_sources' one row for that version now names its commit.
    account = Tuist.Repo.preload(project, :account).account
    CoverageFixtures.seed_history(account, [CoverageFixtures.commit("other", ["c1"], 1)])
    CoverageFixtures.seed_listing(account, "other", ["Sources/Math.swift", "Sources/Setup.swift", "Tests/AppTests.swift"])

    other =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [
          CoverageFixtures.file("Sources/Math.swift", [1, 1]),
          CoverageFixtures.file("Sources/Setup.swift", [1]),
          CoverageFixtures.file("Tests/AppTests.swift", [1], is_test: true)
        ],
        %{
          git_commit_sha: "other",
          git_branch: "feature/other",
          ran_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          test_modules: [
            %{
              name: "AppTests",
              status: "success",
              duration: 1,
              test_cases: [%{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 1}]
            }
          ],
          coverage_evidence: %{
            paths: ["Sources/Math.swift", "Tests/AppTests.swift", "Sources/Setup.swift"],
            scopes: [
              %{
                kind: "test",
                module: "AppTests",
                suite: "MathTests",
                name: "testAdd()",
                files: [0, 1],
                lines: [[1, 2], [1, 1]]
              },
              %{kind: "suite", module: "AppTests", suite: "MathTests", name: "", files: [2], lines: [[1, 1]]}
            ]
          }
        }
      )

    ClickHouseRepo.query!("OPTIMIZE TABLE coverage_test_sources FINAL")

    input = load(project, run, repository_id)
    test_case_id = test_case_id(input, "testAdd()")

    assert %{newest: newest, reproduced: newest} = Input.evidence(input, test_case_id)
    assert {newest.sha, newest.run_id} == {"other", other.id}
    assert MapSet.new(Input.tests_touching(input, "Sources/Math.swift")) == MapSet.new([test_case_id])
  end
end
