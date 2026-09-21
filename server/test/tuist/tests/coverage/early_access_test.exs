defmodule Tuist.Tests.Coverage.EarlyAccessTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Enumeration
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @attrs %{
    recompute: false,
    enumerated_tests: [%{module: "AppTests", suite: "ATests", name: "testA()"}],
    coverage_evidence: %{
      paths: ["Sources/A.swift"],
      scopes: [%{kind: "test", module: "AppTests", suite: "ATests", name: "testA()", files: [0]}]
    },
    changed_files: [%{path: "Sources/A.swift", status: "modified", git_blob_id: "blob", hunks: [%{start: 1, end: 2}]}]
  }

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    %{account: account, project: ProjectsFixtures.project_fixture(account_id: account.id)}
  end

  test "a run of an account without the flag leaves nothing of coverage or test selection behind", %{
    account: account,
    project: project
  } do
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)
    run = CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])], @attrs)

    # Read back with the flag on: what matters is that nothing was stored.
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> true end)

    assert run.git_repository_id == 0
    assert Coverage.run_summary(project.id, run.id) == nil
    assert Enumeration.summary(run) == nil
    assert Evidence.summary(run) == nil
    assert Comparison.changed_files(project.id, run.id) == []
  end

  test "the same run is kept in full once the account has it", %{account: account, project: project} do
    run = CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])], @attrs)

    assert run.git_repository_id > 0
    assert %{covered_lines: 1} = Coverage.run_summary(project.id, run.id)
    assert %{enumerated: 1} = Enumeration.summary(run)
    assert %{tests: 1} = Evidence.summary(run)
    assert [%{path: "Sources/A.swift"}] = Comparison.changed_files(project.id, run.id)
  end
end
