defmodule Tuist.Repo.Migrations.EnqueueCoveragePinsBackfill do
  @moduledoc """
  Queues the pinning of the shard reports of runs published before
  `coverage_runs` carried pins (`Tuist.Tests.Coverage.Workers.PinsBackfillWorker`),
  so readers can take every run's reports from its pins alone. The job lands
  on the `coverage_pins_backfill` queue, which only this release runs, and
  names the worker by string. An
  instance that never folded a commit has no coverage to pin.
  """
  use Ecto.Migration

  import Ecto.Query

  def up do
    if repo().exists?(from(c in "coverage_commits")) do
      now = NaiveDateTime.utc_now()

      repo().insert_all("oban_jobs", [
        %{
          state: "available",
          queue: "coverage_pins_backfill",
          worker: "Tuist.Tests.Coverage.Workers.PinsBackfillWorker",
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
