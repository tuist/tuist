defmodule Tuist.Repo.Migrations.EnqueueCoverageRunFilesBackfill do
  @moduledoc """
  Queues the copy of the run rows `coverage_files` holds into
  `coverage_run_files` and `coverage_file_layouts`
  (`Tuist.Tests.Coverage.Workers.RunFilesBackfillWorker`), so a commit
  measured before the release still reads its runs. The job lands on the
  `coverage_backfills` queue, which only that release runs, and names the
  worker by string. An instance that never folded a commit has no coverage
  to copy.
  """
  use Ecto.Migration

  import Ecto.Query

  def up do
    if repo().exists?(from(c in "coverage_commits")) do
      now = NaiveDateTime.utc_now()

      repo().insert_all("oban_jobs", [
        %{
          state: "available",
          queue: "coverage_backfills",
          worker: "Tuist.Tests.Coverage.Workers.RunFilesBackfillWorker",
          args: %{pass: 1},
          max_attempts: 20,
          inserted_at: now,
          scheduled_at: now
        }
      ])
    end
  end

  def down, do: :ok
end
