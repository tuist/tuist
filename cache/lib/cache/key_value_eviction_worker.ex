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
    {grouped_hashes, count} = KeyValueEntries.delete_expired(max_age_days)
    Logger.info("Evicted #{count} expired key-value entries (older than #{max_age_days} days)")

    enqueue_cleanup_jobs(grouped_hashes)

    :ok
  end

  defp enqueue_cleanup_jobs(grouped_hashes) do
    Enum.each(grouped_hashes, fn {{account, project}, hashes} ->
      hashes
      |> Enum.chunk_every(@cleanup_hashes_per_job)
      |> Enum.each(fn chunk ->
        case %{"account_handle" => account, "project_handle" => project, "cas_hashes" => chunk}
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
end
