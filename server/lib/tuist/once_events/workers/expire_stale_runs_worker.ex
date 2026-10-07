defmodule Tuist.OnceEvents.Workers.ExpireStaleRunsWorker do
  @moduledoc """
  Marks Once runs that stopped reporting as `lost`.

  A cancelled CI job or a killed `once` process never sends `RunCompleted`,
  so without this the run stays `active` and the dashboard shows it as
  Running indefinitely. Mirrors
  `Tuist.Tests.Workers.ExpireStaleTestRunsWorker` for the shared test store.

  It then recounts the cache roll-ups of runs that finished recently, which
  settles any a deploy left incomplete. See
  `Tuist.OnceEvents.recount_recent_cache_rollups/1`.
  """
  use Oban.Worker

  alias Tuist.OnceEvents

  @impl Oban.Worker
  def perform(_args) do
    {:ok, _count} = OnceEvents.expire_stale_runs()
    {:ok, _count} = OnceEvents.recount_recent_cache_rollups()
    :ok
  end
end
