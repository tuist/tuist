defmodule Tuist.Runners.Workers.BackfillWorkflowJobsWorker do
  @moduledoc """
  Walks ClickHouse `runner_jobs` in `workflow_job_id` order and brings
  jobs that predate `runner_workflow_jobs` into it
  (`Tuist.Runners.WorkflowJobs.backfill_from_replica/1`), so the
  Postgres lifecycle table answers for every job.

  Queued once by the migration that ships it. It skips what is already
  there, so a retry or a rerun (`Tuist.Release.backfill_runner_workflow_jobs/0`)
  starts over without rewriting anything current.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Runners.Jobs
  alias Tuist.Runners.WorkflowJobs

  require Logger

  @batch_size 1_000

  @impl Oban.Worker
  def perform(_job) do
    %{inserted: inserted, archive_markers: archive_markers} = backfill(@batch_size)

    Logger.info(
      "runners: backfilled #{inserted} lifecycle rows and #{archive_markers} archive markers from ClickHouse"
    )

    :ok
  end

  def backfill(batch_size) do
    backfill(0, batch_size, %{inserted: 0, archive_markers: 0})
  end

  defp backfill(after_id, batch_size, totals) do
    case Jobs.list_replica_after(after_id, batch_size) do
      [] ->
        totals

      jobs ->
        counts = WorkflowJobs.backfill_from_replica(jobs)
        totals = Map.merge(totals, counts, fn _key, total, count -> total + count end)
        backfill(List.last(jobs).workflow_job_id, batch_size, totals)
    end
  end
end
