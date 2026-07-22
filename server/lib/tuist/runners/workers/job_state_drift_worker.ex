defmodule Tuist.Runners.Workers.JobStateDriftWorker do
  @moduledoc """
  Log-only comparator between the Postgres workflow_job lifecycle rows
  (`runner_workflow_jobs`) — the control-plane store dispatch and the
  recovery workers read — and the ClickHouse `runner_jobs` argMax view
  that the customer-facing dashboards read. Sustained zero drift is
  the confidence signal that ClickHouse (fed by both the direct writes
  and the transition outbox) faithfully mirrors Postgres; once it
  holds, the direct ClickHouse writes and this worker itself can be
  deleted. It never mutates either store.

  Each tick diffs the Postgres rows updated inside the lookback
  window against ClickHouse's latest status for the same
  workflow_jobs:

    * `status_mismatch` — both stores have the job, statuses differ.
      ClickHouse's `completed` + conclusion pair is folded into the
      Postgres status space first (`completed` with conclusion
      `cancelled` reads as `cancelled`), so a cancelled/completed
      disagreement between the stores is drift, not equivalence.
    * `missing_in_clickhouse` — Postgres has a row, ClickHouse has
      none. Expected only if the paired CH INSERT failed after the PG
      transaction committed.

  Rows updated in the last minute are excluded: a Postgres transition
  commits before its paired ClickHouse INSERT lands (claim transitions
  commit inside the claim transaction, the CH write follows; outbox
  replication adds up to a minute of flusher lag), so very fresh rows
  would report propagation lag as drift.

  `missing_in_postgres` is deliberately not a kind: this worker's scan
  is Postgres-driven, and jobs that exist only in ClickHouse (enqueued
  by code predating the lifecycle table) are
  `Tuist.Runners.Workers.BackfillWorkflowJobsWorker`'s job to adopt,
  not this one's to report.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Runners.Job
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.WorkflowJobs

  require Logger

  @lookback_seconds 2 * 3_600
  @settle_seconds 60
  @max_rows 5_000
  @sample_limit 20

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    updated_after = DateTime.add(now, -@lookback_seconds, :second)
    updated_before = DateTime.add(now, -@settle_seconds, :second)

    rows = WorkflowJobs.list_recently_updated(updated_after, updated_before, @max_rows)

    if rows != [] do
      report(rows, clickhouse_statuses(rows))
    end

    :ok
  end

  defp report(rows, ch_statuses) do
    drift =
      Enum.flat_map(rows, fn row ->
        case Map.fetch(ch_statuses, row.workflow_job_id) do
          :error ->
            [{:missing_in_clickhouse, row, nil}]

          {:ok, ch_status} ->
            if row.status == ch_status do
              []
            else
              [{:status_mismatch, row, ch_status}]
            end
        end
      end)

    emit(:telemetry_compared, length(rows))

    drift
    |> Enum.group_by(fn {kind, _row, _ch_status} -> kind end)
    |> Enum.each(fn {kind, entries} ->
      emit(kind, length(entries))

      samples =
        entries
        |> Enum.take(@sample_limit)
        |> Enum.map(fn {_kind, row, ch_status} ->
          %{workflow_job_id: row.workflow_job_id, postgres: row.status, clickhouse: ch_status}
        end)

      Logger.warning("runners: workflow_job state drift between Postgres and ClickHouse",
        kind: Atom.to_string(kind),
        count: length(entries),
        compared: length(rows),
        samples: inspect(samples)
      )
    end)

    :ok
  end

  defp emit(kind, count) do
    :telemetry.execute(
      Telemetry.event_name_workflow_job_drift(),
      %{count: count},
      %{kind: drift_kind(kind)}
    )
  end

  defp drift_kind(:telemetry_compared), do: "compared"
  defp drift_kind(kind), do: Atom.to_string(kind)

  # Latest (status, conclusion) per job, folded into the Postgres
  # status space so the comparison is a plain equality. The
  # enqueued_at floor prunes the ClickHouse scan to the partitions
  # the compared rows can live in — same reason the dispatch read
  # floors on it. `enqueued_at` is stable across a job's transitions,
  # so the batch minimum (minus a second of slack) is exact.
  defp clickhouse_statuses(rows) do
    ids = Enum.map(rows, & &1.workflow_job_id)

    floor =
      rows
      |> Enum.map(& &1.enqueued_at)
      |> Enum.min(DateTime)
      |> DateTime.add(-1, :second)

    from(j in Job,
      where: j.workflow_job_id in ^ids and j.enqueued_at > ^floor,
      group_by: j.workflow_job_id,
      select:
        {j.workflow_job_id,
         {fragment("argMax(?, ?)", j.status, j.updated_at), fragment("argMax(?, ?)", j.conclusion, j.updated_at)}}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn {workflow_job_id, {status, conclusion}} ->
      {workflow_job_id, equivalent_status(status, conclusion)}
    end)
  end

  defp equivalent_status("completed", "cancelled"), do: "cancelled"
  defp equivalent_status(status, _conclusion), do: status
end
