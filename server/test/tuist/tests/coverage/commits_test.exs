defmodule Tuist.Tests.Coverage.CommitsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.GitHistory
  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")
    %{account: account, project: project}
  end

  defp file(path, counts, opts \\ []), do: CoverageFixtures.file(path, counts, opts)

  test "publishes a commit as the union of its runs, a file counted once across schemes", %{
    project: project,
    account: account
  } do
    app =
      CoverageFixtures.run_with_coverage(project, account, [
        file("Sources/A.swift", [1, 0, 0]),
        file("Sources/B.swift", [1])
      ])

    other =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [file("Sources/A.swift", [0, 1, 0], targets: ["Other"]), file("Sources/C.swift", [0, 0], targets: ["Other"])],
        %{scheme: "Other", partial: true}
      )

    summary = Commits.summary(project.id, "abc123")

    assert {summary.covered_lines, summary.executable_lines, summary.coverage, summary.measured_files_count} ==
             {3, 6, 50.0, 3}

    assert {summary.schemes, summary.partial_schemes} == {["App", "Other"], ["Other"]}
    assert Enum.sort(summary.test_run_ids) == Enum.sort([app.id, other.id])
    assert {summary.complete, summary.completeness} == {false, ""}
    assert summary.git_repository_id == CoverageFixtures.repository_id(account)

    assert Enum.map(
             Commits.merged_files(project.id, "abc123"),
             &{&1.path, &1.covered_lines, &1.executable_lines, &1.targets}
           ) ==
             [
               {"Sources/A.swift", 2, 3, ["App", "Other"]},
               {"Sources/B.swift", 1, 1, ["App"]},
               {"Sources/C.swift", 0, 2, ["Other"]}
             ]

    assert Enum.map(Commits.targets(project.id, "abc123"), &{&1.name, &1.covered_lines, &1.executable_lines}) ==
             [{"Other", 2, 5}, {"App", 3, 4}]

    assert {[%{path: "Sources/C.swift"}], 3} = Commits.list_files(project.id, "abc123", 1, 1)

    assert Commits.line_counts(project.id, "abc123", ["Sources/A.swift"]) == %{
             "Sources/A.swift" => [{1, 1}, {2, 1}, {3, 0}]
           }

    assert %{lines: [{1, 1}, {2, 1}, {3, 0}], uncovered_ranges: [{3, 3}]} =
             Commits.file_detail(project.id, "abc123", "Sources/A.swift")

    assert Commits.file_detail(project.id, "abc123", "Missing.swift") == nil
  end

  test "leaves runs from a dirty checkout out, and republishes one version above the latest", %{
    project: project,
    account: account
  } do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])
    first = Commits.summary(project.id, "abc123")

    dirty = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 1])], %{git_dirty: true})
    assert Commits.enqueue_recompute(dirty) == :skipped
    assert Commits.recompute(project, "abc123").covered_lines == 1
    assert Commits.run_ids(project.id, "abc123") != [dirty.id]

    second = Commits.summary(project.id, "abc123")
    assert second.version > first.version
    assert second.inserted_at == first.inserted_at

    assert Commits.recompute(project, "nothing-measured") == nil
    assert Commits.summary(project.id, "nothing-measured") == nil
  end

  test "signals completion, keeps it across recomputes and enqueues the gate verdict", %{
    project: project,
    account: account
  } do
    {:ok, project} = Projects.update_project(project, %{coverage_gates_enabled: true})
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

    assert %{complete: true, completeness: "signal"} = Commits.signal_complete(project, "abc123")

    assert_enqueued(
      worker: Tuist.Tests.Coverage.Workers.CoverageGateWorker,
      args: %{git_commit_sha: "abc123", trigger: "signal"}
    )

    # A run landing after the signal joins the union; the commit stays complete.
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/B.swift", [1])])
    assert %{complete: true, completeness: "signal", measured_files_count: 2} = Commits.summary(project.id, "abc123")

    assert Commits.signal_complete(project, "unmeasured") == nil
  end

  test "counts the source files of the commit's listing that no run measured", %{project: project, account: account} do
    repository = CoverageFixtures.repository_id(account)

    GitHistory.record_listing(repository, "abc123", [
      %{path: "Sources/A.swift", git_blob_id: "a"},
      %{path: "Sources/Untested.swift", git_blob_id: "u"},
      %{path: "Sources/Generated/API.swift", git_blob_id: "g"},
      %{path: "Tests/ATests.swift", git_blob_id: "t"},
      %{path: "Project.swift", git_blob_id: "p"},
      %{path: "Tuist/ProjectDescriptionHelpers/Helper.swift", git_blob_id: "h"},
      %{path: "README.md", git_blob_id: "r"}
    ])

    {:ok, project} = Projects.update_project(project, %{coverage_excluded_path_globs: ["Sources/Generated/**"]})

    CoverageFixtures.run_with_coverage(project, account, [
      file("Sources/A.swift", [1]),
      file("Tests/ATests.swift", [1], is_test: true)
    ])

    assert Commits.summary(project.id, "abc123").unmeasured_files_count == 1

    # The same files the count is taken from, so the page can name them:
    # `README.md` shares no extension with anything measured, the generated
    # file is excluded, the test file was measured, and the manifests are
    # source no product compiles.
    assert Commits.unmeasured_files(project, "abc123") == ["Sources/Untested.swift"]
    assert Commits.unmeasured_files(project, "nothing") == []
  end

  test "a run that does not say whether its checkout was dirty is folded as a clean one", %{
    project: project,
    account: account
  } do
    run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])], %{recompute: false})

    assert {:ok, _job} = Commits.enqueue_recompute(%{run | git_dirty: nil})
    assert Commits.enqueue_recompute(%{run | git_dirty: true}) == :skipped
  end

  test "a report that lands while the fold runs gets a job of its own", %{project: project, account: account} do
    run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])], %{recompute: false})
    {:ok, pending} = Commits.enqueue_recompute(run)

    # A second report while the first job is still pending folds with it.
    {:ok, deduped} = Commits.enqueue_recompute(run)
    assert deduped.id == pending.id

    # Once that job is running, the fold it would be deduped into has already
    # read the runs, so the report cannot wait for it.
    Repo.update_all(from(j in Oban.Job, where: j.id == ^pending.id), set: [state: "executing"])
    {:ok, own} = Commits.enqueue_recompute(run)
    assert own.id != pending.id
    assert own.state == "scheduled"
  end

  test "the worker republishes the commit and is scheduled once per commit", %{project: project, account: account} do
    run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])], %{recompute: false})
    assert Commits.summary(project.id, "abc123") == nil

    assert {:ok, _job} = Commits.enqueue_recompute(run)
    assert {:ok, _job} = Commits.enqueue_recompute(project.id, "abc123")
    assert [job] = all_enqueued(worker: CommitWorker)
    assert job.args == %{"project_id" => project.id, "git_commit_sha" => "abc123"}

    assert :ok = perform_job(CommitWorker, job.args)
    assert %{coverage: 50.0} = Commits.summary(project.id, "abc123")
    assert :ok = perform_job(CommitWorker, %{"project_id" => -1, "git_commit_sha" => "abc123"})
  end
end
