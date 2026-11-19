defmodule Tuist.Repo.Migrations.EnqueueRunnerWorkflowJobsBackfill do
  @moduledoc """
  Queues the backfill of `runner_workflow_jobs` from ClickHouse
  `runner_jobs` (`Tuist.Runners.Workers.BackfillWorkflowJobsWorker`) for the
  jobs that predate the table, on deployments that have run runner jobs. This
  only inserts the job, naming the worker by string.
  """
  use Ecto.Migration

  import Ecto.Query

  def up do
    if repo().exists?(from(j in "runner_workflow_jobs", select: 1)) do
      now = NaiveDateTime.utc_now()

      repo().insert_all("oban_jobs", [
        %{
          state: "available",
          queue: "default",
          worker: "Tuist.Runners.Workers.BackfillWorkflowJobsWorker",
          args: %{},
          max_attempts: 5,
          inserted_at: now,
          scheduled_at: now
        }
      ])
    end
  end

  def down, do: :ok
end
