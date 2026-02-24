defmodule Cache.KeyValueEvictionWorker do
  @moduledoc """
  Oban worker that evicts key-value entries that haven't been accessed
  within the configured time window (default: 30 days).
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.CASCleanupWorker
  alias Cache.KeyValueEntries

  require Logger

  @cleanup_hashes_per_job 500

  @impl Oban.Worker
  def perform(_job) do
    max_age_days = Application.get_env(:cache, :key_value_eviction_max_age_days, 30)
    {expired_entries, count} = KeyValueEntries.delete_expired(max_age_days)
    Logger.info("Evicted #{count} expired key-value entries (older than #{max_age_days} days)")

    expired_entries
    |> group_hashes_by_scope()
    |> enqueue_cleanup_jobs()

    :ok
  end

  defp group_hashes_by_scope(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      case parse_cas_hashes(entry) do
        {account, project, hashes} ->
          Map.update(acc, {account, project}, MapSet.new(hashes), fn existing ->
            Enum.reduce(hashes, existing, &MapSet.put(&2, &1))
          end)

        :skip ->
          acc
      end
    end)
  end

  defp enqueue_cleanup_jobs(grouped_hashes) do
    Enum.each(grouped_hashes, fn {{account, project}, hash_set} ->
      hash_set
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.chunk_every(@cleanup_hashes_per_job)
      |> Enum.each(fn hashes ->
        case %{"account_handle" => account, "project_handle" => project, "cas_hashes" => hashes}
             |> CASCleanupWorker.new()
             |> Oban.insert() do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to enqueue CAS cleanup for #{account}/#{project}: #{inspect(reason)}")
        end
      end)
    end)
  end

  defp parse_cas_hashes(entry) do
    with ["keyvalue", account, project, _cas_id] <- String.split(entry.key, ":", parts: 4),
         {:ok, %{"entries" => [_ | _] = entries_list}} <- Jason.decode(entry.json_payload) do
      hashes =
        entries_list
        |> Enum.map(&Map.get(&1, "value"))
        |> Enum.reject(&is_nil/1)

      {account, project, hashes}
    else
      _ ->
        Logger.warning("Skipping CAS cleanup for entry with key: #{entry.key}")
        :skip
    end
  end
end
