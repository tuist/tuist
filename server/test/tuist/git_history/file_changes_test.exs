defmodule Tuist.GitHistory.FileChangesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.GitHistory.Commit
  alias Tuist.GitHistory.CommitFile
  alias Tuist.GitHistory.CommitListing
  alias Tuist.GitHistory.FileChange
  alias Tuist.GitHistory.FileChanges
  alias Tuist.GitHistory.Ref
  alias Tuist.GitHistory.Workers.FileChangesWorker
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @mode 0o100644
  @executable 0o100755

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    %{repository: CoverageFixtures.repository_id(account)}
  end

  defp commits(repository, commits) do
    commits =
      commits
      |> Enum.with_index()
      |> Enum.map(fn {{sha, parents}, index} -> CoverageFixtures.commit(sha, parents, index) end)

    GitHistory.record_commits(repository, "sha1", commits)
  end

  defp head(repository, branch, sha), do: GitHistory.record_branch_head(repository, branch, sha, "main")

  # A listing as `path => blob` or `path => {blob, mode}`.
  defp list(repository, sha, files, opts \\ []) do
    files =
      Enum.map(files, fn
        {path, {blob, mode}} -> %{path: path, git_blob_id: blob, mode: mode}
        {path, blob} -> %{path: path, git_blob_id: blob, mode: @mode}
      end)

    GitHistory.record_listing(repository, sha, files, Keyword.put_new(opts, :files_count, length(files)))
    settle()
  end

  defp settle, do: Oban.drain_queue(queue: :coverage_deltas, with_recursion: true, with_safety: false)

  defp rows(repository) do
    ClickHouseRepo.all(
      from(c in FileChange,
        hints: ["FINAL"],
        where: c.repository_id == ^repository and c.expires_at > fragment("now()"),
        order_by: [c.ref_id, c.position, c.path]
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  # The rows stored for the commit, as `path => blob`.
  defp changes(repository, sha),
    do: for(row <- rows(repository), row.sha == sha, into: %{}, do: {row.path, row.git_blob_id})

  # The commit's files as its rows and the ones below it read, resolved here
  # along its chain: `path => {blob, mode}`.
  defp files(repository, sha) do
    rows = rows(repository)

    repository
    |> place(sha)
    |> GitHistory.chain(:at)
    |> Enum.reverse()
    |> Enum.flat_map(fn %{ref_id: ref_id, hi: hi} ->
      rows |> Enum.filter(&(&1.ref_id == ref_id and &1.position <= hi)) |> Enum.sort_by(& &1.position)
    end)
    |> Enum.reduce(%{}, fn
      %{git_blob_id: ""} = row, files -> Map.delete(files, row.path)
      row, files -> Map.put(files, row.path, {row.git_blob_id, row.mode})
    end)
  end

  # Where the commit sits, on a detached ref too.
  defp place(repository, sha) do
    Repo.one(from(c in Commit, where: c.repository_id == ^repository and c.sha == ^sha, select: {c.ref_id, c.position}))
  end

  defp detached(repository),
    do: Repo.all(from(r in Ref, where: r.repository_id == ^repository and r.detached, order_by: r.id))

  defp with_mode(files), do: Map.new(files, fn {path, blob} -> {path, {blob, @mode}} end)

  defp listing(repository, sha), do: CoverageFixtures.listing(repository, sha)

  defp ref_id(repository, name), do: GitHistory.ref(repository, name).id

  test "the first listed commit writes every file, and a child the paths it changed", %{repository: repository} do
    commits(repository, [{"a", []}, {"b", ["a"]}])
    head(repository, "main", "b")

    list(repository, "a", %{"Sources/A.swift" => "a1", "Sources/B.swift" => "b1", "script.sh" => "s1"})

    assert changes(repository, "a") == %{"Sources/A.swift" => "a1", "Sources/B.swift" => "b1", "script.sh" => "s1"}

    list(repository, "b", %{
      "Sources/A.swift" => "a2",
      "Sources/C.swift" => "c1",
      "script.sh" => {"s1", @executable}
    })

    # A changed blob, a deleted path, an added one and a mode alone.
    assert changes(repository, "b") == %{
             "Sources/A.swift" => "a2",
             "Sources/B.swift" => "",
             "Sources/C.swift" => "c1",
             "script.sh" => "s1"
           }

    assert files(repository, "b") == %{
             "Sources/A.swift" => {"a2", @mode},
             "Sources/C.swift" => {"c1", @mode},
             "script.sh" => {"s1", @executable}
           }

    main = ref_id(repository, "main")

    assert %{changes_ref_id: ^main, changes_position: 2, changes_expires_at: expires_at, changes_count: 4} =
             listing(repository, "b")

    assert expires_at.year == 2100
    assert %{changes_count: 3} = listing(repository, "a")
    assert Enum.all?(rows(repository), &(&1.ref_id == main and &1.generation == &1.position))
  end

  test "a commit that changed nothing writes no row and is still marked", %{repository: repository} do
    commits(repository, [{"a", []}, {"b", ["a"]}])
    head(repository, "main", "b")

    list(repository, "a", %{"A.swift" => "a1"})
    list(repository, "b", %{"A.swift" => "a1"})

    assert changes(repository, "b") == %{}
    assert %{changes_position: 2, changes_count: 0} = listing(repository, "b")
    assert FileChanges.write(repository, "b") == :current
  end

  test "a commit listed after its child leaves both with the files of their listings", %{repository: repository} do
    commits(repository, [{"a", []}, {"b", ["a"]}, {"c", ["b"]}])
    head(repository, "main", "c")

    a = %{"Kept.swift" => "k1", "Reverted.swift" => "r1", "Changed.swift" => "x1"}
    # `b` changes two files and adds one; `c` puts one of them back and drops
    # the added one.
    b = %{"Kept.swift" => "k1", "Reverted.swift" => "r2", "Changed.swift" => "x2", "Added.swift" => "n1"}
    c = %{"Kept.swift" => "k1", "Reverted.swift" => "r1", "Changed.swift" => "x2"}

    list(repository, "a", a)
    list(repository, "c", c)
    assert changes(repository, "c") == %{"Changed.swift" => "x2"}
    assert %{changes_count: 1} = listing(repository, "c")

    list(repository, "b", b)

    assert changes(repository, "b") == %{"Reverted.swift" => "r2", "Changed.swift" => "x2", "Added.swift" => "n1"}
    assert files(repository, "b") == with_mode(b)
    assert files(repository, "c") == with_mode(c)

    # What `c` no longer reads from below it is now its own change: at least
    # the paths that differ between the two commits.
    assert changes(repository, "c") == %{"Reverted.swift" => "r1", "Changed.swift" => "x2", "Added.swift" => ""}
    assert %{changes_count: 3} = listing(repository, "c")
  end

  describe "a write that stopped before it marked the listing, tried again" do
    setup %{repository: repository} do
      commits(repository, [{"a", []}, {"b", ["a"]}, {"c", ["b"]}])
      head(repository, "main", "c")
      list(repository, "a", %{"Kept.swift" => "k1", "Reverted.swift" => "r1"})

      %{b: %{"Kept.swift" => "k1", "Reverted.swift" => "r2", "Added.swift" => "n1"}}
    end

    defp unmark(repository, sha) do
      Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha == ^sha),
        set: [changes_ref_id: nil, changes_position: nil, changes_expires_at: nil, changes_count: nil]
      )
    end

    test "leaves a child written since with its files", %{repository: repository, b: b} do
      c = Map.put(b, "New.swift", "x1")

      list(repository, "b", b)
      unmark(repository, "b")
      list(repository, "c", c)

      assert FileChanges.write(repository, "b") == :written
      assert files(repository, "b") == with_mode(b)
      assert files(repository, "c") == with_mode(c)
    end

    test "leaves a child written before it with its files", %{repository: repository, b: b} do
      c = %{"Kept.swift" => "k1", "Reverted.swift" => "r1"}

      list(repository, "c", c)
      list(repository, "b", b)
      unmark(repository, "b")

      assert FileChanges.write(repository, "b") == :written
      assert files(repository, "b") == with_mode(b)
      assert files(repository, "c") == with_mode(c)
    end
  end

  test "a moved commit whose listing does not add up keeps the rows it had", %{repository: repository} do
    commits(repository, [{"a", []}, {"f1", ["a"]}])
    head(repository, "main", "a")
    head(repository, "feature", "f1")

    f1 = %{"A.swift" => "a2", "B.swift" => "b1"}
    list(repository, "a", %{"A.swift" => "a1"})
    list(repository, "f1", f1)

    listing = from(l in CommitListing, where: l.repository_id == ^repository and l.sha == "f1")
    Repo.update_all(listing, set: [files_count: 99])
    GitHistory.advance_ref(repository, "main", nil, "f1")

    assert FileChanges.write(repository, "f1") == :unavailable
    assert changes(repository, "f1") == f1

    # Once the listing is gone the rows move with the commit.
    Repo.update_all(listing, set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -200, :day)])

    assert FileChanges.write(repository, "f1") == :moved
    assert files(repository, "f1") == with_mode(f1)
  end

  test "a truncated listing is never written, and the next commit compares with the one below it", %{
    repository: repository
  } do
    commits(repository, [{"a", []}, {"b", ["a"]}, {"c", ["b"]}])
    head(repository, "main", "c")

    list(repository, "a", %{"A.swift" => "a1", "B.swift" => "b1"})
    list(repository, "b", %{"A.swift" => "a2"}, truncated: true, files_count: 2)

    assert changes(repository, "b") == %{}
    assert %{changes_ref_id: nil} = listing(repository, "b")
    assert FileChanges.write(repository, "b") == :skipped

    list(repository, "c", %{"A.swift" => "a2", "B.swift" => "b1"})
    assert changes(repository, "c") == %{"A.swift" => "a2"}
    assert files(repository, "c") == with_mode(%{"A.swift" => "a2", "B.swift" => "b1"})
  end

  test "a listing whose files are not all there yet is left unwritten", %{repository: repository} do
    commits(repository, [{"a", []}])
    head(repository, "main", "a")

    GitHistory.record_listing(repository, "a", [%{path: "A.swift", git_blob_id: "a1"}], files_count: 2)

    assert FileChanges.write(repository, "a") == :unavailable
    assert rows(repository) == []
    assert %{changes_ref_id: nil} = listing(repository, "a")
  end

  describe "a write that cannot be done yet" do
    setup %{repository: repository} do
      commits(repository, [{"a", []}])
      head(repository, "main", "a")
      GitHistory.record_listing(repository, "a", [%{path: "A.swift", git_blob_id: "a1", mode: @mode}], files_count: 2)
      %{args: %{repository_id: repository, sha: "a"}}
    end

    test "comes back less and less often, however many times it ran", %{args: args} do
      assert {:snooze, 30} = perform_job(FileChangesWorker, args, attempt: 1)
      assert {:snooze, 60} = perform_job(FileChangesWorker, args, attempt: 2)
      assert {:snooze, 1_920} = perform_job(FileChangesWorker, args, attempt: 7)
      assert {:snooze, 3_600} = perform_job(FileChangesWorker, args, attempt: 8)
      assert {:snooze, 3_600} = perform_job(FileChangesWorker, args, attempt: 500)
    end

    test "is written once the listing's files are all there", %{repository: repository, args: args} do
      assert {:snooze, 3_600} = perform_job(FileChangesWorker, args, attempt: 40)

      GitHistory.record_listing(repository, "a", [%{path: "B.swift", git_blob_id: "b1", mode: @mode}], complete: false)

      assert :ok = perform_job(FileChangesWorker, args, attempt: 41)
      assert files(repository, "a") == with_mode(%{"A.swift" => "a1", "B.swift" => "b1"})
    end

    test "ends once the listing expired", %{repository: repository, args: args} do
      Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha == "a"),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -90, :day)]
      )

      assert :ok = perform_job(FileChangesWorker, args, attempt: 41)
      assert rows(repository) == []
    end
  end

  describe "enqueue_unwritten/0" do
    defp queued(repository) do
      [worker: FileChangesWorker]
      |> all_enqueued()
      |> Enum.filter(&(&1.args["repository_id"] == repository))
      |> Enum.map(& &1.args["sha"])
      |> Enum.sort()
    end

    # The jobs a listing or a move queued are gone, as after they failed
    # every attempt.
    defp lose_jobs, do: Repo.delete_all(Oban.Job)

    test "queues a commit on a ref whose listing is stored and not written", %{repository: repository} do
      commits(repository, [{"a", []}, {"b", ["a"]}, {"c", ["b"]}, {"t", ["c"]}])
      head(repository, "main", "t")
      list(repository, "a", %{"A.swift" => "a1"})

      one = [%{path: "A.swift", git_blob_id: "a2", mode: @mode}]
      GitHistory.record_listing(repository, "b", one, files_count: 1)
      # Nothing to write these from.
      GitHistory.record_listing(repository, "c", one, files_count: 1)
      expire(repository, ["c"])
      GitHistory.record_listing(repository, "t", one, files_count: 5, truncated: true)
      lose_jobs()

      assert FileChanges.enqueue_unwritten() == 1
      assert queued(repository) == ["b"]

      settle()
      assert changes(repository, "b") == %{"A.swift" => "a2"}
      lose_jobs()
      assert FileChanges.enqueue_unwritten() == 0
      assert queued(repository) == []
    end

    test "queues a commit no ref owns, which its write gives a detached ref", %{repository: repository} do
      commits(repository, [{"a", []}, {"m", ["a"]}])
      head(repository, "main", "a")
      list(repository, "a", %{"A.swift" => "a1"})
      GitHistory.record_listing(repository, "m", [%{path: "A.swift", git_blob_id: "a2", mode: @mode}], files_count: 1)
      lose_jobs()

      assert FileChanges.enqueue_unwritten() == 1
      assert queued(repository) == ["m"]

      settle()
      assert changes(repository, "m") == %{"A.swift" => "a2"}
      lose_jobs()
      assert FileChanges.enqueue_unwritten() == 0
    end

    test "queues a commit with no place again, until its listing expires", %{repository: repository} do
      commits(repository, [{"u", []}])
      GitHistory.record_listing(repository, "u", [%{path: "A.swift", git_blob_id: "a1", mode: @mode}], files_count: 1)
      settle()

      assert FileChanges.enqueue_unwritten() == 1
      settle()
      assert rows(repository) == []

      expire(repository, ["u"])
      assert FileChanges.enqueue_unwritten() == 0
    end

    test "queues a moved commit whose rows are still at the place it left", %{repository: repository} do
      commits(repository, [{"a", []}, {"f1", ["a"]}])
      head(repository, "main", "a")
      head(repository, "feature", "f1")
      list(repository, "a", %{"A.swift" => "a1"})
      list(repository, "f1", %{"A.swift" => "a2"})
      expire(repository, ["f1"])

      head(repository, "main", "f1")
      lose_jobs()

      FileChanges.enqueue_unwritten()
      assert queued(repository) == ["f1"]

      settle()
      main = ref_id(repository, "main")
      assert %{changes_ref_id: ^main, changes_position: 2} = listing(repository, "f1")
      assert files(repository, "f1") == with_mode(%{"A.swift" => "a2"})
    end
  end

  test "a listing read in part records none of the files it lacks as gone", %{repository: repository} do
    commits(repository, [{"a", []}, {"b", ["a"]}])
    head(repository, "main", "b")

    a = %{"A.swift" => "a1", "B.swift" => "b1", "C.swift" => "c1"}
    list(repository, "a", a)

    GitHistory.record_listing(repository, "b", [%{path: "A.swift", git_blob_id: "a2", mode: @mode}], files_count: 3)

    assert FileChanges.write(repository, "b") == :unavailable
    assert changes(repository, "b") == %{}
    assert %{changes_ref_id: nil} = listing(repository, "b")
    assert files(repository, "a") == with_mode(a)
  end

  test "a commit listed before a ref owns it is written once it is placed", %{repository: repository} do
    commits(repository, [{"a", []}, {"b", ["a"]}])

    list(repository, "a", %{"A.swift" => "a1"})
    list(repository, "b", %{"A.swift" => "a2"})

    assert rows(repository) == []
    assert FileChanges.write(repository, "b") == :pending

    head(repository, "main", "b")
    settle()

    assert changes(repository, "a") == %{"A.swift" => "a1"}
    assert changes(repository, "b") == %{"A.swift" => "a2"}
  end

  test "a branch reads the default branch up to its fork, and its rows expire together", %{repository: repository} do
    commits(repository, [{"a", []}, {"b", ["a"]}, {"f1", ["b"]}, {"f2", ["f1"]}, {"c", ["b"]}])
    head(repository, "main", "b")
    head(repository, "feature", "f2")

    list(repository, "a", %{"A.swift" => "a1", "B.swift" => "b1"})
    list(repository, "b", %{"A.swift" => "a2", "B.swift" => "b1"})
    list(repository, "f1", %{"A.swift" => "a2", "B.swift" => "b2"})

    assert changes(repository, "f1") == %{"B.swift" => "b2"}

    # The default branch moves on after the fork.
    head(repository, "main", "c")
    list(repository, "c", %{"A.swift" => "a3", "B.swift" => "b1"})
    list(repository, "f2", %{"A.swift" => "a2", "B.swift" => "b2", "F.swift" => "f1"})

    assert changes(repository, "f2") == %{"F.swift" => "f1"}
    assert files(repository, "f2") == with_mode(%{"A.swift" => "a2", "B.swift" => "b2", "F.swift" => "f1"})
    assert files(repository, "c") == with_mode(%{"A.swift" => "a3", "B.swift" => "b1"})

    feature = ref_id(repository, "feature")
    %{changes_ref_id: ^feature, changes_expires_at: first} = listing(repository, "f1")
    assert_in_delta DateTime.diff(first, DateTime.utc_now(), :day), 90, 1

    # A later commit of the branch reads the first one's rows, so it cannot
    # outlive them.
    Repo.update_all(from(l in CommitListing, where: l.sha == "f1"),
      set: [changes_expires_at: DateTime.add(first, -30, :day)]
    )

    list(repository, "f2", %{"A.swift" => "a2", "B.swift" => "b2", "F.swift" => "f1"})
    assert FileChanges.write(repository, "f2") == :current

    commits(repository, [{"f3", ["f2"]}])
    head(repository, "feature", "f3")
    list(repository, "f3", %{"A.swift" => "a2", "B.swift" => "b2"})
    assert listing(repository, "f3").changes_expires_at == DateTime.add(first, -30, :day)
    assert listing(repository, "c").changes_expires_at.year == 2100
  end

  test "a commit listed below a fork leaves the branch with the files of its listings", %{repository: repository} do
    commits(repository, [{"a", []}, {"b", ["a"]}, {"f1", ["b"]}, {"p1", ["f1"]}])
    head(repository, "main", "b")
    head(repository, "feature", "f1")
    GitHistory.advance_ref(repository, "pull/1", "feature", "p1")

    list(repository, "a", %{"A.swift" => "a1", "B.swift" => "b1"})
    list(repository, "p1", %{"A.swift" => "a1", "B.swift" => "b2"})
    assert changes(repository, "p1") == %{"B.swift" => "b2"}

    # `b` changed a file that the pull request, two refs up with nothing
    # listed in between, has back as it was.
    list(repository, "b", %{"A.swift" => "a2", "B.swift" => "b1"})

    assert files(repository, "b") == with_mode(%{"A.swift" => "a2", "B.swift" => "b1"})
    assert files(repository, "p1") == with_mode(%{"A.swift" => "a1", "B.swift" => "b2"})
    assert changes(repository, "p1") == %{"A.swift" => "a1", "B.swift" => "b2"}
  end

  test "a commit listed below more commits than one statement names leaves each with its files", %{
    repository: repository
  } do
    forks = for n <- 1..210, do: "f#{n}"
    commits(repository, [{"r", []}, {"a", ["r"]}, {"b", ["a"]} | Enum.map(forks, &{&1, ["a"]})])
    head(repository, "main", "b")
    for sha <- forks, do: head(repository, "pull/#{sha}", sha)

    list(repository, "r", %{"A.swift" => "a0", "B.swift" => "b0"})
    list(repository, "b", %{"A.swift" => "a0", "B.swift" => "b1"})

    # Each fork written with the one file it added, without a write per fork.
    expires_at = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 90, :day)

    places =
      Repo.all(
        from(c in Commit,
          where: c.repository_id == ^repository and c.sha in ^forks,
          select: %{sha: c.sha, ref_id: c.ref_id, position: c.position, generation: c.generation}
        )
      )

    Repo.insert_all(
      CommitListing,
      for place <- places do
        %{
          repository_id: repository,
          sha: place.sha,
          files_count: 3,
          truncated: false,
          inserted_at: DateTime.utc_now(:second),
          changes_ref_id: place.ref_id,
          changes_position: place.position,
          changes_expires_at: expires_at,
          changes_count: 1
        }
      end
    )

    IngestRepo.insert_all(
      FileChange,
      for place <- places do
        Map.merge(place, %{
          repository_id: repository,
          path: "F.swift",
          git_blob_id: place.sha,
          mode: @mode,
          expires_at: DateTime.to_naive(expires_at),
          row_version: System.os_time(:microsecond),
          is_deleted: 0
        })
      end
    )

    list(repository, "a", %{"A.swift" => "a1", "B.swift" => "b0"})

    held = for row <- rows(repository), row.path == "A.swift", into: %{}, do: {row.sha, row.git_blob_id}
    assert held == Map.put(Map.new(["r", "b" | forks], &{&1, "a0"}), "a", "a1")
    assert files(repository, "f210") == with_mode(%{"A.swift" => "a0", "B.swift" => "b0", "F.swift" => "f210"})

    counts = from(l in CommitListing, where: l.repository_id == ^repository and l.sha in ^forks, select: l.changes_count)
    assert counts |> Repo.all() |> Enum.uniq() == [2]
  end

  test "a branch that keeps receiving commits keeps its rows", %{repository: repository} do
    commits(repository, [{"a", []}, {"f1", ["a"]}, {"f2", ["f1"]}, {"f3", ["f2"]}])
    head(repository, "main", "a")
    head(repository, "feature", "f2")

    list(repository, "a", %{"A.swift" => "a1"})
    list(repository, "f1", %{"A.swift" => "a2"})
    list(repository, "f2", %{"A.swift" => "a2"})

    # Most of the branch's retention is gone.
    soon = DateTime.utc_now() |> DateTime.add(10, :day) |> DateTime.truncate(:second)

    Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha in ["f1", "f2"]),
      set: [changes_expires_at: soon]
    )

    head(repository, "feature", "f3")
    list(repository, "f3", %{"A.swift" => "a2", "B.swift" => "b1"})

    for sha <- ["f1", "f2", "f3"] do
      assert_in_delta DateTime.diff(listing(repository, sha).changes_expires_at, DateTime.utc_now(), :day), 90, 1
    end

    feature = ref_id(repository, "feature")

    for row <- rows(repository) do
      if row.ref_id == feature,
        do: assert_in_delta(NaiveDateTime.diff(row.expires_at, NaiveDateTime.utc_now(), :day), 90, 1),
        else: assert(row.expires_at.year == 2100)
    end

    assert changes(repository, "f1") == %{"A.swift" => "a2"}
    assert files(repository, "f3") == with_mode(%{"A.swift" => "a2", "B.swift" => "b1"})
    assert %{changes_count: 1} = listing(repository, "f1")
  end

  test "a fast-forward moves a branch's rows onto the default branch", %{repository: repository} do
    commits(repository, [{"a", []}, {"f1", ["a"]}, {"f2", ["f1"]}])
    head(repository, "main", "a")
    head(repository, "feature", "f2")

    list(repository, "a", %{"A.swift" => "a1"})
    list(repository, "f1", %{"A.swift" => "a2"})
    list(repository, "f2", %{"A.swift" => "a2", "B.swift" => "b1"})

    feature = ref_id(repository, "feature")
    main = ref_id(repository, "main")
    assert %{changes_ref_id: ^feature} = listing(repository, "f2")

    head(repository, "main", "f2")
    settle()

    assert %{changes_ref_id: ^main, changes_position: 2, changes_expires_at: kept} = listing(repository, "f1")
    assert %{changes_ref_id: ^main, changes_position: 3} = listing(repository, "f2")
    assert kept.year == 2100
    assert Enum.all?(rows(repository), &(&1.ref_id == main))
    assert changes(repository, "f1") == %{"A.swift" => "a2"}
    assert changes(repository, "f2") == %{"B.swift" => "b1"}
    assert files(repository, "f2") == with_mode(%{"A.swift" => "a2", "B.swift" => "b1"})
  end

  test "a moved commit whose listing expired keeps the rows it had", %{repository: repository} do
    commits(repository, [{"a", []}, {"f1", ["a"]}])
    head(repository, "main", "a")
    head(repository, "feature", "f1")

    list(repository, "a", %{"A.swift" => "a1"})
    list(repository, "f1", %{"A.swift" => "a2", "B.swift" => "b1"})

    Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha == "f1"),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -90, :day)]
    )

    head(repository, "main", "f1")
    assert FileChanges.write(repository, "f1") == :moved

    main = ref_id(repository, "main")
    assert %{changes_ref_id: ^main, changes_position: 2, changes_count: 2} = listing(repository, "f1")
    assert Enum.all?(rows(repository), &(&1.ref_id == main))
    assert files(repository, "f1") == with_mode(%{"A.swift" => "a2", "B.swift" => "b1"})
  end

  describe "commits that move together after their listings expired" do
    setup %{repository: repository} do
      commits(repository, [{"a", []}, {"f1", ["a"]}, {"f2", ["f1"]}])
      head(repository, "main", "a")
      head(repository, "feature", "f2")

      list(repository, "a", %{"A.swift" => "a1", "B.swift" => "b1"})
      list(repository, "f1", %{"A.swift" => "a2", "B.swift" => "b1"})
      list(repository, "f2", %{"A.swift" => "a2", "B.swift" => "b2"})

      Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha in ["f1", "f2"]),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -90, :day)]
      )

      head(repository, "main", "f2")
      :ok
    end

    test "keep their files when the child's write runs first", %{repository: repository} do
      # It comes back after its parent's.
      assert FileChanges.write(repository, "f2") == :deferred
      assert :ok = perform_job(FileChangesWorker, %{repository_id: repository, sha: "f2"})
      assert %{changes_ref_id: feature} = listing(repository, "f2")
      assert feature == ref_id(repository, "feature")

      Oban.drain_queue(queue: :coverage_deltas, with_scheduled: true, with_recursion: true, with_safety: false)

      main = ref_id(repository, "main")
      assert %{changes_ref_id: ^main, changes_position: 3} = listing(repository, "f2")
      assert files(repository, "f1") == with_mode(%{"A.swift" => "a2", "B.swift" => "b1"})
      assert files(repository, "f2") == with_mode(%{"A.swift" => "a2", "B.swift" => "b2"})
      assert changes(repository, "f2") == %{"B.swift" => "b2"}
    end

    test "a child is not copied above a parent that is not going to move", %{repository: repository} do
      # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
      Repo.delete_all(Oban.Job)

      assert FileChanges.write(repository, "f2") == :skipped
      assert listing(repository, "f2").changes_ref_id == ref_id(repository, "feature")
    end
  end

  test "renewing a ref never takes it past a ref it forks from", %{repository: repository} do
    commits(repository, [{"a", []}, {"d1", ["a"]}, {"p1", ["d1"]}, {"p2", ["p1"]}])
    head(repository, "main", "a")
    head(repository, "development", "d1")
    GitHistory.advance_ref(repository, "pull/1", "development", "p1")

    list(repository, "a", %{"A.swift" => "a1"})
    list(repository, "d1", %{"A.swift" => "a2"})
    list(repository, "p1", %{"A.swift" => "a3"})

    expires_in = fn days -> DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.truncate(:second) end

    expire = fn sha, at ->
      Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha == ^sha),
        set: [changes_expires_at: at]
      )
    end

    development = expires_in.(60)
    expire.("d1", development)
    expire.("p1", expires_in.(10))

    GitHistory.advance_ref(repository, "pull/1", "development", "p2")
    list(repository, "p2", %{"A.swift" => "a4"})

    assert listing(repository, "p1").changes_expires_at == development
    assert listing(repository, "p2").changes_expires_at == development
    assert listing(repository, "d1").changes_expires_at == development
  end

  test "a rewritten branch leaves the commits it dropped their files, on a detached ref", %{repository: repository} do
    commits(repository, [{"a", []}, {"f1", ["a"]}, {"g1", ["a"]}])
    head(repository, "main", "a")
    head(repository, "feature", "f1")

    list(repository, "a", %{"A.swift" => "a1"})
    list(repository, "f1", %{"A.swift" => "a2", "F.swift" => "f1"})

    # A force-push: `g1` takes the place `f1` held.
    head(repository, "feature", "g1")
    list(repository, "g1", %{"A.swift" => "a1", "G.swift" => "g1"})

    main = ref_id(repository, "main")
    assert [%{id: ref, parent_ref_id: ^main, fork_position: 1}] = detached(repository)
    assert %{changes_ref_id: ^ref, changes_position: 2, changes_count: 2} = listing(repository, "f1")
    assert changes(repository, "f1") == %{"A.swift" => "a2", "F.swift" => "f1"}
    assert files(repository, "f1") == with_mode(%{"A.swift" => "a2", "F.swift" => "f1"})
    assert changes(repository, "g1") == %{"G.swift" => "g1"}
    assert files(repository, "g1") == with_mode(%{"A.swift" => "a1", "G.swift" => "g1"})
  end

  test "rebuilding the refs leaves written commits where they are", %{repository: repository} do
    commits(repository, [{"a", []}, {"b", ["a"]}])
    head(repository, "main", "b")
    list(repository, "a", %{"A.swift" => "a1"})
    list(repository, "b", %{"A.swift" => "a2"})
    before = rows(repository)

    GitHistory.rebuild_refs(repository)

    assert settle().success == 0
    assert rows(repository) == before
  end

  describe "commits a rebuild of the refs moves up their own ref" do
    # `late` changes two files and adds another; its child `c` has them back
    # as they were, so none is among the paths `c` changed from `b`. `c` and
    # `d` both change a file `e` leaves as `d` has it, and `d` one `late`
    # changes: `e` reads them through rows that lie between it and the
    # places below.
    @shifted %{
      "a" => %{"A.swift" => "a1", "B.swift" => "b1", "C.swift" => "c1"},
      "b" => %{"A.swift" => "a1", "B.swift" => "b2", "C.swift" => "c1"},
      "late" => %{"A.swift" => "a2", "B.swift" => "b9", "C.swift" => "c1", "Late.swift" => "l1"},
      "c" => %{"A.swift" => "a1", "B.swift" => "b2", "C.swift" => "c2"},
      "d" => %{"A.swift" => "a1", "B.swift" => "b3", "C.swift" => "c3", "D.swift" => "d1"},
      "e" => %{"A.swift" => "a3", "B.swift" => "b3", "C.swift" => "c3"},
      "p1" => %{"A.swift" => "a1", "B.swift" => "b2", "C.swift" => "c2", "P.swift" => "p1"}
    }

    @earlier %{"A.swift" => "a1", "B.swift" => "b8", "C.swift" => "c8", "Earlier.swift" => "e1"}

    # main: a, b, then c, d, e above a parent of c that is not stored yet.
    # pull/1 forks at c: p1.
    setup %{repository: repository} do
      commits(repository, [{"a", []}, {"b", ["a"]}])
      head(repository, "main", "b")
      commits(repository, [{"c", ["late"]}, {"d", ["c"]}, {"e", ["d"]}, {"p1", ["c"]}])
      head(repository, "main", "e")
      GitHistory.advance_ref(repository, "pull/1", "main", "p1")

      for sha <- ["a", "b", "c", "d", "e", "p1"], do: list(repository, sha, @shifted[sha])
      :ok
    end

    # `c`'s parent is stored and the refs are placed again: main is now
    # a, b, late, c, d, e.
    defp rebuild_through(repository, late \\ [{"late", ["b"]}]) do
      commits(repository, late)
      GitHistory.rebuild_refs(repository)
    end

    defp expire(repository, shas) do
      Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha in ^shas),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -90, :day)]
      )
    end

    # Each of `listings`' commits is written where it sits and reads the files
    # of its listing, the `unknown` ones have no rows left, and no place
    # holds a row of a commit that is not there.
    defp assert_settled(repository, listings, unknown \\ []) do
      for {sha, files} <- Map.drop(listings, unknown) do
        assert {sha, FileChanges.current(repository, sha)} == {sha, GitHistory.position(repository, sha)}
        assert {sha, files(repository, sha)} == {sha, with_mode(files)}
        assert {sha, Map.new(GitHistory.commit_files(repository, sha), &{&1.path, &1.git_blob_id})} == {sha, files}
      end

      for sha <- unknown do
        assert {sha, FileChanges.current(repository, sha), changes(repository, sha)} == {sha, nil, %{}}
        assert %{changes_ref_id: nil, changes_position: nil} = listing(repository, sha)
        refute GitHistory.listing_complete?(repository, sha)
      end

      for row <- rows(repository) do
        assert {row.sha, GitHistory.position(repository, row.sha)} == {row.sha, {row.ref_id, row.position}}
      end
    end

    test "keep their files while their listings are stored", %{repository: repository} do
      main = ref_id(repository, "main")
      assert GitHistory.position(repository, "c") == {main, 3}
      assert changes(repository, "c") == %{"C.swift" => "c2"}

      rebuild_through(repository)
      settle()

      assert GitHistory.position(repository, "late") == {main, 3}
      assert GitHistory.position(repository, "c") == {main, 4}
      assert GitHistory.position(repository, "e") == {main, 6}
      assert GitHistory.position(repository, "p1") == {ref_id(repository, "pull/1"), 5}
      assert_settled(repository, Map.delete(@shifted, "late"))

      list(repository, "late", @shifted["late"])

      assert_settled(repository, @shifted)
      # What `c` read from `b` until `late` was written below it.
      assert changes(repository, "c") == %{"A.swift" => "a1", "B.swift" => "b2", "C.swift" => "c2", "Late.swift" => ""}
    end

    # Their rows would be copied up the ref, each onto the rows of the next.
    test "are left without files once their listings expired, not with another commit's", %{repository: repository} do
      expire(repository, ["c", "d", "e", "p1"])

      rebuild_through(repository)
      settle()
      assert_settled(repository, Map.delete(@shifted, "late"), ["c", "d", "e", "p1"])

      list(repository, "late", @shifted["late"])
      assert_settled(repository, @shifted, ["c", "d", "e", "p1"])

      # A commit listed again is written again.
      Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha == "d"),
        set: [inserted_at: DateTime.utc_now(:second)]
      )

      assert FileChanges.write(repository, "d") == :written
      assert_settled(repository, @shifted, ["c", "e", "p1"])
    end

    test "keep the files of their listings among others whose listings expired", %{repository: repository} do
      expire(repository, ["d", "p1"])
      list(repository, "late", @shifted["late"])

      rebuild_through(repository)
      settle()

      assert_settled(repository, @shifted, ["d", "p1"])
    end

    # Written above the others first, `e` reads the rows `c` and `d` left at
    # their old places until those go.
    for order <- [~w(e c d p1 late), ~w(e late c p1 d), ~w(late e c p1 d)], expired <- [[], ["d"]] do
      test "settle the same written as #{Enum.join(order, ", ")}, #{length(expired)} listings expired", %{
        repository: repository
      } do
        expire(repository, unquote(expired))
        list(repository, "late", @shifted["late"])
        rebuild_through(repository)

        queued = Map.new(all_enqueued(worker: FileChangesWorker), &{&1.args["sha"], &1.args})
        assert queued |> Map.keys() |> Enum.sort() == ~w(c d e late p1)
        for sha <- unquote(order), do: assert(:ok = perform_job(FileChangesWorker, queued[sha]))

        assert_settled(repository, @shifted, unquote(expired))
      end
    end

    for expired <- [["c", "d", "e", "p1"], ["d", "p1"]] do
      test "settle the same two positions up, #{length(expired)} listings expired", %{repository: repository} do
        expire(repository, unquote(expired))
        list(repository, "earlier", @earlier)
        list(repository, "late", @shifted["late"])

        rebuild_through(repository, [{"earlier", ["b"]}, {"late", ["earlier"]}])
        settle()

        assert GitHistory.position(repository, "c") == {ref_id(repository, "main"), 5}
        assert_settled(repository, Map.put(@shifted, "earlier", @earlier), unquote(expired))
      end
    end
  end

  describe "a commit no branch or pull request owns" do
    @b %{"A.swift" => "a2", "B.swift" => "b1"}
    @m %{"A.swift" => "a2", "F.swift" => "f1"}

    # `m` merges a branch's `f` into the default branch's `b`, as the commit
    # a pull request's run checks out does.
    setup %{repository: repository} do
      commits(repository, [{"a", []}, {"b", ["a"]}, {"f", ["b"]}, {"m", ["b", "f"]}])
      head(repository, "main", "b")
      list(repository, "a", %{"A.swift" => "a1", "B.swift" => "b1"})
      %{main: ref_id(repository, "main")}
    end

    test "is written on a detached ref that forks at its first parent", %{repository: repository, main: main} do
      list(repository, "b", @b)
      list(repository, "m", @m)

      assert [%{id: ref, name: "detached:m", parent_ref_id: ^main, fork_position: 2, head_sha: "m"}] =
               detached(repository)

      assert place(repository, "m") == {ref, 3}
      assert changes(repository, "m") == %{"B.swift" => "", "F.swift" => "f1"}
      assert files(repository, "m") == with_mode(@m)
      assert FileChanges.current(repository, "m") == {ref, 3}
      assert FileChanges.write(repository, "m") == :current

      # It forks from a ref that is kept, and expires on its own.
      assert %{changes_ref_id: ^ref, changes_position: 3, changes_expires_at: expires_at} = listing(repository, "m")
      assert_in_delta DateTime.diff(expires_at, DateTime.utc_now(), :day), 90, 1

      # The place is the file changes' alone.
      assert GitHistory.position(repository, "m") == nil

      assert [%{sha: "m", ref_id: nil, position: nil}, %{sha: "b", ref_id: ^main, position: 2}] =
               GitHistory.first_parents_to_segment(repository, "m")
    end

    test "keeps the files of its listing when its first parent is written after it", %{repository: repository} do
      list(repository, "m", @m)
      assert changes(repository, "m") == %{"A.swift" => "a2", "B.swift" => "", "F.swift" => "f1"}

      b = %{"A.swift" => "a3", "B.swift" => "b1", "C.swift" => "c1"}
      list(repository, "b", b)

      assert files(repository, "b") == with_mode(b)
      assert files(repository, "m") == with_mode(@m)
    end

    test "takes the unowned commits below it along, written there once listed", %{repository: repository, main: main} do
      commits(repository, [{"x", ["b"]}, {"y", ["x"]}])
      x = %{"A.swift" => "a1", "B.swift" => "b1", "X.swift" => "x1"}
      y = %{"A.swift" => "a1", "B.swift" => "b1", "X.swift" => "x2", "Y.swift" => "y1"}

      list(repository, "y", y)
      assert [%{id: ref, name: "detached:y", parent_ref_id: ^main, fork_position: 2}] = detached(repository)
      assert place(repository, "x") == {ref, 3}
      assert place(repository, "y") == {ref, 4}

      list(repository, "x", x)
      assert [%{id: ^ref}] = detached(repository)
      assert %{changes_ref_id: ^ref, changes_position: 3} = listing(repository, "x")
      assert files(repository, "x") == with_mode(x)
      assert files(repository, "y") == with_mode(y)
    end

    test "forks from the detached ref that holds its first parent, and a branch takes both over", %{
      repository: repository,
      main: main
    } do
      commits(repository, [{"x", ["b"]}, {"y", ["x"]}])
      x = %{"A.swift" => "a1", "B.swift" => "b1", "X.swift" => "x1"}
      y = %{"A.swift" => "a1", "B.swift" => "b1", "X.swift" => "x2", "Y.swift" => "y1"}

      list(repository, "x", x)
      list(repository, "y", y)

      assert [%{id: below, parent_ref_id: ^main, fork_position: 2}, %{id: above} = fork] = detached(repository)
      assert %{parent_ref_id: ^below, fork_position: 3} = fork

      assert place(repository, "y") == {above, 4}
      assert changes(repository, "y") == %{"X.swift" => "x2", "Y.swift" => "y1"}
      assert files(repository, "y") == with_mode(y)

      head(repository, "feature", "y")
      settle()

      feature = ref_id(repository, "feature")
      assert detached(repository) == []
      assert %{changes_ref_id: ^feature, changes_position: 3} = listing(repository, "x")
      assert %{changes_ref_id: ^feature, changes_position: 4} = listing(repository, "y")
      assert Enum.all?(rows(repository), &(&1.ref_id in [main, feature]))
      assert files(repository, "x") == with_mode(x)
      assert files(repository, "y") == with_mode(y)
    end

    test "forks from a branch that itself forks, as a stacked pull request's merge commit does", %{
      repository: repository,
      main: main
    } do
      # `f` is the first pull request's branch; `s` merges the second one's
      # `g` into it.
      commits(repository, [{"g", ["f"]}, {"s", ["f", "g"]}])
      head(repository, "one", "f")
      one = ref_id(repository, "one")
      f = %{"A.swift" => "a2", "B.swift" => "b1", "F.swift" => "f1"}
      s = %{"A.swift" => "a2", "B.swift" => "b1", "F.swift" => "f1", "G.swift" => "g1"}

      list(repository, "s", s)
      assert [%{id: ref, parent_ref_id: ^one, fork_position: 3}] = detached(repository)
      assert %{parent_ref_id: ^main, fork_position: 2} = Repo.get(Ref, one)
      assert place(repository, "s") == {ref, 4}
      assert files(repository, "s") == with_mode(s)

      # Written below it afterwards, two forks down and then one.
      list(repository, "b", @b)
      list(repository, "f", f)

      assert changes(repository, "f") == %{"F.swift" => "f1"}
      assert files(repository, "b") == with_mode(@b)
      assert files(repository, "f") == with_mode(f)
      assert files(repository, "s") == with_mode(s)
      assert repository |> GitHistory.commit_files("s") |> Map.new(&{&1.path, &1.git_blob_id}) == s
    end

    test "moves to a detached ref when its branch moves on, also once its listing expired", %{
      repository: repository,
      main: main
    } do
      head(repository, "feature", "m")
      list(repository, "b", @b)
      list(repository, "m", @m)
      feature = ref_id(repository, "feature")
      assert %{changes_ref_id: ^feature, changes_position: 3} = listing(repository, "m")

      Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha == "m"),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -90, :day)]
      )

      # The pull request's next run checks out a new merge commit.
      commits(repository, [{"c", ["b"]}, {"m2", ["c", "f"]}])
      head(repository, "main", "c")
      head(repository, "feature", "m2")
      assert place(repository, "m") == {nil, nil}

      assert FileChanges.write(repository, "m") == :moved
      assert [%{id: ref, parent_ref_id: ^main, fork_position: 2}] = detached(repository)
      assert %{changes_ref_id: ^ref, changes_position: 3, changes_count: 2} = listing(repository, "m")
      assert files(repository, "m") == with_mode(@m)
    end

    test "is placed again when the branch it forks from is rewritten", %{repository: repository, main: main} do
      commits(repository, [{"f2", ["f"]}, {"x", ["f2"]}, {"g", ["b"]}])
      head(repository, "feature", "f2")
      feature = ref_id(repository, "feature")
      f = %{"A.swift" => "a1", "B.swift" => "b1", "F.swift" => "f1"}
      x = %{"A.swift" => "a1", "B.swift" => "b1", "F.swift" => "f2", "X.swift" => "x1"}

      list(repository, "f", f)
      list(repository, "x", x)
      assert [%{parent_ref_id: ^feature, fork_position: 4}] = detached(repository)

      # A force-push: the commits `x` was above are the branch's no more.
      head(repository, "feature", "g")
      settle()

      # The newest is placed first and takes the others along: one ref.
      assert [%{id: ref, name: "detached:x", parent_ref_id: ^main, fork_position: 2}] = detached(repository)
      assert Enum.map(~w(f f2 x), &place(repository, &1)) == [{ref, 3}, {ref, 4}, {ref, 5}]
      assert Enum.all?(rows(repository), &(&1.ref_id in [main, ref]))
      assert files(repository, "f") == with_mode(f)
      assert files(repository, "x") == with_mode(x)
    end

    test "is placed again after the refs are rebuilt", %{repository: repository, main: main} do
      list(repository, "b", @b)
      list(repository, "m", @m)
      assert [%{id: old}] = detached(repository)

      GitHistory.rebuild_refs(repository)
      assert detached(repository) == []
      settle()

      assert [%{id: ref, parent_ref_id: ^main, fork_position: 2}] = detached(repository)
      assert ref != old
      assert Enum.all?(rows(repository), &(&1.ref_id in [main, ref]))
      assert files(repository, "b") == with_mode(@b)
      assert files(repository, "m") == with_mode(@m)
    end

    test "loses its ref once its file changes expired", %{repository: repository} do
      list(repository, "m", @m)
      assert [%{id: ref}] = detached(repository)
      aged = fn days -> DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second) end

      # A ref just made may still be waiting for its write.
      Repo.update_all(from(l in CommitListing, where: l.sha == "m"), set: [changes_expires_at: aged.(1)])
      GitHistory.prune(repository, 365)
      assert [%{id: ^ref}] = detached(repository)

      Repo.update_all(from(l in CommitListing, where: l.sha == "m"), set: [changes_expires_at: aged.(-1)])
      Repo.update_all(from(r in Ref, where: r.id == ^ref), set: [updated_at: aged.(2)])
      GitHistory.prune(repository, 365)
      assert [%{id: ^ref}] = detached(repository)

      Repo.update_all(from(l in CommitListing, where: l.sha == "m"), set: [changes_expires_at: aged.(1)])
      GitHistory.prune(repository, 365)
      assert detached(repository) == []
      assert place(repository, "m") == {nil, nil}
    end

    test "has no place while its first parents reach no commit a ref owns", %{repository: repository} do
      commits(repository, [{"p", []}, {"q", ["p"]}])
      list(repository, "q", %{"Q.swift" => "q1"})

      assert FileChanges.write(repository, "q") == :pending
      assert detached(repository) == []
      assert place(repository, "q") == {nil, nil}
    end
  end

  describe "a pull request's superseded merge commit, read once its listing is gone" do
    # What expiry does to a listing: its rows go, and its marker is older
    # than the file retention.
    defp expire_listing(repository, sha) do
      IngestRepo.query!(
        "ALTER TABLE git_commit_files DELETE WHERE repository_id = {repository_id:Int64} AND sha = {sha:String} " <>
          "SETTINGS mutations_sync = 2",
        %{repository_id: repository, sha: sha}
      )

      Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha == ^sha),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -365, :day)]
      )
    end

    # A 500-file tree; the pull request modifies 20 files, deletes 5 and
    # adds 7; its next merge commit is over a base that moved.
    setup do
      a = Map.new(1..500, &{"Sources/Module#{rem(&1, 25)}/File#{&1}.swift", "a#{&1}"})
      b = a |> Map.put("Sources/Module1/File1.swift", "b1") |> Map.put("Package.resolved", "pins1")

      m1 =
        b
        |> Map.merge(Map.new(100..119, &{"Sources/Module#{rem(&1, 25)}/File#{&1}.swift", "pr#{&1}"}))
        |> Map.drop(Enum.map(200..204, &"Sources/Module#{rem(&1, 25)}/File#{&1}.swift"))
        |> Map.merge(Map.new(1..7, &{"Sources/Feature/New#{&1}.swift", "new#{&1}"}))

      c = Map.put(b, "Sources/Module2/File2.swift", "c2")
      m2 = m1 |> Map.put("Sources/Module2/File2.swift", "c2") |> Map.put("Sources/Feature/New1.swift", "new1b")
      %{trees: %{a: a, b: b, m1: m1, c: c, m2: m2}}
    end

    for order <- [:superseded_then_expired, :expired_then_superseded] do
      test "keeps the files it was listed with (#{order})", %{repository: repository, trees: trees} do
        commits(repository, [{"a", []}, {"b", ["a"]}, {"f", ["b"]}, {"m1", ["b", "f"]}])
        head(repository, "main", "b")
        # A pull request's run reports the merge commit as its branch's head.
        head(repository, "feature", "m1")
        list(repository, "a", trees.a)
        list(repository, "b", trees.b)
        list(repository, "m1", trees.m1)

        # The next push: the base moved, so the run checks out a new merge commit.
        supersede = fn ->
          commits(repository, [{"c", ["b"]}, {"m2", ["c", "f"]}])
          head(repository, "main", "c")
          head(repository, "feature", "m2")
          list(repository, "c", trees.c)
          list(repository, "m2", trees.m2)
        end

        if unquote(order) == :superseded_then_expired do
          supersede.()
          expire_listing(repository, "m1")
        else
          expire_listing(repository, "m1")
          supersede.()
        end

        assert ClickHouseRepo.aggregate(
                 from(f in CommitFile, where: f.repository_id == ^repository and f.sha == "m1"),
                 :count
               ) == 0

        # Only the paths the pull request changed are stored for it.
        assert map_size(changes(repository, "m1")) == 32
        assert GitHistory.listing_complete?(repository, "m1")
        assert repository |> GitHistory.commit_files("m1") |> Map.new(&{&1.path, &1.git_blob_id}) == trees.m1

        # A modified path, an added one and a deleted one.
        assert GitHistory.blobs_at(repository, "m1", [
                 "Sources/Module0/File100.swift",
                 "Sources/Feature/New3.swift",
                 "Sources/Module0/File200.swift"
               ]) == %{"Sources/Module0/File100.swift" => "pr100", "Sources/Feature/New3.swift" => "new3"}

        assert repository |> GitHistory.changed_files("m1", "m2") |> Enum.map(& &1.path) ==
                 ["Sources/Feature/New1.swift", "Sources/Module2/File2.swift"]
      end
    end
  end

  describe "reading a commit's files" do
    @listings %{
      "a" => %{
        "Package.resolved" => "pins1",
        "Project.swift" => "project1",
        "Sources/A.swift" => "a1",
        "Sources/B.swift" => "b1",
        "Tests/ATests.swift" => "at1",
        "README.md" => "readme1"
      },
      "b" => %{
        "Package.resolved" => "pins2",
        "Project.swift" => "project1",
        "Sources/A.swift" => "a2",
        "Tests/ATests.swift" => "at1",
        "Tests/BTests.swift" => "bt1",
        "README.md" => "readme1"
      },
      "c" => %{
        "Package.resolved" => "pins1",
        "Project.swift" => "project1",
        "Sources/A.swift" => "a2",
        "Sources/Nested/C.swift" => "c1",
        "Tests/ATests.swift" => "at2",
        "README.md" => "readme1"
      },
      "f1" => %{
        "Package.resolved" => "pins2",
        "Project.swift" => "project2",
        "Sources/A.swift" => "a2",
        "Sources/F.swift" => "f1",
        "Tests/ATests.swift" => "at1",
        "Tests/BTests.swift" => "bt1"
      },
      "f2" => %{
        "Package.resolved" => "pins2",
        "Project.swift" => "project1",
        "Sources/A.swift" => "a3",
        "Sources/F.swift" => "f1",
        "Tests/BTests.swift" => "bt2"
      },
      "p1" => %{
        "Package.resolved" => "pins3",
        "Project.swift" => "project2",
        "Sources/A.swift" => "a2",
        "Sources/P.swift" => "p1",
        "Tests/ATests.swift" => "at1",
        "Tests/BTests.swift" => "bt1"
      }
    }

    @shas ["a", "b", "c", "f1", "f2", "p1", "truncated", "unlisted"]

    # main: a, b, c, truncated, unlisted. feature forks at b: f1, f2. pull/1
    # forks from feature at f1: p1.
    defp seed(repository) do
      commits(repository, [
        {"a", []},
        {"b", ["a"]},
        {"c", ["b"]},
        {"truncated", ["c"]},
        {"unlisted", ["truncated"]},
        {"f1", ["b"]},
        {"f2", ["f1"]},
        {"p1", ["f1"]}
      ])

      head(repository, "main", "unlisted")
      head(repository, "feature", "f2")
      GitHistory.advance_ref(repository, "pull/1", "feature", "p1")
    end

    defp record(repository, sha, files, opts \\ []) do
      files = Enum.map(files, fn {path, blob} -> %{path: path, git_blob_id: blob, mode: @mode} end)
      GitHistory.record_listing(repository, sha, files, Keyword.put_new(opts, :files_count, length(files)))
    end

    # Every read of the commits' files, and of what differs between each two.
    defp answers(repository, project) do
      tracked = ExcludedPaths.pattern(GitHistory.settings(project).tracked_file_globs)
      directories = ["Sources", "Tests", ".", "Missing"]
      paths = ["Sources/A.swift", "Sources/B.swift", "Sources/Nested/C.swift", "Package.resolved", "Missing.swift"]

      commits =
        for sha <- @shas, into: %{} do
          {sha,
           %{
             complete: GitHistory.listing_complete?(repository, sha),
             files: GitHistory.commit_files(repository, sha),
             matched: GitHistory.commit_files(repository, sha, match: tracked),
             tracked: GitHistory.tracked_files(project, repository, sha),
             in_directories: repository |> GitHistory.files_in(sha, directories) |> Enum.sort_by(& &1.path),
             blobs: GitHistory.blobs_at(repository, sha, paths)
           }}
        end

      changed =
        for from <- @shas, to <- @shas, into: %{} do
          {{from, to},
           %{
             all: GitHistory.changed_files(repository, from, to),
             matched: GitHistory.changed_files(repository, from, to, match: tracked),
             in_directories: GitHistory.changed_files(repository, from, to, directories: directories),
             paths: GitHistory.changed_files(repository, from, to, paths: paths)
           }}
        end

      %{commits: commits, changed: changed}
    end

    test "the file changes answer what the listings answered", %{repository: repository} do
      project = ProjectsFixtures.project_fixture()
      seed(repository)

      # Out of order, so some commits are written below others.
      for sha <- ["c", "p1", "a", "f2", "b", "f1"], do: record(repository, sha, @listings[sha])
      record(repository, "truncated", %{"Sources/A.swift" => "a9"}, truncated: true, files_count: 6)

      for sha <- @shas, do: assert(FileChanges.current(repository, sha) == nil)
      listed = answers(repository, project)

      settle()

      for sha <- @shas, do: assert(is_nil(FileChanges.current(repository, sha)) == sha in ["truncated", "unlisted"])
      assert answers(repository, project) == listed

      # And they are the listings.
      for {sha, files} <- @listings do
        assert listed.commits[sha].complete
        assert Map.new(listed.commits[sha].files, &{&1.path, &1.git_blob_id}) == files
      end

      refute listed.commits["truncated"].complete
      assert listed.changed[{"a", "truncated"}].all == :unknown

      assert listed.changed[{"b", "f2"}].all == [
               %{path: "README.md", from: "readme1", to: nil},
               %{path: "Sources/A.swift", from: "a2", to: "a3"},
               %{path: "Sources/F.swift", from: nil, to: "f1"},
               %{path: "Tests/ATests.swift", from: "at1", to: nil},
               %{path: "Tests/BTests.swift", from: "bt1", to: "bt2"}
             ]

      assert listed.changed[{"c", "p1"}].matched == [
               %{path: "Package.resolved", from: "pins1", to: "pins3"},
               %{path: "Project.swift", from: "project1", to: "project2"}
             ]
    end

    test "two commits read from different sources are compared all the same", %{repository: repository} do
      project = ProjectsFixtures.project_fixture()
      seed(repository)
      for sha <- ["a", "b", "c", "f1", "f2", "p1"], do: record(repository, sha, @listings[sha])
      listed = answers(repository, project).changed

      # Only some commits' file changes are written, as while a backfill runs.
      for sha <- ["a", "c", "f1"], do: assert(FileChanges.write(repository, sha) == :written)
      assert is_nil(FileChanges.current(repository, "b"))
      assert FileChanges.current(repository, "c")

      assert answers(repository, project).changed == listed
    end

    test "paths too long for one request are read in several", %{repository: repository} do
      commits(repository, [{"a", []}, {"b", ["a"]}])
      head(repository, "main", "b")
      directory = String.duplicate("Directory/", 20)
      files = for index <- 1..900, into: %{}, do: {"#{directory}File#{index}.swift", "blob#{index}"}
      changed = "#{directory}File7.swift"

      record(repository, "a", files)
      record(repository, "b", Map.put(files, changed, "changed"))
      settle()

      paths = Map.keys(files)
      assert GitHistory.blobs_at(repository, "b", paths) == Map.put(files, changed, "changed")

      assert GitHistory.changed_files(repository, "a", "b", paths: paths) == [
               %{path: changed, from: "blob7", to: "changed"}
             ]

      assert GitHistory.changed_files(repository, "a", "b", directories: [String.trim_trailing(directory, "/")]) ==
               [%{path: changed, from: "blob7", to: "changed"}]
    end

    test "more paths than one request binds are read from the whole state", %{repository: repository} do
      commits(repository, [{"a", []}, {"b", ["a"]}])
      head(repository, "main", "b")
      files = for index <- 1..1_200, into: %{}, do: {"Sources/File#{index}.swift", "blob#{index}"}

      record(repository, "a", files)
      record(repository, "b", Map.put(files, "Sources/File7.swift", "changed"))
      listed = GitHistory.blobs_at(repository, "b", ["Missing.swift" | Map.keys(files)])
      settle()

      assert FileChanges.current(repository, "b")
      assert GitHistory.blobs_at(repository, "b", ["Missing.swift" | Map.keys(files)]) == listed
      assert listed == Map.put(files, "Sources/File7.swift", "changed")
    end
  end
end
