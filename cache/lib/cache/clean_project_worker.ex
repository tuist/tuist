defmodule Cache.CleanProjectWorker do
  @moduledoc """
  Oban worker that cleans all cache artifacts for a project from both disk and S3.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

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

    case S3.delete_all_with_prefix("#{account_handle}/#{project_handle}/") do
      {:ok, count} ->
        Logger.info("Cleaned #{count} S3 objects for project #{account_handle}/#{project_handle}")

      {:error, reason} ->
        Logger.error("Failed to clean S3 objects for project #{account_handle}/#{project_handle}: #{inspect(reason)}")
    end

    :ok
  end
end
