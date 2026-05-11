defmodule Tuist.Runners.Workers.StaleClaimsWorker do
  @moduledoc """
  Releases soft-claimed `runner_dispatch_queue` rows whose
  `claimed_at` is older than the recovery threshold.

  A soft claim normally lives at most a few seconds: the time
  between `UPDATE … SET claimed_at` and the post-mint
  `finalize_claim` (DELETE). If the server crashes — or any of
  the steps between claim and finalize raises without hitting
  `release_claim` — the row would otherwise stay claimed
  forever, blocking the customer's slot.

  The threshold is generous (5 minutes) because the normal path
  is sub-second; anything stuck > 5 min is overwhelmingly likely
  to be a real failure rather than an in-flight mint.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners.DispatchQueue

  require Logger

  @stale_after_seconds 300

  @impl Oban.Worker
  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@stale_after_seconds, :second)
    released = DispatchQueue.release_stale_claims(threshold)

    if released > 0 do
      Logger.warning("runners: released stale claims",
        count: released,
        stale_after_seconds: @stale_after_seconds
      )
    end

    :ok
  end
end
