defmodule Tuist.Repo.Migrations.EnqueueCoverageSourceBackfill do
  @moduledoc """
  Queues the backfill of the test versions and target sources carried
  coverage reads
  (`Tuist.Tests.Coverage.Workers.SourceBackfillWorker`), one job per
  project with folded coverage, so the release that ships the index fills it
  for the runs still within the file retention rather than by hand. This
  only inserts the jobs, naming the worker by string.
  """
  use Ecto.Migration

  import Ecto.Query

  def up do
    now = NaiveDateTime.utc_now()

    jobs =
      from(c in "coverage_commits", distinct: true, select: c.project_id)
      |> repo().all()
      |> Enum.map(fn project_id ->
        %{
          state: "available",
          queue: "coverage_deltas",
          worker: "Tuist.Tests.Coverage.Workers.SourceBackfillWorker",
          args: %{project_id: project_id},
          max_attempts: 20,
          inserted_at: now,
          scheduled_at: now
        }
      end)

    repo().insert_all("oban_jobs", jobs)
  end

  def down, do: :ok
end
