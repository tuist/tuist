Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261110140000_enqueue_git_file_changes_backfill.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.EnqueueGitFileChangesBackfillTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.GitHistory
  alias Tuist.GitHistory.CommitListing
  alias Tuist.GitHistory.FileChanges
  alias Tuist.GitHistory.Workers.FileChangesWorker
  alias Tuist.Repo.Migrations.EnqueueGitFileChangesBackfill
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures

  test "queues the listed commits a ref owns that have no file changes yet, lowest position first" do
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    repository =
      CoverageFixtures.seed_history(
        account,
        [
          CoverageFixtures.commit("a", [], 0),
          CoverageFixtures.commit("b", ["a"], 1),
          CoverageFixtures.commit("c", ["b"], 2),
          CoverageFixtures.commit("d", ["c"], 3),
          CoverageFixtures.commit("e", ["d"], 4),
          CoverageFixtures.commit("unowned", ["a"], 5)
        ],
        branch_heads: [{"main", "e"}]
      )

    for sha <- ["c", "a", "b", "e", "unowned"], do: CoverageFixtures.seed_listing(account, sha, ["Sources/#{sha}.swift"])
    GitHistory.record_listing(repository, "d", [%{path: "Sources/d.swift", git_blob_id: "d"}], truncated: true)

    # The writer already wrote `a`; `e`'s files expired.
    assert FileChanges.write(repository, "a") == :written

    Repo.update_all(from(l in CommitListing, where: l.repository_id == ^repository and l.sha == "e"),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -90, :day)]
    )

    Repo.delete_all(Oban.Job)

    EnqueueGitFileChangesBackfill.enqueue_backfills!(Repo)

    assert [
             %{args: %{"repository_id" => ^repository, "sha" => "b"}, queue: "coverage_deltas", max_attempts: 5},
             %{args: %{"sha" => "c"}}
           ] = [worker: FileChangesWorker] |> all_enqueued() |> Enum.sort_by(& &1.id)

    assert %{success: 2} = Oban.drain_queue(queue: :coverage_deltas, with_safety: false)
    assert FileChanges.current(repository, "c")
  end
end
