defmodule Tuist.Runners.Workers.BackfillWorkflowJobsWorker do
  @moduledoc """
  Transitional healer for the Postgres-read cutover: adopts lifecycle
  rows for workflow_jobs that exist only in ClickHouse.

  Dispatch, the autoscaler, and the recovery workers read
  `runner_workflow_jobs` exclusively. A job whose `queued` webhook was
  handled by code predating that table has a ClickHouse row but no
  Postgres row — invisible to dispatch and to every recovery scan, so
  it would strand forever. The window is real on every deploy of the
  cutover release: jobs enqueued through old pods during the roll are
  exactly this class.

  Each tick lists ClickHouse's non-terminal rows inside the dispatch
  lookback window, drops the ones Postgres already has, and inserts
  the rest in their current ClickHouse status via
  `Tuist.Runners.WorkflowJobs.adopt_missing/1` (`ON CONFLICT DO
  NOTHING` + completion guard, so racing a live transition or a
  redelivery is safe). Steady state finds nothing — every new job is
  written to Postgres at enqueue — so the tick is one cheap ClickHouse
  aggregation over a bounded window.

  Delete together with the direct ClickHouse writes: once no code
  path writes ClickHouse first, no ClickHouse-only job can exist.
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
    enqueued_after = DateTime.add(DateTime.utc_now(), -@lookback_seconds, :second)

    ch_rows = Jobs.list_non_terminal(enqueued_after)

    missing =
      case ch_rows do
        [] ->
          []

        ch_rows ->
          ids = Enum.map(ch_rows, & &1.workflow_job_id)

          existing =
            MapSet.new(Repo.all(from(j in WorkflowJob, where: j.workflow_job_id in ^ids, select: j.workflow_job_id)))

          Enum.reject(ch_rows, &MapSet.member?(existing, &1.workflow_job_id))
      end

    if missing != [] do
      adopted = WorkflowJobs.adopt_missing(missing)

      Logger.warning("runners: adopted ClickHouse-only workflow_jobs into Postgres",
        count: adopted,
        workflow_job_ids: inspect(Enum.map(missing, & &1.workflow_job_id))
      )

      :telemetry.execute(Telemetry.event_name_recovery(), %{count: adopted}, %{kind: "lifecycle_adopted"})
    end

    :ok
  end
end
