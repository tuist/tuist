defmodule Tuist.Runners.Workers.UnstartedExecutionsWorker do
  @moduledoc """
  Starts lifecycle rows stuck in `status = 'queued'` while GitHub is
  already running them.

  ## How a row gets stuck

  GitHub binds a JIT runner to a label set, not to a job, so it
  routinely places job B on the Pod we minted for job A — the runner
  shuffle. `Tuist.Runners.Claims.record_execution/3` handles both halves
  on the `workflow_job.in_progress` webhook: A goes back to the queue,
  and B starts on the Pod's slot. B has no other way in. It was never
  claimed here, so no mint transitions it, and GitHub announces nothing
  further about a job it has already started.

  So a delivery that never lands strands B in `queued` for its whole
  runtime. The `completed` attribution path
  (`Claims.complete_by_runner_name/3`) recovers the claim in that case
  but not the row, and rows stranded before the webhook path started
  moving them have nothing coming at all.

  ## The evidence

  A `queued` row whose `runner_name` matches a live claim that names it
  as `executed_workflow_job_id` is running. GitHub told us so when it
  reported the runner, the claim is still holding that account's slot,
  and both rows agree on the runner. Nothing needs to be asked of
  GitHub, which is why this sweep carries no age gate: a row is stuck
  the moment it has this shape, and every minute it stays that way is a
  minute the dashboard shows a live build as Queued and the queue
  gauges — and the autoscaler reading them — provision for work that is
  already running.

  ## Safety

  `Tuist.Runners.WorkflowJobs.transition_executing/3` CASes from
  `queued` only, so a row a Pod has since claimed, or one a completion
  has settled, is left where it is. The per-tick cap bounds a
  wrong-but-plausible read the same way the other sweeps do; a
  sustained `tuist_runners_recovery_count{kind="unstarted_execution"}`
  means `in_progress` deliveries are being lost, which is the thing to
  fix rather than this.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners.Claims
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.WorkflowJobs

  require Logger

  @max_starts_per_tick 100

  @impl Oban.Worker
  def perform(_job) do
    started =
      @max_starts_per_tick
      |> Claims.list_executing_queued()
      |> Enum.count(&start_one/1)

    if started > 0 do
      Logger.warning("runners: started rows stuck queued while executing", count: started)
    end

    :ok
  end

  defp start_one(%{workflow_job_id: workflow_job_id, runner_name: runner_name, pod_name: pod_name} = row) do
    case WorkflowJobs.transition_executing(workflow_job_id, runner_name, pod_name) do
      :ok ->
        :telemetry.execute(
          Telemetry.event_name_recovery(),
          %{count: 1, stranded_ms: stranded_ms(row.enqueued_at)},
          %{kind: "unstarted_execution", fleet: row.fleet_name || ""}
        )

        true

      :noop ->
        false
    end
  end

  defp stranded_ms(%DateTime{} = enqueued_at) do
    DateTime.utc_now() |> DateTime.diff(enqueued_at, :millisecond) |> max(0)
  end

  defp stranded_ms(_enqueued_at), do: 0
end
