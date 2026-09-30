defmodule Tuist.OnceEvents.Workers.ExpireStaleRunsWorker do
  @moduledoc """
  Marks Once runs that stopped reporting as `lost`.

  A cancelled CI job or a killed `once` process never sends `RunCompleted`,
  so without this the run stays `active` and the dashboard shows it as
  Running indefinitely. Mirrors
  `Tuist.Tests.Workers.ExpireStaleTestRunsWorker` for the shared test store.
  """
  use Oban.Worker

  alias Tuist.OnceEvents

  @impl Oban.Worker
  def perform(_args) do
    {:ok, _count} = OnceEvents.expire_stale_runs()
    :ok
  end
end
