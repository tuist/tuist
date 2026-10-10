defmodule Tuist.Tests.Coverage.TargetSourcesTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Tests.Coverage.TargetSources
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("c1", [], 0),
      CoverageFixtures.commit("c2", ["c1"], 1)
    ])

    %{account: account, project: project, repository_id: CoverageFixtures.repository_id(account)}
  end

  # A run of TextKitTests at `sha`, its hashes landing before its commit folds.
  defp run(project, account, sha, attrs \\ %{}) do
    {status, attrs} = Map.pop(attrs, :status, "success")

    run =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [CoverageFixtures.file("Sources/Text.swift", [1, 1, 0])],
        Map.merge(
          %{
            git_commit_sha: sha,
            recompute: false,
            test_modules: [
              %{
                name: "TextKitTests",
                status: status,
                duration: 1,
                test_cases: [%{name: "testTrim()", test_suite_name: "TextTests", status: status, duration: 1}]
              }
            ],
            coverage_evidence: %{
              paths: ["Sources/Text.swift"],
              scopes: [%{kind: "target", module: "TextKitTests", suite: "", name: "", files: [0], lines: [[1, 2]]}]
            }
          },
          attrs
        )
      )

    event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test", test_run_id: run.id)

    XcodeFixtures.xcode_target_fixture(
      command_event_id: event.id,
      name: "TextKitTests",
      selective_testing_hash: "text",
      selective_testing_hit: :miss
    )

    CoverageFixtures.recompute_commit(run)
    run
  end

  test "records the latest run that executed the target whole and passed it", %{
    project: project,
    account: account,
    repository_id: repository_id
  } do
    run(project, account, "c1")
    latest = run(project, account, "c2")

    assert %{{"TextKitTests", "text"} => %{run_id: run_id, sha: "c2"}} =
             TargetSources.latest(project.id, repository_id, [{"TextKitTests", "text"}])

    assert run_id == latest.id
  end

  test "records no run where the target failed, or the caller narrowed the tests", %{
    project: project,
    account: account,
    repository_id: repository_id
  } do
    run(project, account, "c1", %{status: "failure"})
    run(project, account, "c2", %{only_test_identifiers: ["TextKitTests/TextTests/testTrim()"]})

    assert TargetSources.latest(project.id, repository_id, [{"TextKitTests", "text"}]) == %{}
  end
end
