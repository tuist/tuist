defmodule Tuist.Repo.Migrations.EnqueueTestRunSelectionsBackfill do
  @moduledoc """
  Queues the backfill of `test_run_selections`, the per-run test selection
  effectiveness the dashboards read
  (`Tuist.Tests.Workers.RunSelectionsBackfillWorker`), so the release that
  ships the table fills it for earlier runs rather than by hand. The job
  lists the projects in ClickHouse and queues one job per project. This only
  inserts the job, naming the worker by string, and only on a server that
  has projects: a new one has no runs to fill.
  """
  use Ecto.Migration

  import Ecto.Query

  def up do
    if repo().exists?(from(p in "projects", select: 1)) do
      now = NaiveDateTime.utc_now()

      repo().insert_all("oban_jobs", [
        %{
          state: "available",
          queue: "default",
          worker: "Tuist.Tests.Workers.RunSelectionsBackfillWorker",
          args: %{},
          max_attempts: 20,
          inserted_at: now,
          scheduled_at: now
        }
      ])
    end
  end

  def down, do: :ok
end
