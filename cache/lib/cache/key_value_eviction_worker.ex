defmodule Cache.KeyValueEvictionWorker do
  @moduledoc """
  Oban worker that evicts key-value entries that haven't been accessed
  within the configured time window (default: 30 days).
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.KeyValueEntries

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    max_age_days = Application.get_env(:cache, :key_value_eviction_max_age_days, 30)
    {count, _} = KeyValueEntries.delete_expired(max_age_days)
    Logger.info("Evicted #{count} expired key-value entries (older than #{max_age_days} days)")
    :ok
  end
end
