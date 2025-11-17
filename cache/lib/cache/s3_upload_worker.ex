defmodule Cache.S3UploadWorker do
  @moduledoc """
  Oban worker for uploading CAS artifacts to S3.
  """

  use Oban.Worker, queue: :s3_uploads, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Logger.info("Starting S3 upload for artifact: #{key}")

    local_path = Cache.Disk.artifact_path(key)

    case upload_to_s3(key, local_path) do
      :ok ->
        Logger.info("Successfully uploaded artifact to S3: #{key}")
        :ok

      {:error, reason} ->
        Appsignal.send_error(%RuntimeError{message: "Failed to upload artifact to S3"}, %{
          key: key,
          reason: reason
        })

        {:error, reason}
    end
  end

  def enqueue_upload(account_handle, project_handle, id) do
    key = Cache.Disk.cas_key(account_handle, project_handle, id)

    %{key: key}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp upload_to_s3(key, local_path) do
    bucket = Application.get_env(:cache, :s3)[:bucket]

    case local_path
         |> ExAws.S3.Upload.stream_file()
         |> ExAws.S3.upload(bucket, key)
         |> ExAws.request() do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
