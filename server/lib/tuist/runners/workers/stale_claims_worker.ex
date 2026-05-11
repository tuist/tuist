defmodule Tuist.Runners.Workers.StaleClaimsWorker do
  @moduledoc """
  Recovers Postgres `runner_claims` rows stuck past the recovery
  threshold by deleting them and re-INSERTing a `queued` state
  row into the ClickHouse `runner_jobs` table so the next poll
  can pick the workflow_job up again.

  A successful claim normally lives at most a few seconds — claim
  → mint → start. If the server crashes between the PG INSERT and
  the JIT-mint completion, the PG row stays stuck and the
  customer's cap slot is consumed for a job that will never run.

  Threshold is generous (5 min) because the happy path is
  sub-second; anything stuck > 5 min is overwhelmingly a real
  failure rather than an in-flight mint.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs

  require Logger

  @stale_after_seconds 300

  @impl Oban.Worker
  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@stale_after_seconds, :second)

    case Claims.release_stale(threshold) do
      [] ->
        :ok

      released ->
        Enum.each(released, fn %{workflow_job_id: id} ->
          Jobs.record_queued(id)
        end)

        Logger.warning("runners: released stale claims",
          count: length(released),
          stale_after_seconds: @stale_after_seconds
        )

        :ok
    end
  end
end
