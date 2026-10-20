defmodule Tuist.Tests.Coverage.Workers.DeltaBackfillWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Deltas
  alias Tuist.Tests.Coverage.Workers.DeltaBackfillWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "writes the project's complete commits" do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")
    CoverageFixtures.seed_history(account, [CoverageFixtures.commit("a", [], 0)])

    CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])], %{
      git_commit_sha: "a"
    })

    Commits.signal_complete(project, "a")

    assert Deltas.files(project.id, "a") == nil
    assert :ok = perform_job(DeltaBackfillWorker, %{project_id: project.id})
    assert [%{path: "Sources/A.swift", covered_lines: 1, executable_lines: 2}] = Deltas.files(project.id, "a")
  end

  test "skips a project that no longer exists" do
    assert :ok = perform_job(DeltaBackfillWorker, %{project_id: -1})
  end
end
