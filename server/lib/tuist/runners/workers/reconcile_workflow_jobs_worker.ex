defmodule Tuist.Runners.Workers.ReconcileWorkflowJobsWorker do
  @moduledoc """
  Transitional healer for the Postgres-read cutover. Dispatch, the
  autoscaler, and the recovery workers read `runner_workflow_jobs`
  exclusively, but the previous release never wrote it — so while old
  and new pods overlap (every roll of the cutover release, and any
  rollback followed by a roll-forward) the table can miss jobs or hold
  them in a state the old code has since moved past. Each tick heals
  both classes:

    * **Adopt ClickHouse-only jobs.** A job whose `queued` webhook the
      old code handled has a `runner_jobs` row and no Postgres row —
      invisible to dispatch and every recovery scan. The tick lists
      ClickHouse's non-terminal rows inside the dispatch lookback
      window and inserts the missing ones in their current status.
      Each insert runs under the workflow_job ordering lock, the same
      lock every completion writer (old and new) takes, so the
      completion check and the insert cannot straddle a completion
      landing between them and adopt a dead job as live.
    * **Close rows the old code completed.** Every completion path,
      old and new, records `runner_job_completions`; a Postgres row
      still non-terminal alongside one is stale and is closed with the
      completion's conclusion.
    * **Re-queue `claimed` rows no claim backs.** The old code's
      stale-claim sweep and pod-stopped path delete a claim without
      touching this table; a `claimed` row is pre-mint by construction,
      so with its claim gone the job can be re-queued safely.
    * **Bring `queued` rows a live claim backs to the claim's state.**
      The old code's `Claims.attempt/5` and `mark_running/2` write the
      claim only; without this the job reads `queued` while a Pod
      holds it.

  Steady state finds nothing on any pass — every new job is written to
  Postgres at enqueue and moved by the same transactions that move its
  claim — so the tick is one bounded ClickHouse aggregation plus three
  Postgres index lookups over the live set.

  Delete together with the direct ClickHouse writes: once no code path
  writes ClickHouse first and no code path moves a claim without its
  lifecycle row, none of these states can arise.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  require Logger

  # Matches the dispatch read's `enqueued_at` floor: anything older can
  # never be claimable again, so it doesn't need a lifecycle row.
  @lookback_seconds 7 * 86_400

  @impl Oban.Worker
  def perform(_job) do
    adopt_missing()

    report("lifecycle_closed", WorkflowJobs.close_completed())
    report("lifecycle_synced_claimed", WorkflowJobs.sync_claimed_from_claims())
    report("lifecycle_requeued_unbacked", WorkflowJobs.requeue_unbacked_claimed())

    :ok
  end

  defp adopt_missing do
    enqueued_after = DateTime.add(DateTime.utc_now(), -@lookback_seconds, :second)

    candidates =
      case Jobs.list_non_terminal(enqueued_after) do
        [] ->
          []

        ch_rows ->
          ids = Enum.map(ch_rows, & &1.workflow_job_id)

          existing =
            MapSet.new(Repo.all(from(j in WorkflowJob, where: j.workflow_job_id in ^ids, select: j.workflow_job_id)))

          completed = MapSet.new(WorkflowJobs.completed_ids(ids))

          Enum.reject(ch_rows, fn row ->
            MapSet.member?(existing, row.workflow_job_id) or MapSet.member?(completed, row.workflow_job_id)
          end)
      end

    adopted =
      Enum.reduce(candidates, 0, fn ch_row, count ->
        case Jobs.with_workflow_job_ordering_lock(ch_row.workflow_job_id, fn -> WorkflowJobs.adopt(ch_row) end) do
          inserted when is_integer(inserted) -> count + inserted
          {:error, _reason} -> count
        end
      end)

    if adopted > 0 do
      Logger.warning("runners: adopted ClickHouse-only workflow_jobs into Postgres",
        count: adopted,
        workflow_job_ids: inspect(Enum.map(candidates, & &1.workflow_job_id))
      )
    end

    report("lifecycle_adopted", adopted)
  end

  defp report(_kind, 0), do: :ok

  defp report(kind, count) do
    Logger.warning("runners: reconciled workflow_job lifecycle rows", kind: kind, count: count)
    :telemetry.execute(Telemetry.event_name_recovery(), %{count: count}, %{kind: kind})
  end
end
