defmodule Tuist.Runners.Workers.UnstartedExecutionsWorker do
  @moduledoc """
  Starts lifecycle rows stuck in `status = 'queued'` while a live claim
  already records GitHub running them.

  ## How a row gets stuck

  GitHub binds a JIT runner to a label set, not to a job, so it
  routinely places job B on the Pod we minted for job A — the runner
  shuffle. `Tuist.Runners.Claims.record_execution/3` handles both halves
  on the `workflow_job.in_progress` webhook: A goes back to the queue,
  and B starts on the Pod's slot. B has no other way in. It was never
  claimed here, so no mint transitions it, and GitHub announces nothing
  further about a job it has already started.

  That CAS can still miss. B may be `claimed` by another Pod at the
  time, so the transition is refused and the later release drops B back
  to `queued`; or B's own `queued` webhook may not have arrived yet, so
  there is no row to move and the one inserted afterwards starts life
  `queued` under a runner that is already executing it. Rows stranded
  before that transition existed have nothing coming at all.

  ## The evidence

  The claim, and only the claim. `executed_workflow_job_id` is written
  from a delivery where GitHub named this runner running that job,
  scoped to the account, and a claim is deleted on completion — so a
  live claim still naming a `queued` row proves that row is running.
  Nothing needs to be asked of GitHub, which is why this sweep has no
  age gate: a row is stuck the moment it has this shape, and every
  minute it stays that way is a minute the dashboard shows a live build
  as Queued and the queue gauges — and the autoscaler reading them —
  provision for work already running.

  ## What it does not cover

  An `in_progress` delivery that never lands at all. Nothing then writes
  `executed_workflow_job_id`, so no claim carries the evidence, and the
  `completed` webhook deletes the claim while flipping the row terminal
  (`Claims.complete_by_runner_name/3`). Those rows end as phantom
  terminals — `started_at` NULL with a `runner_name` — and closing that
  class needs the durable `runner_sessions` binding, which outlives the
  Pod, rather than this sweep.

  ## Safety

  `Tuist.Runners.WorkflowJobs.start_executing_queued/1` re-applies its
  guards in the write and moves rows out of `queued` only, so a row a
  Pod has since claimed, or one a completion has settled, is left where
  it is. A sustained
  `tuist_runners_recovery_count{kind="unstarted_execution"}` means
  `in_progress` deliveries are being lost, which is the thing to fix
  rather than this.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.WorkflowJobs

  require Logger

  @max_starts_per_tick 100

  @impl Oban.Worker
  def perform(_job) do
    started = WorkflowJobs.start_executing_queued(@max_starts_per_tick)

    Enum.each(started, &report_started/1)

    if started != [] do
      Logger.warning("runners: started rows stuck queued while executing", count: length(started))
    end

    :ok
  end

  defp report_started(row) do
    :telemetry.execute(
      Telemetry.event_name_recovery(),
      %{count: 1, stranded_ms: stranded_ms(row.enqueued_at)},
      %{kind: "unstarted_execution", fleet: row.fleet_name || ""}
    )
  end

  defp stranded_ms(%DateTime{} = enqueued_at) do
    DateTime.utc_now() |> DateTime.diff(enqueued_at, :millisecond) |> max(0)
  end

  defp stranded_ms(_enqueued_at), do: 0
end
