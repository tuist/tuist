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

    expired_entries
    |> Enum.flat_map(&parse_cas_hashes/1)
    |> Enum.group_by(fn {account, project, _hash} -> {account, project} end)
    |> Enum.each(fn {{account, project}, entries} ->
      hashes = entries |> Enum.map(fn {_, _, hash} -> hash end) |> Enum.uniq()

      case %{"account_handle" => account, "project_handle" => project, "cas_hashes" => hashes}
           |> CASCleanupWorker.new()
           |> Oban.insert() do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to enqueue CAS cleanup for #{account}/#{project}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  defp parse_cas_hashes(entry) do
    with ["keyvalue", account, project, _cas_id] <- String.split(entry.key, ":", parts: 4),
         {:ok, %{"entries" => [_ | _] = entries_list}} <- Jason.decode(entry.json_payload) do
      entries_list
      |> Enum.map(&Map.get(&1, "value"))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(String.length(&1) >= @min_hash_length))
      |> Enum.map(fn hash -> {account, project, hash} end)
    else
      _ ->
        Logger.warning("Skipping CAS cleanup for entry with key: #{entry.key}")
        []
    end
  rescue
    error ->
      Logger.warning("Failed to parse CAS cleanup data for entry with key: #{entry.key}, error: #{inspect(error)}")

      []
  end
end
