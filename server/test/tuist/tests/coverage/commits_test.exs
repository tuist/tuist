defmodule Tuist.Tests.Coverage.CommitsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.ClickHouse.Inserts
  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.IngestRepo
  alias Tuist.TestImpactAnalysis.Baselines
  alias Tuist.TestImpactAnalysis.Carry
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.TestImpactAnalysis.Snapshots
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Reported
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias Tuist.Tests.CoverageCommit
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.CoverageRunFile
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures
  alias TuistTestSupport.Fixtures.TestSelectionFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

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

    assert %{lines: [{1, 1}, {2, 1}, {3, 0}]} =
             Commits.file_detail(project.id, "abc123", "Sources/A.swift")

    assert Commits.file_detail(project.id, "abc123", "Missing.swift") == nil
  end

  test "reads a run's scheme off the run, which a client-reported run gets after its coverage published", %{
    project: project,
    account: account
  } do
    run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1])], %{scheme: nil})

    {:ok, _} =
      Tuist.Tests.create_test(%{
        id: run.id,
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        is_ci: true,
        scheme: "AppTests",
        git_commit_sha: "abc123",
        ran_at: NaiveDateTime.utc_now(),
        test_modules: []
      })

    assert [%{scheme: "AppTests"}] = Commits.runs(project.id, "abc123")
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

  test "lists a run whose product code all came from the binary cache without counters", %{
    project: project,
    account: account
  } do
    # The run measured no product line, so only its test file says it gathered coverage.
    run = CoverageFixtures.run_with_coverage(project, account, [file("Tests/ATests.swift", [1], is_test: true)])

    assert Enum.map(Commits.run_cursor_page(project.id, {:commit, "abc123"}).runs, &{&1.test_run_id, &1.executable_lines}) ==
             [{run.id, 0}]
  end

  test "a scheme only runs from a dirty checkout measured leaves the figure a lower bound, and its runs are listed on request",
       %{project: project, account: account} do
    # Alone, a dirty CI run counts for nothing: the figure is a lower bound of nothing,
    # labelled with where the run ran, out of every comparison.
    dirty =
      CoverageFixtures.run_with_coverage(project, account, [file("Sources/B.swift", [1, 1])], %{
        scheme: "AppTests",
        git_dirty: true,
        git_branch: "feature",
        is_pull_request: true,
        pull_request_number: 9
      })

    summary = Commits.summary(project.id, "abc123")

    assert {summary.reported_kind, Commits.gap_reasons(summary), summary.schemes, summary.test_run_ids} ==
             {"partial", [:dirty_run_excluded], [], []}

    assert {summary.executable_lines, summary.reported_executable_lines} == {0, 0}
    assert {summary.git_branch, summary.pull_request_number} == {"feature", 9}
    assert Commits.status(Commits.signal_complete(project, "abc123")) == :incomplete
    assert Commits.by_shas(project.id, ["abc123"]) == %{}
    assert Map.has_key?(Commits.by_shas(project.id, ["abc123"], listed: true), "abc123")

    clean = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

    summary = Commits.summary(project.id, "abc123")
    assert {summary.schemes, summary.covered_lines, summary.executable_lines} == {["App"], 1, 2}
    assert {summary.reported_kind, Commits.gap_reasons(summary)} == {"partial", [:dirty_run_excluded]}
    assert Commits.status(summary) == :incomplete

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

  test "a local dirty run publishes a commit nothing else measured, but never turns one incomplete", %{
    project: project,
    account: account
  } do
    repository_id =
      CoverageFixtures.seed_history(account, [CoverageFixtures.commit("abc123", [], 0)],
        branch_heads: [{"main", "abc123"}]
      )

    local =
      CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])], %{
        is_ci: false,
        git_dirty: true
      })

    assert {:ok, _job} = Commits.enqueue_recompute(local)
    summary = Commits.summary(project.id, "abc123")

    assert {summary.reported_kind, Commits.gap_reasons(summary), summary.executable_lines} ==
             {"partial", [:dirty_run_excluded], 0}

    # Placed on its ref like any commit, so the branch's commits list it.
    {ref_id, position} = GitHistory.position(repository_id, "abc123")
    assert {summary.repository_id, summary.ref_id, summary.position} == {repository_id, ref_id, position}

    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

    assert {:complete, []} ==
             then(Commits.signal_complete(project, "abc123"), &{Commits.status(&1), Commits.gap_reasons(&1)})

    # A later dirty run of a scheme a clean run measured changes nothing.
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 1])], %{git_dirty: true})
    summary = Commits.summary(project.id, "abc123")
    assert {Commits.status(summary), Commits.gap_reasons(summary), summary.covered_lines} == {:complete, [], 1}

    # Nor does a local dirty run of a scheme no clean run measured, such as
    # one a developer is adding.
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/B.swift", [1])], %{
      scheme: "LocalScheme",
      is_ci: false,
      git_dirty: true
    })

    summary = Commits.summary(project.id, "abc123")
    assert {Commits.status(summary), Commits.gap_reasons(summary), summary.schemes} == {:complete, [], ["App"]}
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

  test "a completion signal is not lost when the first run reports while the signal folds", %{
    project: project,
    account: account
  } do
    stub(Reported, :compute, fn project, sha, opts -> Mimic.call_original(Reported, :compute, [project, sha, opts]) end)

    expect(Reported, :compute, fn project, sha, opts ->
      CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])], %{recompute: false})
      Mimic.call_original(Reported, :compute, [project, sha, opts])
    end)

    # The run was declared after the signal's gate, so the signal's fold may
    # have read part of it: it publishes nothing and leaves the signal to the
    # commit's fold job, which gates again.
    assert Commits.signal_complete(project, "abc123") == nil
    assert Commits.summary(project.id, "abc123") == nil

    assert [job] = all_enqueued(worker: CommitWorker)
    assert :ok = perform_job(CommitWorker, job.args)
    assert %{complete: true, completeness: "signal", covered_lines: 1} = Commits.summary(project.id, "abc123")
  end

  test "a fold that read a run declared after its gate publishes nothing and gates again", %{
    project: project,
    account: account
  } do
    CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])], %{recompute: false})
    Repo.delete_all(Oban.Job)
    key = "#{UUIDv7.generate()}/0"

    # Another shard of the commit declares its rows while the fold reads.
    stub(Reported, :compute, fn project, sha, opts -> Mimic.call_original(Reported, :compute, [project, sha, opts]) end)

    expect(Reported, :compute, fn project, sha, opts ->
      Inserts.record("test_case_runs", key, project.id, NaiveDateTime.utc_now(), sha: sha)
      Mimic.call_original(Reported, :compute, [project, sha, opts])
    end)

    args = %{"project_id" => project.id, "git_commit_sha" => "abc123"}
    assert perform_job(CommitWorker, args) == {:snooze, 5}
    assert Commits.summary(project.id, "abc123") == nil

    Inserts.record("test_case_runs", key, project.id, NaiveDateTime.utc_now(), sha: "abc123", rows: 0)
    assert perform_job(CommitWorker, args) == :ok
    assert %{covered_lines: 1} = Commits.summary(project.id, "abc123")
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

    # The same from the commit's file changes, once they are written.
    CoverageFixtures.seed_history(account, [CoverageFixtures.commit("abc123", [], 0)], branch_heads: [{"main", "abc123"}])
    Oban.drain_queue(queue: :coverage_deltas, with_recursion: true, with_safety: false)
    assert GitHistory.FileChanges.current(repository, "abc123")
    assert %{unmeasured_files_count: 1} = Commits.recompute(project, "abc123")
  end

  test "a run schedules its commit's fold whether its checkout was dirty or not, and one without a commit none", %{
    project: project,
    account: account
  } do
    run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])], %{recompute: false})

    assert {:ok, _job} = Commits.enqueue_recompute(%{run | git_dirty: nil})
    assert {:ok, _job} = Commits.enqueue_recompute(%{run | git_dirty: true})
    assert {:ok, _job} = Commits.enqueue_recompute(%{run | git_dirty: true, is_ci: false})
    assert Commits.enqueue_recompute(%{run | git_commit_sha: ""}) == :skipped
  end

  test "a report that lands while the fold runs gets a job of its own", %{project: project, account: account} do
    run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])], %{recompute: false})
    {:ok, pending} = Commits.enqueue_recompute(run)

    # A second report while the first job is still pending folds with it.
    {:ok, deduped} = Commits.enqueue_recompute(run)
    assert deduped.id == pending.id

    # Once that job is running, the fold it would be deduped into has already
    # read the runs, so the report cannot wait for it: it gets a job of its
    # own, held back until the running fold has published.
    running = start(pending)
    {:ok, own} = Commits.enqueue_recompute(run)
    assert own.id != pending.id
    assert own.state == "scheduled"
    assert DateTime.diff(own.scheduled_at, DateTime.utc_now()) in 590..600

    # Every later report lands in that one job.
    {:ok, again} = Commits.enqueue_recompute(run)
    assert again.id == own.id

    # The fold publishes, then lets the pending one go at once.
    assert :ok = perform_job(running)
    assert [next] = all_enqueued(worker: CommitWorker)
    assert next.id == own.id
    assert DateTime.diff(next.scheduled_at, DateTime.utc_now()) <= 0
    assert %{covered_lines: 1} = Commits.summary(project.id, "abc123")

    # A report after the fold published, while its job is still finishing,
    # is folded after the usual delay.
    Repo.delete_all(from(j in Oban.Job, where: j.id == ^own.id))
    {:ok, after_release} = Commits.enqueue_recompute(run)
    assert after_release.id != pending.id
    assert DateTime.diff(after_release.scheduled_at, DateTime.utc_now()) < 60
  end

  test "a fold that must wait for its runs' inputs ends when a fold is pending after it", %{project: project} do
    {:ok, pending} = CommitWorker.enqueue(project.id, "abc123")
    running = start(pending)
    {:ok, next} = CommitWorker.enqueue(project.id, "abc123")
    Inserts.record("test_case_runs", "#{UUIDv7.generate()}/0", project.id, NaiveDateTime.utc_now(), sha: "abc123")

    assert :ok = perform_job(running)
    assert [%{id: id, scheduled_at: scheduled_at}] = all_enqueued(worker: CommitWorker)
    assert id == next.id
    assert DateTime.diff(scheduled_at, DateTime.utc_now()) <= 0
  end

  test "a fold retried after its node died holds new reports back again", %{project: project} do
    {:ok, pending} = CommitWorker.enqueue(project.id, "abc123")
    running = start(pending)
    assert :ok = perform_job(running)

    # Released on its first attempt; Oban fetching it again starts another.
    start(Repo.get!(Oban.Job, pending.id))
    {:ok, held} = CommitWorker.enqueue(project.id, "abc123")
    assert DateTime.diff(held.scheduled_at, DateTime.utc_now()) in 590..600
  end

  test "a report whose job another insert of the commit's job is writing leaves that one pending", %{project: project} do
    # What Oban returns when another transaction holds its unique lock on the
    # job (never in tests, which run without it): the job, unsaved.
    expect(Oban, :insert, fn changeset ->
      {:ok, job} = Ecto.Changeset.apply_action(changeset, :insert)
      {:ok, %{job | conflict?: true}}
    end)

    assert {:ok, %Oban.Job{id: nil, conflict?: true}} = CommitWorker.enqueue(project.id, "abc123")
  end

  # A job as Oban hands it to a worker: executing, its attempt counted.
  defp start(job) do
    {1, [started]} =
      Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id, select: j),
        set: [state: "executing", attempted_at: DateTime.utc_now()],
        inc: [attempt: 1]
      )

    started
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
    assert {:ok, refold} =
             %{project_id: project.id, git_commit_sha: "abc123"} |> CommitWorker.new(schedule_in: 600) |> Oban.insert()

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

    # The command event as the client reports it (`refold_after_selective_testing/3`
    # also needs the graph it stored only for its targets' count and time).
    defp event(run),
      do: %{
        id: UUIDv7.generate(),
        project_id: run.project_id,
        test_run_id: run.id,
        git_commit_sha: "abc123",
        created_at: NaiveDateTime.utc_now()
      }

    defp stored, do: %{targets: 0, inserted_at: NaiveDateTime.utc_now()}

    test "refold the commit once they are stored", %{project: project, account: account} do
      run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])
      Commits.signal_complete(project, "abc123")
      Oban.drain_queue(queue: :default, with_scheduled: true)

      event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          test_run_id: run.id,
          git_commit_sha: "abc123"
        )

      {:ok, stored} =
        with_flushed_ingestion_buffers(fn ->
          Tuist.Xcode.create_xcode_graph(%{command_event: event, xcode_graph: graph("local")})
        end)

      assert {:ok, %Oban.Job{} = job} = Coverage.refold_after_selective_testing(event, graph("local"), stored)

      assert %{git_commit_sha: "abc123"} = job.args
      assert DateTime.after?(job.scheduled_at, DateTime.utc_now())

      version = Commits.summary(project.id, "abc123").version
      assert :ok = perform_job(CommitWorker, job.args)
      assert %{complete: true, version: new_version} = Commits.summary(project.id, "abc123")
      assert new_version > version
    end

    test "refold the commit when a repository target came from the binary cache", %{project: project, account: account} do
      run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

      cached = %{
        name: "App",
        projects: [
          %{
            "targets" => [
              %{"name" => "Core", "binary_cache_metadata" => %{"hit" => "remote"}},
              %{
                "name" => "Alamofire",
                "binary_cache_metadata" => %{"hit" => "local", "subhashes" => %{"external" => "5.9.0"}}
              }
            ]
          }
        ]
      }

      assert {:ok, %Oban.Job{}} =
               Coverage.refold_after_selective_testing(event(run), cached, stored())

      remote_package_only = update_in(cached, [:projects, Access.at(0), "targets"], &tl/1)

      assert Coverage.refold_after_selective_testing(event(run), remote_package_only, stored()) ==
               :skipped
    end

    test "schedule nothing when no target was skipped, or the event has no run", %{project: project, account: account} do
      run = CoverageFixtures.run_with_coverage(project, account, [file("Sources/A.swift", [1, 0])])

      assert Coverage.refold_after_selective_testing(event(run), graph("miss"), stored()) ==
               :skipped

      assert Coverage.refold_after_selective_testing(%{event(run) | test_run_id: nil}, graph("local"), stored()) ==
               :skipped
    end
  end

  describe "folding a commit whose evidence may have expired" do
    # A full run of AppTests at `sha`: testAdd() with evidence over A.swift.
    defp evidenced_run(project, account, sha, attrs \\ %{}) do
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [file("Sources/A.swift", [1, 0])],
        Map.merge(
          %{
            git_commit_sha: sha,
            test_modules: [
              %{
                name: "AppTests",
                status: "success",
                duration: 1,
                test_cases: [%{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 10}]
              }
            ],
            coverage_evidence: %{
              paths: ["Sources/A.swift"],
              scopes: [
                %{kind: "test", module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0], lines: [[1, 1]]}
              ]
            }
          },
          attrs
        )
      )
    end

    # A shard report of the run three days old, which its totals cover: its
    # evidence is past the two days `coverage_files` keeps it, so merges may
    # have deleted any of it.
    defp report_days_ago(run, days) do
      inserted_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 86_400)

      [totals] =
        ClickHouseRepo.all(from(c in CoverageRun, where: c.test_run_id == ^run.id, order_by: [desc: c.version], limit: 1))

      IngestRepo.insert_all(CoverageRun, [
        %{
          Map.take(totals, CoverageRun.__schema__(:fields))
          | version: totals.version + 1,
            report_shards: totals.report_shards ++ [1],
            report_inserted_at: totals.report_inserted_at ++ [inserted_at]
        }
      ])

      IngestRepo.insert_all(CoverageRunFile, [
        %{
          test_run_id: run.id,
          project_id: run.project_id,
          shard_index: 1,
          build_system: "xcode",
          path: "Sources/Old.swift",
          layout_id: 1,
          git_commit_sha: run.git_commit_sha,
          targets: ["App"],
          covered_lines: 0,
          executable_lines: 1,
          execution_counts: [],
          function_execution_counts: [],
          function_covered_lines: [],
          inserted_at: inserted_at
        }
      ])
    end

    defp snapshots(project), do: Repo.all(from(s in Snapshot, where: s.project_id == ^project.id, order_by: s.id))

    test "writes no test map from a run whose evidence may be gone", %{account: account, project: project} do
      CoverageFixtures.seed_history(account, [CoverageFixtures.commit("old", [], 0)])
      run = evidenced_run(project, account, "old", %{recompute: false})
      report_days_ago(run, 3)

      Commits.recompute(project, "old")

      assert snapshots(project) == []
    end

    test "keeps the commit's checkpoint when a run arrives beside one whose evidence may be gone",
         %{account: account, project: project} do
      CoverageFixtures.seed_history(account, [CoverageFixtures.commit("old", [], 0)])
      first = evidenced_run(project, account, "old")
      assert [%Snapshot{kind: :checkpoint} = checkpoint] = snapshots(project)

      # Days later the first run's evidence is expiring and another full run
      # of the scope reports at the commit: a checkpoint over both would
      # read whatever is left of the first run's evidence.
      report_days_ago(first, 3)
      evidenced_run(project, account, "old")

      assert snapshots(project) == [checkpoint]
      assert %{checkpoint: ^checkpoint} = Snapshots.at(project.id, "old", "App", "")
    end

    test "writes the checkpoint of a scope that has none from its runs whose evidence is whole",
         %{account: account, project: project} do
      CoverageFixtures.seed_history(account, [CoverageFixtures.commit("old", [], 0)])
      first = evidenced_run(project, account, "old", %{recompute: false})
      report_days_ago(first, 3)
      second = evidenced_run(project, account, "old")

      assert [%Snapshot{kind: :checkpoint, test_run_ids: [run_id], tests_count: 1}] = snapshots(project)
      assert run_id == second.id
    end
  end

  describe "a selective run whose every skip was carried" do
    setup %{account: account} do
      CoverageFixtures.seed_history(account, [
        CoverageFixtures.commit("base", [], 0),
        CoverageFixtures.commit("mid", ["base"], 1),
        CoverageFixtures.commit("head", ["mid"], 2),
        CoverageFixtures.commit("tip", ["head"], 3)
      ])

      stub(GitHistory, :settings, fn project ->
        GitHistory |> call_original(:settings, [project]) |> Map.put(:tracked_file_globs, [])
      end)

      :ok
    end

    defp case_run(name, suite), do: %{name: name, test_suite_name: suite, status: "success", duration: 1}

    defp text_kit_tests,
      do: %{
        name: "TextKitTests",
        status: "success",
        duration: 1,
        test_cases: [case_run("testPad()", "TextTests"), case_run("testTrim()", "TextTests")]
      }

    defp hashed(project, run, hits) do
      event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test", test_run_id: run.id)

      for {target, hit, hash} <- hits do
        XcodeFixtures.xcode_target_fixture(
          command_event_id: event.id,
          name: target,
          selective_testing_hash: hash,
          selective_testing_hit: hit
        )
      end

      CoverageFixtures.recompute_commit(run)
      run
    end

    # AppTests and TextKitTests run whole at `base`, with each TextKitTests
    # test's lines in Text.swift, its suite's setup's (3) and its target's
    # outside any test (5).
    # `opts` sets its `status` and the other targets it built (`hits`).
    defp full_run(project, account, ran_at, opts \\ %{}) do
      run =
        CoverageFixtures.run_with_coverage(
          project,
          account,
          [file("Sources/Math.swift", [1, 1, 0]), file("Sources/Text.swift", [1, 1, 1, 0, 1])],
          %{
            git_commit_sha: "base",
            ran_at: ran_at,
            status: Map.get(opts, :status, "success"),
            recompute: false,
            test_modules: [
              %{name: "AppTests", status: "success", duration: 1, test_cases: [case_run("testAdd()", "MathTests")]},
              text_kit_tests()
            ],
            coverage_evidence: %{
              paths: ["Sources/Math.swift", "Sources/Text.swift"],
              scopes: [
                %{kind: "test", module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0], lines: [[1, 2]]},
                %{
                  kind: "test",
                  module: "TextKitTests",
                  suite: "TextTests",
                  name: "testPad()",
                  files: [1],
                  lines: [[2, 2]]
                },
                %{
                  kind: "test",
                  module: "TextKitTests",
                  suite: "TextTests",
                  name: "testTrim()",
                  files: [1],
                  lines: [[1, 1]]
                },
                %{kind: "suite", module: "TextKitTests", suite: "TextTests", name: "", files: [1], lines: [[3, 3]]},
                %{kind: "target", module: "TextKitTests", suite: "", name: "", files: [1], lines: [[5, 5]]}
              ]
            }
          }
        )

      hashed(project, run, [{"AppTests", :miss, "app"}, {"TextKitTests", :miss, "text"} | Map.get(opts, :hits, [])])
    end

    # AppTests runs at `sha` and selective testing skips TextKitTests under
    # `text_hash`, and the other targets `attrs` name (`hits`).
    defp selective_run(project, account, sha, text_hash, attrs \\ %{}) do
      {hits, attrs} = Map.pop(attrs, :hits, [])

      run =
        CoverageFixtures.run_with_coverage(
          project,
          account,
          [file("Sources/Math.swift", [1, 1, 0])],
          Map.merge(
            %{
              git_commit_sha: sha,
              partial: true,
              recompute: false,
              test_modules: [
                %{name: "AppTests", status: "success", duration: 1, test_cases: [case_run("testAdd()", "MathTests")]}
              ],
              coverage_evidence: %{
                paths: ["Sources/Math.swift"],
                scopes: [
                  %{kind: "test", module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0], lines: [[1, 2]]}
                ]
              }
            },
            attrs
          )
        )

      hashed(project, run, [{"AppTests", :miss, "app-" <> sha}, {"TextKitTests", :remote, text_hash} | hits])
    end

    defp checkpoints(project, sha),
      do:
        Repo.all(
          from(s in Snapshot, where: s.project_id == ^project.id and s.commit_sha == ^sha and s.kind == :checkpoint)
        )

    # The lines a snapshot holds for a TextKitTests test, its suite's setup
    # and its target, as a carry plan reads them.
    defp text_kit_lines(project, snapshot, test) do
      [[idx]] =
        Snapshots.query!(
          """
          SELECT t.test_idx FROM test_impact_snapshot_tests AS t FINAL
          INNER JOIN (SELECT DISTINCT id, name FROM test_cases WHERE project_id = {project_id:Int64}) AS c
            ON c.id = t.test_case_id
          WHERE t.project_id = {project_id:Int64} AND t.snapshot_id = {id:UUID} AND c.name = {name:String}
          """,
          %{project_id: project.id, id: snapshot.id, name: test}
        )

      plan = [
        %{
          snapshot_id: snapshot.id,
          checkpoint_id: snapshot.checkpoint_id || "00000000-0000-0000-0000-000000000000",
          idx: Snapshots.idx_chunks([idx]),
          targets: ["TextKitTests"],
          source: %{run_id: ""}
        }
      ]

      {sql, params} = Carry.lines_sql(project.id, plan)
      sql |> Snapshots.query!(params) |> Enum.map(fn [path, lines, _rank, _run] -> {path, lines} end)
    end

    test "copies the targets skipped by hash into its checkpoint, which selection walks to and carry reads", %{
      account: account,
      project: project
    } do
      # Measured in an earlier week than the copy, whose rows live in its own.
      full_run(project, account, NaiveDateTime.add(NaiveDateTime.utc_now(), -9 * 86_400))
      [original] = checkpoints(project, "base")
      head = selective_run(project, account, "head", "text")

      assert [copy] = checkpoints(project, "head")
      assert copy.test_run_ids == [head.id]
      assert copy.tests_count == 3
      assert copy.carried_targets == ["TextKitTests\u001Ftext"]
      assert copy.evidence_measured_at == original.ran_at
      assert DateTime.diff(copy.expires_at, copy.ran_at, :day) == 31

      for test <- ["testPad()", "testTrim()"] do
        assert text_kit_lines(project, copy, test) == text_kit_lines(project, original, test)
      end

      assert text_kit_lines(project, copy, "testPad()") == [{"Sources/Text.swift", [2, 3, 5]}]
      assert {:ok, %{sha: "head", distance: 1}} = Baselines.resolve(project, %{commit_sha: "tip", scheme: "App"})

      # Once the snapshot it was measured in expires, the copy carries it.
      Repo.update_all(from(s in Snapshot, where: s.id == ^original.id), set: [expires_at: DateTime.utc_now()])
      selective_run(project, account, "tip", "text")

      assert %{kind: "reported", carried_tests_count: 2, carried_from: ["base"]} = Reported.compute(project, "tip")
    end

    test "lists a target without tests it skipped, which the next commit skipping it finds empty there", %{
      account: account,
      project: project
    } do
      full_run(project, account, NaiveDateTime.utc_now(), %{hits: [{"EmptyKitTests", :miss, "empty"}]})
      selective_run(project, account, "head", "text", %{hits: [{"EmptyKitTests", :local, "empty"}]})

      assert %{carried_tests_count: 2, gap_reasons: reasons} = Reported.compute(project, "head")
      refute :target_without_history in Coverage.GapReasons.decode(reasons)
      assert [copy] = checkpoints(project, "head")
      assert copy.tests_count == 3
      assert Enum.sort(copy.carried_targets) == ["EmptyKitTests\u001Fempty", "TextKitTests\u001Ftext"]

      selective_run(project, account, "tip", "text", %{hits: [{"EmptyKitTests", :local, "empty"}]})

      assert %{carried_tests_count: 2, gap_reasons: reasons} = Reported.compute(project, "tip")
      refute :target_without_history in Coverage.GapReasons.decode(reasons)
      assert [tip] = checkpoints(project, "tip")
      assert {tip.tests_count, Enum.sort(tip.carried_targets)} == {copy.tests_count, Enum.sort(copy.carried_targets)}
    end

    test "writes a checkpoint for a run whose only skip is a target without tests", %{
      account: account,
      project: project
    } do
      full_run(project, account, NaiveDateTime.utc_now(), %{hits: [{"EmptyKitTests", :miss, "empty"}]})

      head =
        CoverageFixtures.run_with_coverage(project, account, [file("Sources/Math.swift", [1, 1, 0])], %{
          git_commit_sha: "head",
          partial: true,
          recompute: false,
          test_modules: [
            %{name: "AppTests", status: "success", duration: 1, test_cases: [case_run("testAdd()", "MathTests")]}
          ]
        })

      hashed(project, head, [{"AppTests", :miss, "app-head"}, {"EmptyKitTests", :local, "empty"}])

      assert %{kind: "measured"} = Reported.compute(project, "head")
      assert [%Snapshot{tests_count: 1, carried_targets: ["EmptyKitTests\u001Fempty"]}] = checkpoints(project, "head")
    end

    test "writes no checkpoint when a target without tests it skipped was built under another hash", %{
      account: account,
      project: project
    } do
      full_run(project, account, NaiveDateTime.utc_now(), %{hits: [{"EmptyKitTests", :miss, "old"}]})
      selective_run(project, account, "head", "text", %{hits: [{"EmptyKitTests", :local, "empty"}]})

      assert %{carried_tests_count: 2, gap_reasons: reasons} = Reported.compute(project, "head")
      assert :target_without_history in Coverage.GapReasons.decode(reasons)
      assert checkpoints(project, "head") == []
    end

    test "writes no checkpoint when only a failed run built a target without tests it skipped", %{
      account: account,
      project: project
    } do
      full_run(project, account, NaiveDateTime.utc_now(), %{
        status: "failure",
        hits: [{"EmptyKitTests", :miss, "empty"}]
      })

      selective_run(project, account, "head", "text", %{hits: [{"EmptyKitTests", :local, "empty"}]})

      assert %{carried_tests_count: 2, gap_reasons: reasons} = Reported.compute(project, "head")
      assert :target_without_history in Coverage.GapReasons.decode(reasons)
      assert checkpoints(project, "head") == []
    end

    test "on a pull request's merge checkout writes no checkpoint", %{account: account, project: project} do
      full_run(project, account, NaiveDateTime.utc_now())
      selective_run(project, account, "head", "text", %{git_ref: "refs/pull/7/merge"})

      assert %{carried_tests_count: 2} = Reported.compute(project, "head")
      assert checkpoints(project, "head") == []
    end

    test "writes no checkpoint while a shard's report is on the replicas but not in the totals", %{
      account: account,
      project: project
    } do
      full_run(project, account, NaiveDateTime.utc_now())
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)
      sharded = %{shard_plan_id: plan.id, shard_index: 0}
      head = selective_run(project, account, "head", "text", sharded)

      # Shard 1's rows land before its totals do.
      IngestRepo.insert_all(CoverageRunFile, [
        %{
          test_run_id: head.id,
          project_id: project.id,
          shard_index: 1,
          build_system: "xcode",
          path: "Sources/Math.swift",
          layout_id: 1,
          git_commit_sha: "head",
          targets: ["App"],
          covered_lines: 0,
          executable_lines: 1,
          execution_counts: [],
          function_execution_counts: [],
          function_covered_lines: [],
          inserted_at: NaiveDateTime.utc_now()
        }
      ])

      CoverageFixtures.recompute_commit(head)
      assert checkpoints(project, "head") == []

      CoverageFixtures.run_with_coverage(project, account, [file("Sources/Math.swift", [1, 1, 0])], %{
        sharded
        | shard_index: 1
      })

      assert [%Snapshot{carried_targets: ["TextKitTests\u001Ftext"]}] = checkpoints(project, "head")
    end

    test "copies a target from an overlay with the tests it doesn't override from its checkpoint", %{
      account: account,
      project: project
    } do
      full_run(project, account, NaiveDateTime.utc_now())
      [original] = checkpoints(project, "base")

      impact = TestSelectionFixtures.run_fixture(project_id: project.id, commit_sha: "mid", baseline_sha: "base")
      TestSelectionFixtures.diff_fixture(project_id: project.id, commit_sha: "mid", baseline_sha: "base")

      # A run of TextKitTests alone, skipping AppTests by name: only testTrim()
      # changed, so the overlay holds it and its target's new lines (4).
      mid =
        CoverageFixtures.run_with_coverage(project, account, [file("Sources/Text.swift", [1, 1, 1, 1, 1])], %{
          git_commit_sha: "mid",
          partial: true,
          recompute: false,
          test_impact_run_id: impact.id,
          skip_test_identifiers: ["AppTests/MathTests/testAdd()"],
          test_modules: [text_kit_tests()],
          coverage_evidence: %{
            paths: ["Sources/Text.swift"],
            scopes: [
              %{kind: "test", module: "TextKitTests", suite: "TextTests", name: "testPad()", files: [0], lines: [[2, 2]]},
              %{
                kind: "test",
                module: "TextKitTests",
                suite: "TextTests",
                name: "testTrim()",
                files: [0],
                lines: [[1, 2]]
              },
              %{kind: "suite", module: "TextKitTests", suite: "TextTests", name: "", files: [0], lines: [[3, 3]]},
              %{kind: "target", module: "TextKitTests", suite: "", name: "", files: [0], lines: [[4, 4]]}
            ]
          }
        })

      hashed(project, mid, [{"TextKitTests", :miss, "text-mid"}])

      assert [%Snapshot{kind: :overlay, checkpoint_id: checkpoint_id, overridden_count: 1}] =
               project
               |> snapshots()
               |> Enum.filter(&(&1.commit_sha == "mid"))

      assert checkpoint_id == original.id

      selective_run(project, account, "head", "text-mid")

      assert [copy] = checkpoints(project, "head")
      assert text_kit_lines(project, copy, "testPad()") == [{"Sources/Text.swift", [2, 3, 4]}]
      assert text_kit_lines(project, copy, "testTrim()") == [{"Sources/Text.swift", [1, 2, 3, 4]}]
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

    test "makes the project's default branch the root once the project names it", %{
      account: account,
      project: project
    } do
      repository_id =
        CoverageFixtures.seed_history(account, [
          CoverageFixtures.commit("a", [], 0),
          CoverageFixtures.commit("b", ["a"], 1)
        ])

      file = [CoverageFixtures.file("Sources/A.swift", [1, 0])]
      CoverageFixtures.run_with_coverage(project, account, file, %{git_commit_sha: "a", git_branch: "develop"})
      assert GitHistory.ref(repository_id, "develop").parent_ref_id

      project = project |> Ecto.Changeset.change(default_branch: "develop") |> Repo.update!()
      CoverageFixtures.run_with_coverage(project, account, file, %{git_commit_sha: "b", git_branch: "develop"})

      assert GitHistory.ref(repository_id, "develop").parent_ref_id == nil
      assert GitHistory.position(repository_id, "a") == {GitHistory.ref(repository_id, "develop").id, 1}
    end

    test "publishes no place for a commit only a detached ref holds", %{account: account, project: project} do
      repository_id =
        CoverageFixtures.seed_history(
          account,
          [CoverageFixtures.commit("d", [], 0), CoverageFixtures.commit("x", ["d"], 1)],
          branch_heads: [{"main", "d"}]
        )

      assert GitHistory.with_refs_lock(repository_id, fn -> GitHistory.detach(repository_id, "x") end)

      # A run that reports no branch advances no ref.
      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])], %{
        git_commit_sha: "x",
        git_branch: nil
      })

      assert %{detached: true, head_sha: "x"} = GitHistory.ref(repository_id, "detached:x")
      assert %{ref_id: nil, position: nil} = Commits.summary(project.id, "x")
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
