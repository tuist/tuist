defmodule Tuist.Runners.Workers.StaleClaimsWorker do
  @moduledoc """
  Recovers Postgres `runner_claims` rows **in `lifecycle_state =
  'claimed'`** stuck past the recovery threshold by re-INSERTing
  a `queued` state row into ClickHouse `runner_jobs` and then
  DELETEing the matching PG row.

  `running` claims are explicitly NOT in scope: a build that has
  successfully minted a JIT and registered with GitHub holds its
  cap slot for as long as the build runs (potentially hours).
  Reaping those at the 5-min threshold would free the slot of an
  actively-running runner and let another claim take its place,
  pushing the account over cap. `Claims.list_stale/1` filters on
  `lifecycle_state = 'claimed'` so a long-running build is
  invisible to this worker.

  ## Why CH first

  Order matters. If we DELETEd the PG row first and then crashed
  before the CH transition, the row would stay `claimed` in CH —
  `pick_queued` would skip it — with no PG claim left for the
  next worker run to find. The workflow_job would be stranded.

  With CH first:

    * Both succeed → row is back in the queued pool, cap slot
      freed.
    * CH succeeds, PG delete fails / crash → CH says queued, PG
      still claimed. Dispatch skips rows already claimed in PG
      before selecting queued work, so later workflow_jobs can
      keep moving. The next worker run sees the same stale PG row
      and retries.
    * CH fails → leave PG alone; next worker run retries the
      whole sequence.

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
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Telemetry

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

    :ok
  end

  defp recover_one(%{workflow_job_id: id, claimed_at: handle}) do
    with :ok <- safe_record_queued(id),
         :ok <- safe_release(id, handle) do
      true
    else
      _ -> false
    end
  end

  # CH first — see moduledoc. Treat a CH failure as "skip this row,
  # retry next tick" — the PG claim stays put so we re-see it.
  defp safe_record_queued(workflow_job_id) do
    Jobs.record_queued(workflow_job_id)
  rescue
    e ->
      Logger.warning("runners: record_queued failed in stale-worker; will retry next tick",
        workflow_job_id: workflow_job_id,
        ch_error: Exception.message(e)
      )

      :error
  end

  defp safe_release(workflow_job_id, handle) do
    case Claims.release(workflow_job_id, handle) do
      :ok ->
        :ok

      {:error, :stale_claim} ->
        # Someone else released + re-claimed between our list_stale
        # and our release. The new claim has a newer claimed_at and
        # our CH record_queued didn't touch it; fine.
        :error
    end
  end
end
