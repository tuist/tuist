defmodule Tuist.Tests.Coverage.CommitsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.GitHistory
  alias Tuist.Projects
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias Tuist.Tests.CoverageCommit
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

  test "signals completion and keeps it across recomputes", %{project: project, account: account} do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

    assert %{complete: true, completeness: "signal"} = Commits.signal_complete(project, "abc123")

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

  test "the fold waits out the buffer the run's row is flushed through", %{project: project} do
    flush_seconds = div(Tuist.Environment.clickhouse_flush_interval_ms(), 1000)
    before = DateTime.utc_now()

    assert {:ok, job} = CommitWorker.enqueue(project.id, "abc123")
    assert DateTime.diff(job.scheduled_at, before) >= flush_seconds + 1
  end

  test "a later report never pulls a later scheduled fold forward", %{project: project} do
    assert {:ok, refold} = CommitWorker.enqueue_refold(project.id, "abc123", 600)
    assert {:ok, _job} = CommitWorker.enqueue(project.id, "abc123")

    assert [job] = all_enqueued(worker: CommitWorker)
    assert job.id == refold.id
    assert DateTime.compare(job.scheduled_at, refold.scheduled_at) == :eq

    # A later report still pushes a sooner fold back.
    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [scheduled_at: DateTime.utc_now()])
    assert {:ok, _job} = CommitWorker.enqueue(project.id, "abc123")
    assert [pushed] = all_enqueued(worker: CommitWorker)
    assert DateTime.after?(pushed.scheduled_at, DateTime.add(DateTime.utc_now(), 1, :second))
  end

  test "reads a commit's runs when the ancestor window holds more shas than ClickHouse takes parameters",
       %{project: project, account: account} do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

    # ClickHouse binds one HTTP form field per query parameter and rejects a
    # request over `http_max_fields` (1000 by default; a self-hosted 26.1.12
    # refused 1000 list elements where 300 went through). The ancestor window
    # is `git_history_window_commits` wide — thousands — so the shas cannot be
    # one `IN` list. Whether a given server enforces the cap is its own
    # configuration, so this pins the behaviour the chunking has to preserve:
    # the same rows, whatever the list length.
    shas = Enum.map(1..1_500, &String.pad_leading("#{&1}", 40, "0")) ++ ["abc123"]

    assert [run] = Commits.runs(project.id, shas)
    assert run.git_commit_sha == "abc123"
  end

  describe "a run's selective-testing results arriving after its commit was folded" do
    defp graph(hit),
      do: %{
        name: "App",
        projects: [%{"targets" => [%{"name" => "AppTests", "selective_testing_metadata" => %{"hit" => hit}}]}]
      }

    test "refold the commit once they are stored", %{project: project, account: account} do
      run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])
      Commits.signal_complete(project, "abc123")
      Oban.drain_queue(queue: :default, with_scheduled: true)

      assert {:ok, %Oban.Job{} = job} =
               Coverage.refold_after_selective_testing(%{test_run_id: run.id, project_id: project.id}, graph("local"))

      assert %{git_commit_sha: "abc123"} = job.args
      assert DateTime.after?(job.scheduled_at, DateTime.utc_now())

      version = Commits.summary(project.id, "abc123").version
      assert :ok = perform_job(CommitWorker, job.args)
      assert %{complete: true, version: new_version} = Commits.summary(project.id, "abc123")
      assert new_version > version
    end

    test "schedule nothing when no target was skipped, or the event has no run", %{project: project, account: account} do
      run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

      assert Coverage.refold_after_selective_testing(%{test_run_id: run.id, project_id: project.id}, graph("miss")) ==
               :skipped

      assert Coverage.refold_after_selective_testing(%{test_run_id: nil, project_id: project.id}, graph("local")) ==
               :skipped
    end
  end

  describe "nearest_measured_ancestor/3" do
    # main: a → b → c → m → d, where m merges the feature branch b → f1 → f2;
    # x is a commit on top of d that no ref placed yet.
    setup %{account: account} do
      repository_id =
        CoverageFixtures.seed_history(
          account,
          [
            CoverageFixtures.commit("a", [], 0),
            CoverageFixtures.commit("b", ["a"], 1),
            CoverageFixtures.commit("c", ["b"], 2),
            CoverageFixtures.commit("f1", ["b"], 3),
            CoverageFixtures.commit("f2", ["f1"], 4),
            CoverageFixtures.commit("m", ["c", "f2"], 5),
            CoverageFixtures.commit("d", ["m"], 6),
            CoverageFixtures.commit("x", ["d"], 7)
          ],
          branch_heads: [feature: "f2", main: "d"]
        )

      %{repository_id: repository_id}
    end

    defp measure(project, repository_id, shas) do
      for sha <- shas do
        {ref_id, position} = GitHistory.position(repository_id, sha) || {nil, nil}

        Repo.insert!(%CoverageCommit{
          project_id: project.id,
          git_commit_sha: sha,
          repository_id: repository_id,
          ref_id: ref_id,
          position: position,
          committed_at: ~U[2026-09-01 00:00:00.000000Z],
          ran_at: ~U[2026-09-01 00:00:00.000000Z],
          covered_lines: 1,
          executable_lines: 1
        })
      end
    end

    test "is the nearest measured first parent, across the refs' segments", %{
      project: project,
      repository_id: repository_id
    } do
      measure(project, repository_id, ["a"])

      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d") == {"a", 4}
      assert Commits.nearest_measured_ancestor(project.id, repository_id, "f2") == {"a", 3}
    end

    test "is a commit merged in closer than the nearest measured first parent", %{
      project: project,
      repository_id: repository_id
    } do
      measure(project, repository_id, ["a", "f2"])

      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d") == {"f2", 2}
    end

    test "leaves the commit itself out", %{project: project, repository_id: repository_id} do
      measure(project, repository_id, ["d"])

      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d") == nil
    end

    test "walks the first parents of a commit no ref placed down to a segment", %{
      project: project,
      repository_id: repository_id
    } do
      measure(project, repository_id, ["c"])

      assert GitHistory.position(repository_id, "x") == nil
      assert Commits.nearest_measured_ancestor(project.id, repository_id, "x") == {"c", 3}
    end

    test "walks the whole ancestry when no first parent was measured", %{
      project: project,
      repository_id: repository_id
    } do
      measure(project, repository_id, ["f1"])

      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d") == {"f1", 3}
    end
  end
end
