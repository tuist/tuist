defmodule Tuist.Runners.Workers.StaleClaimsWorker do
  @moduledoc """
  Recovers `runner_jobs` rows stuck in `status='claimed'` past
  the recovery threshold by INSERTing a fresh row that transitions
  them back to `status='queued'`.

  A successful claim normally lives at most a few seconds — claim
  → mint → start. If the server crashes between the `claimed`
  INSERT and the `running` INSERT, the row stays stuck. The
  ReplacingMergeTree merge keeps the latest `updated_at` row, so
  re-INSERTing with a `queued` state and a fresh timestamp puts
  the row back into the dispatch candidate pool.

  Threshold is generous (5 min) because the happy path is
  sub-second; anything stuck > 5 min is overwhelmingly a real
  failure rather than an in-flight mint.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners.Jobs

  require Logger

  @stale_after_seconds 300

  @impl Oban.Worker
  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@stale_after_seconds, :second)

    case Jobs.stale_claimed(threshold) do
      [] ->
        :ok

      stale ->
        Enum.each(stale, fn job ->
          Jobs.release(job)
        end)

        Logger.warning("runners: released stale claims",
          count: length(stale),
          stale_after_seconds: @stale_after_seconds
        )

        :ok
    end
  end
end
