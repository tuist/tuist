defmodule Tuist.Tests.Coverage.TestSourcesTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.Coverage.TestSources
  alias Tuist.Tests.TestCaseRun
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    CoverageFixtures.seed_history(account, [CoverageFixtures.commit("c1", [], 0)])
    %{account: account, project: project, repository_id: CoverageFixtures.repository_id(account)}
  end

  # testAdd() ran Math.swift and its test file, and its suite's setup ran
  # Setup.swift without lines.
  defp run(project, account, attrs \\ %{}) do
    {status, attrs} = Map.pop(attrs, :status, "success")

    CoverageFixtures.run_with_coverage(
      project,
      account,
      [
        CoverageFixtures.file("Sources/Math.swift", [1, 1, 0]),
        CoverageFixtures.file("Sources/Setup.swift", [1]),
        CoverageFixtures.file("Tests/AppTests.swift", [1, 1], is_test: true)
      ],
      Map.merge(
        %{
          git_commit_sha: "c1",
          test_modules: [
            %{
              name: "AppTests",
              status: status,
              duration: 1,
              test_cases: [%{name: "testAdd()", test_suite_name: "MathTests", status: status, duration: 1}]
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
              %{kind: "suite", module: "AppTests", suite: "MathTests", name: "", files: [2], lines: [[]]}
            ]
          }
        },
        attrs
      )
    )
  end

  defp versions(project, repository_id) do
    project.id |> TestSources.versions(repository_id, [test_case_id(project)]) |> Map.values() |> Enum.concat()
  end

  defp test_case_id(project) do
    ClickHouseRepo.one(
      from(r in TestCaseRun,
        where: r.project_id == ^project.id and r.name == "testAdd()",
        limit: 1,
        select: fragment("toString(?)", r.test_case_id)
      )
    )
  end

  test "a fingerprint is the files and their blobs, whatever their order" do
    assert TestSources.fingerprint([{"a", "1"}, {"b", "2"}]) == TestSources.fingerprint([{"b", "2"}, {"a", "1"}])
    refute TestSources.fingerprint([{"a", "1"}, {"b", "2"}]) == TestSources.fingerprint([{"a", "1"}, {"b", "3"}])
    refute TestSources.fingerprint([{"a", "1"}]) == TestSources.fingerprint([{"a", "1"}, {"b", "2"}])
  end

  test "records a test's version from the files it and its suite ran, at a commit's fold", %{
    project: project,
    account: account,
    repository_id: repository_id
  } do
    run = run(project, account)

    assert [version] = versions(project, repository_id)

    assert %{
             paths: ["Sources/Math.swift", "Sources/Setup.swift", "Tests/AppTests.swift"],
             unlined_paths: ["Sources/Setup.swift"],
             passed: true,
             sha: "c1"
           } = version

    assert version.run_id == run.id

    assert version.fingerprint ==
             TestSources.fingerprint([
               {"Sources/Math.swift", "blob-Sources/Math.swift"},
               {"Sources/Setup.swift", "blob-Sources/Setup.swift"},
               {"Tests/AppTests.swift", "blob-Tests/AppTests.swift"}
             ])
  end

  test "records whether the test passed", %{project: project, account: account, repository_id: repository_id} do
    run(project, account, %{status: "failure"})

    assert [%{passed: false}] = versions(project, repository_id)
  end

  test "backfills the versions a fold would have recorded", %{
    project: project,
    account: account,
    repository_id: repository_id
  } do
    run(project, account, %{recompute: false})
    assert versions(project, repository_id) == []

    TestSources.backfill(project.id)

    assert [%{paths: ["Sources/Math.swift", "Sources/Setup.swift", "Tests/AppTests.swift"], passed: true}] =
             versions(project, repository_id)
  end
end
