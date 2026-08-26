defmodule Tuist.Runners.Workers.FlushJobTransitionEventsWorker do
  @moduledoc """
  Batch-flushes `runner_workflow_job_transition_events` outbox rows
  into the ClickHouse `runner_jobs` table.

  Events are written by `Tuist.Runners.WorkflowJobs` in the same
  Postgres transaction as the lifecycle transition they describe,
  so the outbox is exactly the committed transition stream. This
  worker drains it in id-ordered batches: SELECT … FOR UPDATE SKIP
  LOCKED, INSERT the decoded payloads into ClickHouse, then DELETE
  the flushed rows — all inside one Postgres transaction per batch.

  This is how ClickHouse learns about lifecycle transitions — the
  `runner_jobs` table is a replica fed from this outbox (plus the
  CH-only `log_archived_at` stamp in `Tuist.Runners.Jobs`). Ordering
  inside a batch doesn't matter for correctness: each payload carries
  the transition's own `updated_at`, and the RMT's
  argMax-by-`updated_at` read resolves any interleaving.

  Crash safety: the CH INSERT happens before the PG DELETE, so a
  crash between the two re-flushes the batch next tick. Replayed
  rows are byte-identical (same `updated_at`), which the RMT dedups.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Runners.Job
  alias Tuist.Runners.WorkflowJobs
  alias Tuist.Runners.WorkflowJobTransitionEvent

  @batch_size 500
  @max_batches_per_tick 20

  @impl Oban.Worker
  def perform(_job) do
    flush_batches(@max_batches_per_tick)
  end

  defp flush_batches(0), do: :ok

  defp flush_batches(remaining) do
    case flush_batch() do
      :done -> :ok
      :more -> flush_batches(remaining - 1)
    end
  end

  defp flush_batch do
    {:ok, outcome} =
      Repo.transaction(fn ->
        events =
          Repo.all(
            from(e in WorkflowJobTransitionEvent,
              order_by: [asc: e.id],
              limit: @batch_size,
              lock: "FOR UPDATE SKIP LOCKED"
            )
          )

        case events do
          [] ->
            :done

          events ->
            rows = Enum.map(events, &WorkflowJobs.decode_transition_payload(&1.payload))
            IngestRepo.insert_all(Job, rows)

            ids = Enum.map(events, & &1.id)
            Repo.delete_all(from(e in WorkflowJobTransitionEvent, where: e.id in ^ids))

            if length(events) == @batch_size, do: :more, else: :done
        end
      end)

    outcome
  end
end
