defmodule Tuist.Tests.Coverage.CommitsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.GitHistory
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Reported
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

  test "unsigned clean runs cannot conceal a scheme measured only by dirty CI runs", %{project: project, account: account} do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

    CoverageFixtures.run_with_coverage(project, account, [file("Sources/B.swift", [1, 1])], %{
      scheme: "DirtyOnly",
      git_dirty: true
    })

    before = Commits.recompute(project, "abc123")
    assert :dirty_run_excluded in Commits.gap_reasons(before)

    CoverageFixtures.run_with_coverage(project, account, [], %{
      scheme: "DirtyOnly",
      submission_auth: "network_trusted",
      account_id: 0,
      xcode_coverage: nil,
      recompute: false
    })

    after_report = Commits.recompute(project, "abc123")
    assert after_report.reported_kind == before.reported_kind
    assert Commits.gap_reasons(after_report) == Commits.gap_reasons(before)
    assert after_report.test_run_ids == before.test_run_ids
    assert after_report.schemes == before.schemes
    assert after_report.covered_lines == before.covered_lines
  end

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
    assert {[%{path: "Sources/B.swift"}], 3} = Commits.list_files(project.id, "abc123", 1, 1, sort: {:coverage, :desc})

    assert {[%{path: "Sources/A.swift"}, %{path: "Sources/B.swift"}], 3} =
             Commits.list_files(project.id, "abc123", 1, 2, sort: {:path, :asc})

    assert {[%{path: "Sources/B.swift"}], 1} = Commits.list_files(project.id, "abc123", 1, 10, search: "b.SWIFT")
    assert {[], 0} = Commits.list_files(project.id, "abc123", 1, 10, search: "missing")

    assert Commits.line_counts(project.id, "abc123", ["Sources/A.swift"]) == %{
             "Sources/A.swift" => [{1, 1}, {2, 1}, {3, 0}]
           }

    assert %{lines: [{1, 1}, {2, 1}, {3, 0}]} =
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
    assert {:ok, _job} = Commits.enqueue_recompute(dirty)
    assert Commits.recompute(project, "abc123").covered_lines == 1
    assert Commits.run_ids(project.id, "abc123") != [dirty.id]

    second = Commits.summary(project.id, "abc123")
    assert second.version > first.version
    assert second.inserted_at == first.inserted_at
    # A clean run measured the dirty run's scheme, so the figure is whole.
    refute Commits.incomplete?(second)

    assert Commits.recompute(project, "nothing-measured") == nil
    assert Commits.summary(project.id, "nothing-measured") == nil
  end

  test "a scheme only runs from a dirty checkout measured leaves the figure a lower bound, and its runs are listed on request",
       %{project: project, account: account} do
    # Alone, a dirty run folds nothing: no run that counts measured the commit.
    dirty =
      CoverageFixtures.run_with_coverage(project, account, [file("Sources/B.swift", [1, 1])], %{
        scheme: "AppTests",
        git_dirty: true
      })

    assert Commits.summary(project.id, "abc123") == nil

    clean = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

    summary = Commits.summary(project.id, "abc123")
    assert {summary.schemes, summary.covered_lines, summary.executable_lines} == {["App"], 1, 2}
    assert {summary.reported_kind, Commits.gap_reasons(summary)} == {"partial", [:dirty_run_excluded]}
    assert Commits.status(summary) == :in_progress
    assert Commits.status(Commits.signal_complete(project, "abc123")) == :incomplete

    assert Enum.map(Commits.run_cursor_page(project.id, {:commit, "abc123"}).runs, &{&1.test_run_id, &1.git_dirty}) ==
             [{clean.id, false}]

    assert project.id
           |> Commits.run_cursor_page({:commit, "abc123"}, dirty: true)
           |> Map.fetch!(:runs)
           |> Enum.map(&{&1.test_run_id, &1.git_dirty})
           |> Enum.sort() == Enum.sort([{clean.id, false}, {dirty.id, true}])

    # A clean run of the scheme makes the figure whole again.
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/B.swift", [1, 1])], %{scheme: "AppTests"})
    summary = Commits.summary(project.id, "abc123")
    assert {summary.schemes, Commits.gap_reasons(summary)} == {["App", "AppTests"], []}
    assert Commits.status(summary) == :complete
  end

  test "a dirty run landing after the commit's clean runs still leaves the figure a lower bound", %{
    project: project,
    account: account
  } do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])
    refute Commits.incomplete?(Commits.signal_complete(project, "abc123"))

    CoverageFixtures.run_with_coverage(project, account, [file("Sources/B.swift", [1, 1])], %{
      scheme: "AppTests",
      git_dirty: true
    })

    summary = Commits.summary(project.id, "abc123")
    assert {summary.schemes, Commits.gap_reasons(summary)} == {["App"], [:dirty_run_excluded]}
    assert Commits.status(summary) == :incomplete
  end

  test "a local dirty run of a scheme CI never ran leaves a complete commit whole", %{
    project: project,
    account: account
  } do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])
    Commits.signal_complete(project, "abc123")

    local =
      CoverageFixtures.run_with_coverage(project, account, [file("Sources/B.swift", [1])], %{
        scheme: "LocalScheme",
        is_ci: false,
        git_dirty: true
      })

    assert Commits.enqueue_recompute(local) == :skipped
    summary = Commits.recompute(project, "abc123")
    assert {Commits.status(summary), Commits.gap_reasons(summary)} == {:complete, []}
  end

  test "signals completion and keeps it across recomputes", %{project: project, account: account} do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

    assert %{complete: true, completeness: "signal"} = Commits.signal_complete(project, "abc123")

    # A run landing after the signal joins the union; the commit stays complete.
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/B.swift", [1])])
    assert %{complete: true, completeness: "signal", measured_files_count: 2} = Commits.summary(project.id, "abc123")

    assert Commits.signal_complete(project, "unmeasured") == nil
  end

  test "a completion signal that lands before any run folded completes the commit's first fold", %{
    project: project,
    account: account
  } do
    assert Commits.signal_complete(project, "abc123") == nil
    assert Commits.summary(project.id, "abc123") == nil

    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])
    assert %{complete: true, completeness: "signal"} = Commits.summary(project.id, "abc123")

    CoverageFixtures.run_with_coverage(project, account, [file("Sources/B.swift", [1])])
    assert %{complete: true, completeness: "signal", measured_files_count: 2} = Commits.summary(project.id, "abc123")

    # Another commit is not completed by it.
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])], %{git_commit_sha: "def456"})
    assert %{complete: false} = Commits.summary(project.id, "def456")
  end

  describe "changed_files/5" do
    test "lists the files whose coverage moved most between two commits, kept at both", %{
      project: project,
      account: account
    } do
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [
          file("Sources/A.swift", [1, 0, 0, 0]),
          file("Sources/B.swift", [1, 1]),
          file("Sources/Same.swift", [0, 0]),
          file("Sources/Gone.swift", [1]),
          file("Sources/Small.swift", [0])
        ],
        %{git_commit_sha: "a"}
      )

      CoverageFixtures.run_with_coverage(
        project,
        account,
        [
          file("Sources/A.swift", [1, 1, 0, 0]),
          file("Sources/B.swift", [1, 0]),
          file("Sources/Same.swift", [0, 0]),
          file("Sources/New.swift", [1]),
          file("Sources/Small.swift", [1])
        ],
        %{git_commit_sha: "b"}
      )

      assert Enum.map(Commits.changed_files(project.id, "a", "b", 5), &{&1.path, &1.change}) == [
               {"Sources/Small.swift", 100.0},
               {"Sources/B.swift", -50.0},
               {"Sources/A.swift", 25.0}
             ]

      assert [%{path: "Sources/Small.swift", previous_covered_lines: 0, covered_lines: 1}] =
               Commits.changed_files(project.id, "a", "b", 1)

      assert Commits.changed_files(project.id, "a", "missing", 5) == []
    end
  end

  describe "changed_targets/5" do
    test "lists the targets whose coverage moved most between two commits, kept at both", %{
      project: project,
      account: account
    } do
      in_target = &file(&1, &2, targets: [&3])

      CoverageFixtures.run_with_coverage(
        project,
        account,
        [
          in_target.("Sources/A.swift", [1, 0, 0, 0], "Core"),
          in_target.("Sources/B.swift", [1, 1], "UI"),
          in_target.("Sources/Same.swift", [0, 0], "Same"),
          in_target.("Sources/Gone.swift", [1], "Gone"),
          in_target.("Sources/Small.swift", [0], "Small")
        ],
        %{git_commit_sha: "a"}
      )

      CoverageFixtures.run_with_coverage(
        project,
        account,
        [
          in_target.("Sources/A.swift", [1, 1, 0, 0], "Core"),
          in_target.("Sources/B.swift", [1, 0], "UI"),
          in_target.("Sources/Same.swift", [0, 0], "Same"),
          in_target.("Sources/New.swift", [1], "New"),
          in_target.("Sources/Small.swift", [1], "Small")
        ],
        %{git_commit_sha: "b"}
      )

      assert Enum.map(Commits.changed_targets(project.id, "a", "b", 5), &{&1.name, &1.change}) == [
               {"Small", 100.0},
               {"UI", -50.0},
               {"Core", 25.0}
             ]

      assert [%{name: "Small", files_count: 1, previous_covered_lines: 0, covered_lines: 1, executable_lines: 1}] =
               Commits.changed_targets(project.id, "a", "b", 1)

      assert Commits.changed_targets(project.id, "a", "missing", 5) == []
    end
  end

  describe "prune/1" do
    defp published(project, sha, attrs) do
      Repo.insert!(
        struct(
          %CoverageCommit{
            project_id: project.id,
            git_commit_sha: sha,
            committed_at: DateTime.utc_now(),
            ran_at: DateTime.utc_now(),
            covered_lines: 1,
            executable_lines: 1
          },
          attrs
        )
      )
    end

    defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)

    test "drops commits past retention and a pull request's own commits sooner", %{
      project: project,
      account: account
    } do
      repository_id =
        CoverageFixtures.seed_history(account, [CoverageFixtures.commit("main-head", [], 0)],
          branch_heads: [{"main", "main-head"}]
        )

      {main_ref_id, main_position} = GitHistory.position(repository_id, "main-head")

      published(project, "ancient", %{committed_at: days_ago(1100)})
      published(project, "recent", %{committed_at: days_ago(10)})
      published(project, "pull-request", %{committed_at: days_ago(100), pull_request_number: 7})

      published(project, "merged-into-main", %{
        committed_at: days_ago(100),
        pull_request_number: 7,
        ref_id: main_ref_id,
        position: main_position
      })

      assert Commits.prune(%{commits: 1095, pull_requests: 90}) == 2

      assert CoverageCommit
             |> where([c], c.project_id == ^project.id)
             |> select([c], c.git_commit_sha)
             |> Repo.all()
             |> Enum.sort() ==
               ["merged-into-main", "recent"]
    end

    test "drops a completion signal no run followed", %{project: project, account: account} do
      assert Commits.signal_complete(project, "abc123") == nil

      Repo.update_all(from(c in "coverage_commit_completions", where: c.project_id == ^project.id),
        set: [inserted_at: days_ago(91)]
      )

      Commits.prune(%{commits: 1095, pull_requests: 90})

      CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])
      assert %{complete: false} = Commits.summary(project.id, "abc123")
    end
  end

  test "a completion signal is not lost when the first run folds while the signal reads", %{
    project: project,
    account: account
  } do
    stub(Reported, :compute, fn project, sha, opts -> Mimic.call_original(Reported, :compute, [project, sha, opts]) end)

    expect(Reported, :compute, fn project, sha, opts ->
      CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])
      Mimic.call_original(Reported, :compute, [project, sha, opts])
    end)

    assert %{complete: true, completeness: "signal"} = Commits.signal_complete(project, "abc123")
    assert %{complete: true, completeness: "signal"} = Commits.summary(project.id, "abc123")
  end

  test "a fold computes outside a transaction and never overwrites what was written meanwhile", %{
    project: project,
    account: account
  } do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])
    %{version: version} = Commits.summary(project.id, "abc123")

    # The completion signal lands while a run's fold is computing.
    stub(Reported, :compute, fn project, sha, opts ->
      refute Repo.in_transaction?()
      Mimic.call_original(Reported, :compute, [project, sha, opts])
    end)

    expect(Reported, :compute, fn project, sha, opts ->
      refute Repo.in_transaction?()
      assert %{complete: true} = Commits.signal_complete(project, sha)
      Mimic.call_original(Reported, :compute, [project, sha, opts])
    end)

    assert %{complete: true, completeness: "signal"} = Commits.recompute(project, "abc123")
    assert %{complete: true, version: new_version} = Commits.summary(project.id, "abc123")
    assert new_version == version + 2
  end

  test "a fold that keeps losing the race folds under the commit's lock", %{project: project, account: account} do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])
    %{version: version} = Commits.summary(project.id, "abc123")

    # Every optimistic attempt sees the row move under it.
    stub(Reported, :compute, fn project, sha, opts ->
      if !Repo.in_transaction?() do
        Repo.update_all(
          from(c in CoverageCommit, where: c.project_id == ^project.id and c.git_commit_sha == ^sha),
          inc: [version: 1],
          set: [complete: true, completeness: "signal"]
        )
      end

      Mimic.call_original(Reported, :compute, [project, sha, opts])
    end)

    assert %{complete: true, version: new_version} = Commits.recompute(project, "abc123")
    assert new_version == version + 3
  end

  test "counts the source files of the commit's listing that no run measured", %{project: project, account: account} do
    repository = CoverageFixtures.repository_id(account)

    GitHistory.record_listing(repository, "abc123", [
      %{path: "Sources/A.swift", git_blob_id: "a"},
      %{path: "Sources/Untested.swift", git_blob_id: "u"},
      %{path: "Sources/API/Client.generated.swift", git_blob_id: "g"},
      %{path: "Tests/ATests.swift", git_blob_id: "t"},
      %{path: "Project.swift", git_blob_id: "p"},
      %{path: "Tuist/ProjectDescriptionHelpers/Helper.swift", git_blob_id: "h"},
      %{path: "README.md", git_blob_id: "r"}
    ])

    CoverageFixtures.run_with_coverage(project, account, [
      file("Sources/A.swift", [1]),
      file("Tests/ATests.swift", [1], is_test: true)
    ])

    # Only Untested.swift: `README.md` shares no extension with anything
    # measured, the generated file is excluded, the test file was measured,
    # and the manifests are source no product compiles.
    assert Commits.summary(project.id, "abc123").unmeasured_files_count == 1
  end

  test "a run schedules its commit's fold whether its checkout was dirty or not, and one without a commit none", %{
    project: project,
    account: account
  } do
    run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])], %{recompute: false})

    assert {:ok, _job} = Commits.enqueue_recompute(%{run | git_dirty: nil})
    assert {:ok, _job} = Commits.enqueue_recompute(%{run | git_dirty: true})
    assert Commits.enqueue_recompute(%{run | git_dirty: true, is_ci: false}) == :skipped
    assert Commits.enqueue_recompute(%{run | git_commit_sha: ""}) == :skipped
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

  describe "folding a commit" do
    test "moves its branch only on runs newer than what last moved it, so a refold never moves it back", %{
      account: account,
      project: project
    } do
      repository_id =
        CoverageFixtures.seed_history(account, [
          CoverageFixtures.commit("d", [], 0),
          CoverageFixtures.commit("x1", ["d"], 1),
          CoverageFixtures.commit("y1", ["d"], 2)
        ])

      now = NaiveDateTime.utc_now()
      file = [CoverageFixtures.file("Sources/A.swift", [1, 0])]

      CoverageFixtures.run_with_coverage(project, account, file, %{
        git_commit_sha: "x1",
        git_branch: "feature",
        ran_at: NaiveDateTime.add(now, -7200)
      })

      assert CoverageFixtures.branch_head(repository_id, "feature") == "x1"

      # The branch was force-pushed to y1, whose run came later.
      CoverageFixtures.run_with_coverage(project, account, file, %{
        git_commit_sha: "y1",
        git_branch: "feature",
        ran_at: NaiveDateTime.add(now, -3600)
      })

      assert CoverageFixtures.branch_head(repository_id, "feature") == "y1"

      # A refold of x1 (after the excluded paths changed, say) is observed at
      # x1's own run, older than y1's.
      Commits.recompute(project, "x1")
      assert CoverageFixtures.branch_head(repository_id, "feature") == "y1"
    end

    # n1's own advance moves nothing either way: observed before n2's run
    # moved main, or finding main already holds n1.
    for {exit, n1_ago, n2_ago} <- [{"older", -7200, -3600}, {"newer", -3600, -7200}] do
      test "publishes the commit's place when its child's fold advanced the branch past it mid-fold (#{exit} run)", %{
        account: account,
        project: project
      } do
        repository_id =
          CoverageFixtures.seed_history(account, [
            CoverageFixtures.commit("d", [], 0),
            CoverageFixtures.commit("n1", ["d"], 1),
            CoverageFixtures.commit("n2", ["n1"], 2)
          ])

        now = NaiveDateTime.utc_now()
        file = [CoverageFixtures.file("Sources/A.swift", [1, 0])]

        for {sha, ago} <- [{"n1", unquote(n1_ago)}, {"n2", unquote(n2_ago)}] do
          CoverageFixtures.run_with_coverage(project, account, file, %{
            git_commit_sha: sha,
            ran_at: NaiveDateTime.add(now, ago),
            recompute: false
          })
        end

        # n1's fold has read where n1 stands (nowhere yet) when n2's fold
        # advances main through n1, before n1's row exists to be synced.
        stub(Repo, :transaction, &Mimic.call_original(Repo, :transaction, [&1, &2]))

        expect(Repo, :transaction, fn fun, opts ->
          Commits.recompute(project, "n2")
          Mimic.call_original(Repo, :transaction, [fun, opts])
        end)

        Commits.recompute(project, "n1")

        assert {ref_id, position} = GitHistory.position(repository_id, "n1")
        assert %{ref_id: ^ref_id, position: ^position} = Commits.summary(project.id, "n1")
        assert %{ref_id: ref_id_n2, position: position_n2} = Commits.summary(project.id, "n2")
        assert {ref_id_n2, position_n2} == GitHistory.position(repository_id, "n2")
      end
    end
  end

  describe "nearest_measured_ancestor/4" do
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

    defp measure(project, repository_id, shas, schemes \\ ["App"]) do
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
          executable_lines: 1,
          schemes: schemes
        })
      end
    end

    test "is the nearest measured first parent, across the refs' segments", %{
      project: project,
      repository_id: repository_id
    } do
      measure(project, repository_id, ["a"])

      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d", ["App"]) == {"a", 4}
      assert Commits.nearest_measured_ancestor(project.id, repository_id, "f2", ["App"]) == {"a", 3}
    end

    test "is a commit merged in closer than the nearest measured first parent", %{
      project: project,
      repository_id: repository_id
    } do
      measure(project, repository_id, ["a", "f2"])

      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d", ["App"]) == {"f2", 2}
    end

    test "leaves the commit itself out", %{project: project, repository_id: repository_id} do
      measure(project, repository_id, ["d"])

      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d", ["App"]) == nil
    end

    test "walks the first parents of a commit no ref placed down to a segment", %{
      project: project,
      repository_id: repository_id
    } do
      measure(project, repository_id, ["c"])

      assert GitHistory.position(repository_id, "x") == nil
      assert Commits.nearest_measured_ancestor(project.id, repository_id, "x", ["App"]) == {"c", 3}
    end

    test "walks the whole ancestry when no first parent was measured", %{
      project: project,
      repository_id: repository_id
    } do
      measure(project, repository_id, ["f1"])

      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d", ["App"]) == {"f1", 3}
    end

    test "keeps to the commits that measured one of the schemes when given them", %{
      project: project,
      repository_id: repository_id
    } do
      measure(project, repository_id, ["a"], ["App"])
      measure(project, repository_id, ["f2"], ["Kit"])

      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d", ["App", "Kit"]) == {"f2", 2}
      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d", ["App", "Other"]) == {"a", 4}
      assert Commits.nearest_measured_ancestor(project.id, repository_id, "x", ["App"]) == {"a", 5}
      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d", ["Kit"]) == {"f2", 2}
      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d", ["Other"]) == nil
      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d", []) == nil
    end

    test "walks the whole ancestry when no first parent measured the schemes", %{
      project: project,
      repository_id: repository_id
    } do
      measure(project, repository_id, ["a", "c"], ["Kit"])
      measure(project, repository_id, ["f1"], ["App"])

      assert Commits.nearest_measured_ancestor(project.id, repository_id, "d", ["App"]) == {"f1", 3}
    end
  end
end
