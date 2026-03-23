defmodule Cache.XcodeCleanupWorker do
  @moduledoc """
  Oban worker that deletes explicit Xcode cache artifacts from disk and metadata.
  """
  use Oban.Worker,
    queue: :clean,
    max_attempts: 3,
    unique: [keys: [:account_handle, :project_handle, :cas_hashes], period: 300]

  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.Xcode

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"account_handle" => account_handle, "project_handle" => project_handle, "cas_hashes" => cas_hashes}
      }) do
    keys = Enum.map(cas_hashes, &Xcode.Disk.key(account_handle, project_handle, &1))

    {deleted_keys, failed_count} = delete_from_disk(keys)

    if deleted_keys != [], do: delete_from_metadata(deleted_keys)

    if failed_count > 0,
      do: {:error, {:disk_delete_failed, failed_count}},
      else: :ok
  end

  defp delete_from_disk(keys) do
    {deleted_acc, failed_count} =
      Enum.reduce(keys, {[], 0}, fn key, {deleted_acc, failed_acc} ->
        case Disk.delete_artifact(key) do
          :ok ->
            {[key | deleted_acc], failed_acc}

          {:error, :enoent} ->
            {[key | deleted_acc], failed_acc}

          {:error, reason} ->
            Logger.error("Failed to delete Xcode cache artifact from disk #{key}: #{inspect(reason)}")
            {deleted_acc, failed_acc + 1}
        end
      end)

    {Enum.reverse(deleted_acc), failed_count}
  end

  defp delete_from_metadata(keys) do
    CacheArtifacts.delete_by_keys(keys)
  end
end
