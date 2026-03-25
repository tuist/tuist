defmodule Cache.ApplyProjectCleanupWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :clean,
    max_attempts: 5,
    unique: [keys: [:account_handle, :project_handle, :generation], period: 300]

  alias Cache.CleanProjectWorker
  alias Cache.DistributedKV.Cleanup

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "generation" => generation,
          "cutoff" => cutoff_iso
        }
      }) do
    {:ok, cutoff, _offset} = DateTime.from_iso8601(cutoff_iso)
    safe_cutoff = DateTime.truncate(cutoff, :second)

    if already_applied?(account_handle, project_handle, generation) do
      Logger.info("Skipping already-applied cleanup for #{account_handle}/#{project_handle} generation=#{generation}")

      :ok
    else
      case CleanProjectWorker.perform_local_node_cleanup(account_handle, project_handle, safe_cutoff, fn -> :ok end) do
        :ok ->
          :ok = Cleanup.put_local_applied_generation(account_handle, project_handle, generation)

          Logger.info(
            "Applied project cleanup for #{account_handle}/#{project_handle} " <>
              "generation=#{generation} cutoff=#{DateTime.to_iso8601(safe_cutoff)}"
          )

          :ok

        {:error, reason} = error ->
          Logger.error(
            "Failed to apply project cleanup for #{account_handle}/#{project_handle} " <>
              "generation=#{generation}: #{inspect(reason)}"
          )

          error
      end
    end
  end

  defp already_applied?(account_handle, project_handle, generation) do
    Cleanup.local_applied_generation(account_handle, project_handle) >= generation
  end
end
