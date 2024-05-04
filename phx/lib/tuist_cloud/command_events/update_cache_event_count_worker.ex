defmodule TuistCloud.CommandEvents.UpdateCacheEventCountWorker do
  @moduledoc """
  Worker that updates the cache event counts.
  """
  use Oban.Worker
  alias TuistCloud.CommandEvents

  @impl Oban.Worker
  def perform(_job) do
    # TODO - Make more optimal
    # It's causing DB timeouts due to slow queries
    # CommandEvents.update_cache_event_counts()

    :ok
  end
end
