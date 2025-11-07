defmodule Cache.S3DownloadWorker do
  @moduledoc """
  Oban worker for downloading CAS artifacts from S3 to disk.
  """

  use Oban.Worker, queue: :s3_downloads, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Logger.info("Starting S3 download for artifact: #{key}")

    if Cache.S3.exists?(key) do
      local_path = Cache.Disk.artifact_path(key)

      :ok = download_from_s3(key, local_path)
    else
      Logger.info("Artifact not found in S3, skipping download: #{key}")
      :ok
    end
  end

  def enqueue_download(account_handle, project_handle, id) do
    key = Cache.Disk.cas_key(account_handle, project_handle, id)

    %{key: key}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp download_from_s3(key, local_path) do
    bucket = Application.get_env(:cache, :s3)[:bucket]

    local_path |> Path.dirname() |> File.mkdir_p!()

    case bucket
         |> ExAws.S3.download_file(key, local_path)
         |> ExAws.request() do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
