defmodule Tuist.Runners.Workers.RepairReplicaDivergenceWorker do
  @moduledoc """
  One-off repair of ClickHouse `runner_jobs` rows left non-terminal while
  the Postgres lifecycle row is terminal
  (`Tuist.Runners.Jobs.repair_replica_divergence/3`), queued by the
  migration `20261014160000_enqueue_runner_job_replica_repair` with the
  `enqueued_after` timestamp to scan from.

  The rows it repairs were written before every outbox event took its
  version after the row lock (`Tuist.Runners.WorkflowJobs`), and before
  that, by the log archiver's direct writes. Neither can produce new ones,
  so this runs once rather than on a schedule; a new divergence is a new
  writer bug, which `tuist_runners_replica_divergence_count` surfaces.

  A capped scan snoozes until the flush has carried the repaired rows to
  ClickHouse, then scans again.
  """
  use Oban.Worker, queue: :default, max_attempts: 20

  alias Tuist.Runners.Jobs

  require Logger

  @settle_minutes 5
  @scan_limit 5_000
  @snooze_seconds 120

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"enqueued_after" => enqueued_after}}) do
    {:ok, enqueued_floor, _offset} = DateTime.from_iso8601(enqueued_after)
    settled_before = DateTime.add(DateTime.utc_now(), -@settle_minutes, :minute)

    result = Jobs.repair_replica_divergence(settled_before, enqueued_floor, @scan_limit)

    Logger.info(
      "runners: repaired ClickHouse runner_jobs rows left non-terminal " <>
        "(republished #{result.republished}, closed #{result.closed}, scanned #{result.scanned})"
    )

    if result.scanned == @scan_limit, do: {:snooze, @snooze_seconds}, else: :ok
  end
end
