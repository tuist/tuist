defmodule Cache.KeyValueEvictionWorker do
  @moduledoc """
  Oban worker that evicts key-value entries that haven't been accessed
  within the configured time window (default: 30 days).
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.CASCleanupWorker
  alias Cache.KeyValueEntries

  require Logger

  @min_hash_length 4

  @impl Oban.Worker
  def perform(_job) do
    max_age_days = Application.get_env(:cache, :key_value_eviction_max_age_days, 30)
    {expired_entries, count} = KeyValueEntries.delete_expired(max_age_days)
    Logger.info("Evicted #{count} expired key-value entries (older than #{max_age_days} days)")

    Enum.each(expired_entries, &maybe_enqueue_cas_cleanup/1)

    :ok
  end

  defp maybe_enqueue_cas_cleanup(entry) do
    with ["keyvalue", account, project, _cas_id] <- String.split(entry.key, ":", parts: 4),
         {:ok, %{"entries" => [_ | _] = entries_list}} <- Jason.decode(entry.json_payload),
         hashes = entries_list |> Enum.map(&Map.get(&1, "value")) |> Enum.reject(&is_nil/1),
         valid_hashes = Enum.filter(hashes, &(String.length(&1) >= @min_hash_length)),
         true <- valid_hashes != [] do
      %{"account_handle" => account, "project_handle" => project, "cas_hashes" => valid_hashes}
      |> CASCleanupWorker.new()
      |> Oban.insert()
    else
      _ ->
        Logger.warning("Skipping CAS cleanup for entry with key: #{entry.key}")
        :ok
    end
  rescue
    error ->
      Logger.warning("Failed to parse CAS cleanup data for entry with key: #{entry.key}, error: #{inspect(error)}")
      :ok
  end
end
