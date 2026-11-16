defmodule Tuist.Repo.Migrations.EnqueueTestImpactSnapshotBackfill do
  @moduledoc """
  Queues the backfill of the test maps coverage-based test selection and
  coverage carry read
  (`Tuist.TestImpactAnalysis.Workers.SnapshotBackfillWorker`), one job per
  project with coverage folded within the maps' 31-day retention, so the
  release that ships them fills them rather than by hand. This only inserts
  the jobs, naming the worker by string.
  """
  use Ecto.Migration

  import Ecto.Query

  def up do
    now = DateTime.utc_now()
    since = DateTime.add(now, -31 * 86_400, :second)

    jobs =
      from(c in "coverage_commits",
        where: c.ran_at >= ^since,
        distinct: true,
        select: c.project_id
      )
      |> repo().all()
      |> Enum.map(fn project_id ->
        %{
          state: "available",
          queue: "coverage_deltas",
          worker: "Tuist.TestImpactAnalysis.Workers.SnapshotBackfillWorker",
          args: %{project_id: project_id},
          max_attempts: 20,
          inserted_at: DateTime.to_naive(now),
          scheduled_at: DateTime.to_naive(now)
        }
      end)

    repo().insert_all("oban_jobs", jobs)
  end

  def down, do: :ok
end
