defmodule Tuist.GitHistory.FileChangesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.GitHistory.CommitListing
  alias Tuist.GitHistory.FileChange
  alias Tuist.GitHistory.FileChanges
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures

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
    |> GitHistory.position(sha)
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

  test "a rewritten branch retires the rows of the commits it dropped", %{repository: repository} do
    commits(repository, [{"a", []}, {"f1", ["a"]}, {"g1", ["a"]}])
    head(repository, "main", "a")
    head(repository, "feature", "f1")

    list(repository, "a", %{"A.swift" => "a1"})
    list(repository, "f1", %{"A.swift" => "a2", "F.swift" => "f1"})

    # A force-push: `g1` takes the place `f1` held.
    head(repository, "feature", "g1")
    list(repository, "g1", %{"A.swift" => "a1", "G.swift" => "g1"})

    assert changes(repository, "f1") == %{}
    assert %{changes_ref_id: nil, changes_position: nil, changes_count: nil} = listing(repository, "f1")
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
end
