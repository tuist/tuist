defmodule TuistCloud.CommandEvents.UpdateCacheEventCountWorker do
  @moduledoc """
  Worker that updates the cache event counts.
  """
  use Oban.Worker
  alias TuistCloud.CommandEvents

  @impl Oban.Worker
  def perform(_job) do
    CommandEvents.update_cache_event_counts()

    :ok
  end
end
