defmodule Tuist.Runners.Workers.StaleClaimsWorker do
  @moduledoc """
  Recovers Postgres `runner_claims` rows **in `lifecycle_state =
  'claimed'`** stuck past the recovery threshold. `Claims.release/2`
  deletes the claim and moves the workflow_job's lifecycle row back
  to `queued` in one transaction, so the job is immediately
  claimable again.

  `running` claims are explicitly NOT in scope: a build that has
  successfully minted a JIT and registered with GitHub holds its
  cap slot for as long as the build runs (potentially hours).
  Reaping those at the 5-min threshold would free the slot of an
  actively-running runner and let another claim take its place,
  pushing the account over cap. `Claims.list_stale/1` filters on
  `lifecycle_state = 'claimed'` so a long-running build is
  invisible to this worker.

  ## Second pass: claims held past a recorded completion

  A `running` claim IS released when its workflow_job has a
  `runner_job_completions` row (`Claims.release_completed/1`). That is
  proof the job is over rather than a timeout, so the objection above
  does not apply.

  This pass exists because such a claim is invisible to every other
  recovery path: the sweep above only sees `claimed`, and
  `OrphanedRunnersWorker` drives off lifecycle rows still in
  `status = 'running'` — recording the completion already moved the row
  out of that state, so its scan never returns it. The slot would be
  held until the account is deleted.

  A successful `claimed → running` transition normally happens
  within a few seconds — claim → mint → mark_running. If the
  server crashes between the PG INSERT and the mint completion,
  the PG row stays in `claimed` state and the customer's cap
  slot is consumed for a job that will never run. Threshold is
  generous (5 min) because the happy path is sub-second;
  anything stuck > 5 min in `claimed` is overwhelmingly a real
  failure rather than an in-flight mint.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners.Claims
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.VolumeAffinities

  require Logger

  @stale_after_seconds 300

  @impl Oban.Worker
  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@stale_after_seconds, :second)

    released =
      threshold
      |> Claims.list_stale()
      |> Enum.count(&recover_one/1)

    if released > 0 do
      Logger.warning("runners: released stale claims",
        count: released,
        stale_after_seconds: @stale_after_seconds
      )

      :telemetry.execute(
        Telemetry.event_name_recovery(),
        %{count: released},
        %{kind: "stale_claim"}
      )
    end

    release_completed_claims(threshold)

    # Opportunistically prune volume-affinity rows past their retention
    # window. Cheap indexed range delete, usually 0 rows;
    # piggybacks on this periodic runner-maintenance sweep rather than
    # adding a separate cron entry.
    VolumeAffinities.prune()

    :ok
  end

  # Second pass: claims whose workflow_job already has a recorded
  # completion. Unlike the sweep above these are usually in `running`,
  # which the time-based pass must never touch — but here the completion
  # row is independent proof the job is over, not a timeout guess.
  #
  # Nothing else reclaims them. `list_stale/1` only sees `claimed`, and
  # `OrphanedRunnersWorker` scans lifecycle rows still in
  # `status = 'running'` — the completion already moved the row out of
  # that state, so it never appears there. The slot would otherwise be
  # held for the account's lifetime.
  #
  # No lifecycle transition and no GitHub call: the job is already
  # recorded complete, so there is nothing to requeue or confirm.
  defp release_completed_claims(threshold) do
    case Claims.release_completed(threshold) do
      0 ->
        :ok

      count ->
        Logger.warning("runners: released claims held past a recorded completion",
          count: count
        )

        :telemetry.execute(
          Telemetry.event_name_recovery(),
          %{count: count},
          %{kind: "completed_claim"}
        )

        :ok
    end
  end

  defp recover_one(%{workflow_job_id: id, claimed_at: handle}) do
    case Claims.release(id, handle) do
      :ok ->
        true

      {:error, :stale_claim} ->
        # Someone else released + re-claimed between our list_stale
        # and our release; the new claim has a newer claimed_at.
        false
    end
  end
end
