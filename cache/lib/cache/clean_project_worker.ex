defmodule Cache.CleanProjectWorker do
  @moduledoc """
  Oban worker that cleans all cache artifacts for a project from both disk and S3.
  """

  use Oban.Worker, queue: :clean, max_attempts: 3

  alias Cache.Config
  alias Cache.Disk
  alias Cache.S3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}) do
    case Disk.delete_project(account_handle, project_handle) do
      :ok ->
        Logger.info("Cleaned disk cache for project #{account_handle}/#{project_handle}")

      {:error, reason} ->
        Logger.error("Failed to clean disk cache for project #{account_handle}/#{project_handle}: #{inspect(reason)}")
    end

    if Config.xcode_cache_bucket() do
      delete_s3_artifacts(account_handle, project_handle, :xcode_cache, "xcode cache")
    end

    delete_s3_artifacts(account_handle, project_handle, :cache, "cache")

    :ok
  end

  defp delete_s3_artifacts(account_handle, project_handle, type, label) do
    prefix = "#{account_handle}/#{project_handle}/"

    case S3.delete_all_with_prefix(prefix, type: type) do
      {:ok, count} ->
        Logger.info("Cleaned #{count} S3 #{label} objects with prefix #{prefix}")

      {:error, reason} ->
        Logger.error("Failed to clean S3 #{label} objects with prefix #{prefix}: #{inspect(reason)}")
    end
  end
end
