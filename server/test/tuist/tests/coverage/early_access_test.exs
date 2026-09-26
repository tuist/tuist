defmodule Tuist.Tests.Coverage.EarlyAccessTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

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
    assert CoverageFixtures.run_summary(project.id, run.id) == nil
    assert CoverageFixtures.enumerated_tests(run) == []
    assert CoverageFixtures.evidence_rows(run) == []
    assert CoverageFixtures.changed_files(run) == []
  end

  test "the same run is kept in full once the account has it", %{account: account, project: project} do
    run = CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])], @attrs)

    assert run.git_repository_id > 0
    assert %{covered_lines: 1} = CoverageFixtures.run_summary(project.id, run.id)
    assert [%{name: "testA()"}] = CoverageFixtures.enumerated_tests(run)
    assert [%{scope_kind: "test", path: "Sources/A.swift"}] = CoverageFixtures.evidence_rows(run)
    assert [%{path: "Sources/A.swift", hunk_starts: [1], hunk_ends: [2]}] = CoverageFixtures.changed_files(run)
  end
end
