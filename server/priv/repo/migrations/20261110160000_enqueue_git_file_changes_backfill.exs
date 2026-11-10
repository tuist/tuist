defmodule Tuist.Repo.Migrations.EnqueueGitFileChangesBackfill do
  @moduledoc """
  Queues the file changes of the commits listed before they were written
  (`Tuist.GitHistory.Workers.FileChangesWorker`): one job per commit with a
  whole listing whose files are still kept, that a ref owns and that has no
  changes yet, each repository's lowest position first so a commit is
  compared with the one below it.

  This only inserts the jobs, naming the worker by string. A server from
  before the worker existed puts them back without running them
  (`Tuist.Oban.Engine`). By hand, for one repository:

      bin/tuist rpc "Tuist.GitHistory.FileChanges.enqueue_moved(<repository id>)"
  """
  use Ecto.Migration

  import Ecto.Query

  alias Tuist.Environment

  def up, do: enqueue_backfills!(repo())

  def down, do: :ok

  @doc false
  def enqueue_backfills!(repo) do
    now = NaiveDateTime.utc_now()

    kept =
      DateTime.add(DateTime.utc_now(), -(Environment.coverage_retention_days().files - 1), :day)

    from(l in "git_commit_listings",
      join: c in "git_commits",
      on: c.repository_id == l.repository_id and c.sha == l.sha,
      where:
        not l.truncated and is_nil(l.changes_ref_id) and not is_nil(c.ref_id) and
          l.inserted_at >= ^kept,
      order_by: [asc: l.repository_id, asc: c.position],
      select: %{repository_id: l.repository_id, sha: l.sha}
    )
    |> repo.all()
    |> Enum.map(
      &%{
        state: "available",
        queue: "coverage_deltas",
        worker: "Tuist.GitHistory.Workers.FileChangesWorker",
        args: &1,
        max_attempts: 5,
        inserted_at: now,
        scheduled_at: now
      }
    )
    |> Enum.chunk_every(1_000)
    |> Enum.each(&repo.insert_all("oban_jobs", &1))
  end
end
