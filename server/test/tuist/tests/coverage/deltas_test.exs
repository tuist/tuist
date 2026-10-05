defmodule Tuist.Tests.Coverage.DeltasTest do
  # Every read from the deltas is compared with the raw read of the same
  # commit (`Commits`), which stays the reference while readers move over.
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Deltas
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Workers.DeltaWorker
  alias Tuist.Tests.CoverageCommit
  alias Tuist.Tests.CoverageFileDelta
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")
    %{account: account, project: project}
  end

  defp file(path, counts, opts \\ []), do: CoverageFixtures.file(path, counts, opts)

  defp measure(project, account, sha, files, attrs \\ %{}),
    do: CoverageFixtures.run_with_coverage(project, account, files, Map.merge(%{git_commit_sha: sha}, attrs))

  defp complete(project, sha), do: Commits.signal_complete(project, sha)

  # Runs every queued fold and delta write, and whatever they queue.
  defp settle do
    drain = &Oban.drain_queue(queue: &1, with_scheduled: true, with_recursion: true, with_safety: false)

    # A refold queues a delta write, and a delta write can queue another.
    fn -> drain.(:default).success + drain.(:coverage_deltas).success end
    |> Stream.repeatedly()
    |> Enum.find(&(&1 == 0))
  end

  defp linear(account, shas) do
    CoverageFixtures.seed_history(
      account,
      shas
      |> Enum.with_index()
      |> Enum.map(fn {sha, index} ->
        CoverageFixtures.commit(sha, if(index == 0, do: [], else: [Enum.at(shas, index - 1)]), index)
      end)
    )
  end

  # The commit's rows as stored, by path.
  defp rows(project, sha) do
    ClickHouseRepo.all(
      from(d in CoverageFileDelta,
        hints: ["FINAL"],
        where: d.project_id == ^project.id and d.git_commit_sha == ^sha,
        order_by: d.path,
        select: %{
          path: d.path,
          kind: d.kind,
          covered_lines: d.covered_lines,
          executable_lines: d.executable_lines,
          base_sha: d.base_sha,
          ref_id: d.ref_id
        }
      )
    )
  end

  defp refs(project, shas), do: shas |> Enum.flat_map(&rows(project, &1)) |> Enum.map(& &1.ref_id) |> Enum.uniq()

  defp raw_files(project, sha) do
    project.id
    |> Commits.final_files(sha)
    |> Enum.filter(&(&1.executable_lines > 0))
    |> Enum.map(&Map.take(&1, [:path, :covered_lines, :executable_lines]))
  end

  defp assert_parity(project, sha) do
    raw = raw_files(project, sha)
    assert raw != []
    assert Deltas.files(project.id, sha) == raw

    for sort <- [{:coverage, :asc}, {:coverage, :desc}, {:path, :desc}], search <- ["", "a"], page <- [1, 2] do
      {files, count} = Commits.list_files(project.id, sha, page, 2, sort: sort, search: search)

      assert Deltas.list_files(project.id, sha, page, 2, sort: sort, search: search) ==
               {Enum.map(files, &Map.take(&1, [:path, :covered_lines, :executable_lines])), count}
    end

    assert Deltas.targets(project.id, sha) == Commits.targets(project.id, sha)
  end

  defp assert_changes_parity(project, from_sha, to_sha) do
    assert Deltas.changed_files(project.id, from_sha, to_sha, 5) == Commits.changed_files(project.id, from_sha, to_sha, 5)
  end

  # The file's trend from the deltas against the raw one, over the commits.
  defp assert_trend_parity(project, path, shas) do
    points = Enum.map(shas, &%{git_commit_sha: &1})

    raw =
      project
      |> History.file_points(path, points)
      |> Map.new(&{&1.git_commit_sha, Map.take(&1, [:covered_lines, :executable_lines])})

    assert Deltas.file_figures(project.id, path, shas) == raw
  end

  describe "a branch's complete commits" do
    test "store only the files that changed, and read back each commit's files", %{project: project, account: account} do
      linear(account, ~w(a b c d))
      base = [file("Sources/A.swift", [1, 0, 0]), file("Sources/B.swift", [1, 1, 0]), file("Sources/C.swift", [0, 0])]

      measure(project, account, "a", base ++ [file("Sources/E.swift", [1]), file("Sources/F.swift", [1, 0])])

      measure(project, account, "b", [
        file("Sources/A.swift", [1, 1, 0]) | tl(base) ++ [file("Sources/E.swift", [1]), file("Sources/F.swift", [1, 0])]
      ])

      # C.swift is gone and D.swift is new.
      c_files = [
        file("Sources/A.swift", [1, 1, 0]),
        file("Sources/B.swift", [1, 1, 0]),
        file("Sources/D.swift", [1, 1]),
        file("Sources/E.swift", [1]),
        file("Sources/F.swift", [1, 0])
      ]

      measure(project, account, "c", c_files)
      measure(project, account, "d", c_files)

      for sha <- ~w(a b c d), do: complete(project, sha)
      settle()

      for sha <- ~w(a b c d), do: assert_parity(project, sha)

      # The first commit has nothing below it: a checkpoint of every file.
      assert project |> rows("a") |> Enum.map(& &1.kind) |> Enum.uniq() == ["checkpoint"]
      assert length(rows(project, "a")) == 5

      assert [%{path: "Sources/A.swift", kind: "delta", covered_lines: 2, base_sha: "a"}] = rows(project, "b")

      assert [
               %{path: "Sources/C.swift", executable_lines: 0, kind: "delta"},
               %{path: "Sources/D.swift", covered_lines: 2, kind: "delta"}
             ] = rows(project, "c")

      assert rows(project, "d") == []

      assert_changes_parity(project, "a", "d")
      assert_changes_parity(project, "b", "c")
      assert_trend_parity(project, "Sources/A.swift", ~w(a b c d))
      assert_trend_parity(project, "Sources/C.swift", ~w(a b c d))
    end

    test "write a checkpoint once the deltas since the last one reach the file count", %{
      project: project,
      account: account
    } do
      linear(account, ~w(a b c))
      measure(project, account, "a", [file("Sources/A.swift", [0, 0]), file("Sources/B.swift", [0, 0])])
      measure(project, account, "b", [file("Sources/A.swift", [1, 0]), file("Sources/B.swift", [0, 0])])
      measure(project, account, "c", [file("Sources/A.swift", [1, 0]), file("Sources/B.swift", [1, 0])])

      for sha <- ~w(a b c), do: complete(project, sha)
      settle()

      assert [%{kind: "delta"}] = rows(project, "b")
      # One delta below and one here make two, the commit's file count.
      assert [%{kind: "checkpoint"}, %{kind: "checkpoint"}] = rows(project, "c")
      for sha <- ~w(a b c), do: assert_parity(project, sha)
    end

    test "are compared with the commit completed below them, whatever order they completed in", %{
      project: project,
      account: account
    } do
      linear(account, ~w(a b c))

      measure(project, account, "a", [
        file("Sources/A.swift", [1, 0, 0]),
        file("Sources/B.swift", [0, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      measure(project, account, "b", [
        file("Sources/A.swift", [1, 1, 0]),
        file("Sources/B.swift", [0, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      measure(project, account, "c", [
        file("Sources/A.swift", [1, 1, 0]),
        file("Sources/B.swift", [1, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      complete(project, "a")
      complete(project, "c")
      settle()

      # b is still in progress: c is compared with a, and b reads raw.
      assert "Sources/A.swift" in Enum.map(rows(project, "c"), & &1.path)
      assert Deltas.files(project.id, "b") == nil

      complete(project, "b")
      settle()

      assert [%{path: "Sources/B.swift", base_sha: "b"}] = rows(project, "c")
      for sha <- ~w(a b c), do: assert_parity(project, sha)
      assert_changes_parity(project, "a", "c")
    end

    test "are rewritten, with the commit above, when a late run changes a complete commit", %{
      project: project,
      account: account
    } do
      linear(account, ~w(a b c))

      measure(project, account, "a", [
        file("Sources/A.swift", [1, 0, 0]),
        file("Sources/B.swift", [0, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      measure(project, account, "b", [
        file("Sources/A.swift", [1, 0, 0]),
        file("Sources/B.swift", [0, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      measure(project, account, "c", [
        file("Sources/A.swift", [1, 1, 0]),
        file("Sources/B.swift", [0, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      for sha <- ~w(a b c), do: complete(project, sha)
      settle()
      assert rows(project, "b") == []

      # Another scheme reports b after it completed.
      measure(project, account, "b", [file("Sources/A.swift", [1, 1, 1])], %{scheme: "Other"})
      settle()

      assert [%{path: "Sources/A.swift", covered_lines: 3}] = rows(project, "b")
      for sha <- ~w(a b c), do: assert_parity(project, sha)
    end

    test "on a branch read what the branch changed over what its parent held at the fork", %{
      project: project,
      account: account
    } do
      # main: a → b → c; feature: f1 → f2 off b.
      CoverageFixtures.seed_history(account, [
        CoverageFixtures.commit("a", [], 0),
        CoverageFixtures.commit("b", ["a"], 1),
        CoverageFixtures.commit("c", ["b"], 2),
        CoverageFixtures.commit("f1", ["b"], 3),
        CoverageFixtures.commit("f2", ["f1"], 4)
      ])

      measure(project, account, "a", [
        file("Sources/A.swift", [1, 0, 0]),
        file("Sources/B.swift", [0, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      measure(project, account, "b", [
        file("Sources/A.swift", [1, 1, 0]),
        file("Sources/B.swift", [0, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      measure(project, account, "c", [
        file("Sources/A.swift", [1, 1, 1]),
        file("Sources/B.swift", [0, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      feature = %{git_branch: "feature"}

      measure(
        project,
        account,
        "f1",
        [file("Sources/A.swift", [1, 1, 0]), file("Sources/B.swift", [1, 0, 0]), file("Sources/Z.swift", [1])],
        feature
      )

      measure(
        project,
        account,
        "f2",
        [file("Sources/A.swift", [1, 1, 0]), file("Sources/B.swift", [1, 1, 0]), file("Sources/Z.swift", [1])],
        feature
      )

      for sha <- ~w(a b c f1 f2), do: complete(project, sha)
      settle()

      for sha <- ~w(a b c f1 f2), do: assert_parity(project, sha)
      # f1 changed only B.swift from b, below the fork; c's A.swift is not on its chain.
      assert [%{path: "Sources/B.swift", base_sha: "b"}] = rows(project, "f1")
      assert_changes_parity(project, "b", "f2")
      assert_changes_parity(project, "c", "f2")
      assert_trend_parity(project, "Sources/A.swift", ~w(a b c f1 f2))
    end

    test "move with their commits when the default branch fast-forwards over a branch", %{
      project: project,
      account: account
    } do
      repository_id =
        CoverageFixtures.seed_history(account, [
          CoverageFixtures.commit("a", [], 0),
          CoverageFixtures.commit("b", ["a"], 1),
          CoverageFixtures.commit("p1", ["b"], 2),
          CoverageFixtures.commit("p2", ["p1"], 3)
        ])

      measure(project, account, "a", [
        file("Sources/A.swift", [1, 0, 0]),
        file("Sources/B.swift", [0, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      measure(project, account, "b", [
        file("Sources/A.swift", [1, 1, 0]),
        file("Sources/B.swift", [0, 0, 0]),
        file("Sources/Z.swift", [1])
      ])

      feature = %{git_branch: "feature"}

      measure(
        project,
        account,
        "p1",
        [file("Sources/A.swift", [1, 1, 0]), file("Sources/B.swift", [1, 0, 0]), file("Sources/Z.swift", [1])],
        feature
      )

      measure(
        project,
        account,
        "p2",
        [file("Sources/A.swift", [1, 1, 1]), file("Sources/B.swift", [1, 0, 0]), file("Sources/Z.swift", [1])],
        feature
      )

      for sha <- ~w(a b p1 p2), do: complete(project, sha)
      settle()

      feature_ref = GitHistory.ref(repository_id, "feature").id
      assert refs(project, ~w(p1 p2)) == [feature_ref]

      GitHistory.record_branch_head(repository_id, "main", "p2", "main")
      settle()

      main_ref = GitHistory.ref(repository_id, "main").id
      assert refs(project, ~w(p1 p2)) == [main_ref]

      assert ClickHouseRepo.all(
               from(d in CoverageFileDelta,
                 hints: ["FINAL"],
                 where: d.project_id == ^project.id and d.ref_id == ^feature_ref,
                 select: d.path
               )
             ) == []

      for sha <- ~w(a b p1 p2), do: assert_parity(project, sha)
      assert_changes_parity(project, "a", "p2")
    end

    test "give way to the commit a force-push puts in a rewritten commit's place", %{
      project: project,
      account: account
    } do
      repository_id = linear(account, ~w(a b c))

      measure(project, account, "a", [
        file("Sources/A.swift", [1, 0, 0]),
        file("Sources/B.swift", [0, 0]),
        file("Sources/Z.swift", [1])
      ])

      measure(project, account, "b", [
        file("Sources/A.swift", [1, 1, 0]),
        file("Sources/B.swift", [0, 0]),
        file("Sources/Z.swift", [1])
      ])

      measure(project, account, "c", [
        file("Sources/A.swift", [1, 1, 0]),
        file("Sources/B.swift", [1, 0]),
        file("Sources/Z.swift", [1])
      ])

      for sha <- ~w(a b c), do: complete(project, sha)
      settle()
      assert [%{path: "Sources/B.swift"}] = rows(project, "c")

      # c is rewritten as c2, on top of b, in the same place.
      CoverageFixtures.seed_history(account, [CoverageFixtures.commit("c2", ["b"], 3)])
      GitHistory.record_branch_head(repository_id, "main", "c2", "main")

      measure(project, account, "c2", [
        file("Sources/A.swift", [1, 1, 1]),
        file("Sources/B.swift", [0, 0]),
        file("Sources/Z.swift", [1])
      ])

      complete(project, "c2")
      settle()

      assert {_ref_id, position} = GitHistory.position(repository_id, "c2")

      assert Repo.one(
               from(c in CoverageCommit, where: c.project_id == ^project.id and c.git_commit_sha == "c", select: c.ref_id)
             ) == nil

      assert rows(project, "c") == []
      assert [%{path: "Sources/A.swift", covered_lines: 3}] = rows(project, "c2")

      assert ClickHouseRepo.one(
               from(d in CoverageFileDelta,
                 hints: ["FINAL"],
                 where: d.project_id == ^project.id and d.position == ^position,
                 select: count()
               )
             ) == 1

      assert_parity(project, "c2")
      assert_changes_parity(project, "a", "c2")
    end

    test "are rebuilt where a rebuild of the refs places their commits", %{project: project, account: account} do
      repository_id = linear(account, ~w(a b c))
      measure(project, account, "a", [file("Sources/A.swift", [1, 0, 0])])
      measure(project, account, "b", [file("Sources/A.swift", [1, 1, 0])])
      measure(project, account, "c", [file("Sources/A.swift", [1, 1, 1])])
      for sha <- ~w(a b c), do: complete(project, sha)
      settle()

      # A bug left the copies on coverage elsewhere; the rebuild puts them back.
      Repo.update_all(from(c in CoverageCommit, where: c.project_id == ^project.id), set: [position: nil, ref_id: nil])
      GitHistory.rebuild_refs(repository_id)
      settle()

      for sha <- ~w(a b c), do: assert_parity(project, sha)
    end
  end

  test "a commit coverage was carried into stores its files with the carried coverage", %{
    project: project,
    account: account
  } do
    stub(GitHistory, :settings, fn project ->
      GitHistory |> call_original(:settings, [project]) |> Map.put(:tracked_file_globs, [])
    end)

    linear(account, ~w(base head))

    tests = [
      %{module: "AppTests", suite: "MathTests", name: "testAdd()"},
      %{module: "AppTests", suite: "TextTests", name: "testTrim()"}
    ]

    test_case = fn name, suite -> %{name: name, test_suite_name: suite, status: "success", duration: 1} end
    modules = fn cases -> [%{name: "AppTests", status: "success", duration: 1, test_cases: cases}] end

    measure(
      project,
      account,
      "base",
      [file("Sources/Math.swift", [1, 1, 0]), file("Sources/Text.swift", [1, 1, 1, 0])],
      %{
        test_modules: modules.([test_case.("testAdd()", "MathTests"), test_case.("testTrim()", "TextTests")]),
        enumerated_tests: tests,
        coverage_evidence: %{
          paths: ["Sources/Math.swift", "Sources/Text.swift"],
          scopes: [
            %{kind: "test", module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0], lines: [[1, 2]]},
            %{kind: "test", module: "AppTests", suite: "TextTests", name: "testTrim()", files: [1], lines: [[1, 3]]}
          ]
        }
      }
    )

    # Only testAdd() ran: Text.swift's lines are carried from base.
    measure(
      project,
      account,
      "head",
      [file("Sources/Math.swift", [1, 1, 0]), file("Sources/Text.swift", [0, 0, 0, 0])],
      %{
        partial: true,
        test_modules: modules.([test_case.("testAdd()", "MathTests")]),
        enumerated_tests: tests
      }
    )

    for sha <- ~w(base head), do: complete(project, sha)
    settle()

    assert Commits.carried?(Commits.summary(project.id, "head"))

    assert %{path: "Sources/Text.swift", covered_lines: 3} =
             Enum.find(Deltas.files(project.id, "head"), &(&1.path == "Sources/Text.swift"))

    assert rows(project, "head") == []
    for sha <- ~w(base head), do: assert_parity(project, sha)
  end

  test "a version whose runs' rows don't add up to its totals is not written, and reads stay raw", %{
    project: project,
    account: account
  } do
    linear(account, ~w(a))
    measure(project, account, "a", [file("Sources/A.swift", [1, 0])])
    complete(project, "a")
    settle()
    assert Deltas.files(project.id, "a") == raw_files(project, "a")

    # A version published over rows that have since expired, or not reached
    # this replica yet.
    Repo.update_all(from(c in CoverageCommit, where: c.project_id == ^project.id), inc: [covered_lines: 1, version: 1])
    Deltas.enqueue(project.id, "a")
    settle()

    assert [%{covered_lines: 1}] = rows(project, "a")
    assert Deltas.files(project.id, "a") == nil
    assert Deltas.targets(project.id, "a") == nil
  end

  test "commits without a ref store their targets only", %{project: project, account: account} do
    measure(project, account, "loose", [file("Sources/A.swift", [1, 0], targets: ["App", "Kit"])])
    complete(project, "loose")
    settle()

    assert rows(project, "loose") == []
    assert Deltas.files(project.id, "loose") == nil
    assert Deltas.targets(project.id, "loose") == Commits.targets(project.id, "loose")
  end

  test "the backfill writes the complete commits a branch already had, oldest first", %{
    project: project,
    account: account
  } do
    linear(account, ~w(a b c))
    measure(project, account, "a", [file("Sources/A.swift", [1, 0, 0]), file("Sources/B.swift", [0, 0])])
    measure(project, account, "b", [file("Sources/A.swift", [1, 1, 0]), file("Sources/B.swift", [0, 0])])
    measure(project, account, "c", [file("Sources/A.swift", [1, 1, 0]), file("Sources/B.swift", [1, 0])])
    for sha <- ~w(a b c), do: complete(project, sha)
    Repo.delete_all(from(j in Oban.Job, where: j.worker == "Tuist.Tests.Coverage.Workers.DeltaWorker"))

    assert Deltas.backfill(project) == %{written: 3, unavailable: 0}
    assert [] = all_enqueued(worker: DeltaWorker)
    for sha <- ~w(a b c), do: assert_parity(project, sha)
    assert [%{path: "Sources/A.swift", base_sha: "a"}] = rows(project, "b")

    # Nothing changed, so a second pass rewrites nothing.
    assert Deltas.backfill(project) == %{written: 3, unavailable: 0}
    assert [%{path: "Sources/A.swift"}] = rows(project, "b")
  end

  test "the backfill re-queues the commits above what it wrote", %{project: project, account: account} do
    linear(account, ~w(a b c))

    measure(project, account, "a", [
      file("Sources/A.swift", [1, 0, 0]),
      file("Sources/B.swift", [0, 0]),
      file("Sources/Z.swift", [1])
    ])

    measure(project, account, "b", [
      file("Sources/A.swift", [1, 1, 0]),
      file("Sources/B.swift", [0, 0]),
      file("Sources/Z.swift", [0])
    ])

    measure(project, account, "c", [
      file("Sources/A.swift", [1, 1, 0]),
      file("Sources/B.swift", [1, 0]),
      file("Sources/Z.swift", [1])
    ])

    for sha <- ~w(a b c), do: complete(project, sha)
    Repo.delete_all(from(j in Oban.Job, where: j.worker == "Tuist.Tests.Coverage.Workers.DeltaWorker"))

    # c is written by a live job before the backfill writes what is below it,
    # and is not among the commits the backfill lists.
    Deltas.with_project_lock(project.id, fn -> Deltas.write(project, "a", cascade: false) end)
    Deltas.with_project_lock(project.id, fn -> Deltas.write(project, "c", cascade: false) end)
    old = DateTime.add(DateTime.utc_now(), -200, :day)

    Repo.update_all(from(c in CoverageCommit, where: c.project_id == ^project.id and c.git_commit_sha == "c"),
      set: [ran_at: old]
    )

    assert Deltas.backfill(project) == %{written: 2, unavailable: 0}
    assert Deltas.files(project.id, "c") != raw_files(project, "c")
    assert_enqueued(worker: DeltaWorker, args: %{project_id: project.id, git_commit_sha: "c"})
    Oban.drain_queue(queue: :coverage_deltas, with_scheduled: true, with_recursion: true, with_safety: false)

    assert_parity(project, "c")
  end
end
