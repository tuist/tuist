defmodule Tuist.Repo.Migrations.EnqueueRunnerJobReplicaRepair do
  @moduledoc """
  Queues one pass of `Tuist.Runners.Workers.RepairReplicaDivergenceWorker`
  over the whole `runner_jobs` history, so the release that ships it
  repairs the ClickHouse rows left non-terminal before the worker
  existed: the ones the log archiver re-asserted as running between
  2026-08-19 and 2026-08-21, the ones a completion lost to a concurrent
  claim or release, and the ones from before `runner_workflow_jobs`
  existed. The worker's cron pass only looks back seven days.

  The repair reads PostgreSQL and ClickHouse together, so this only
  inserts the job, naming the worker by string. A database without runner
  jobs has nothing to repair and gets no job.
  """
  use Ecto.Migration

  import Ecto.Query

  def up, do: enqueue_repair!(repo())

  def down, do: :ok

  @doc false
  def enqueue_repair!(repo) do
    if repo.exists?(from(j in "runner_workflow_jobs", select: 1)) do
      now = NaiveDateTime.utc_now()

      repo.insert_all("oban_jobs", [
        %{
          state: "available",
          queue: "default",
          worker: "Tuist.Runners.Workers.RepairReplicaDivergenceWorker",
          args: %{enqueued_after: "2026-01-01T00:00:00Z"},
          max_attempts: 20,
          inserted_at: now,
          scheduled_at: now
        }
      ])
    end
  end
end
