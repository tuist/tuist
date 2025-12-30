defmodule Tuist.MinioBucketCreator do
  @moduledoc false
  use Task

  require Logger

  def start_link(_) do
    Task.start_link(__MODULE__, :run, [])
  end

  def run do
    if not Tuist.Environment.dev_use_remote_storage?() do
      wait_for_minio()
      create_bucket()
    end
  end

  defp wait_for_minio(retries \\ 30)

  defp wait_for_minio(0) do
    Logger.error("MinIO failed to start after 30 seconds")
  end

  defp wait_for_minio(retries) do
    if minio_ready?() do
      Logger.info("MinIO is ready")
    else
      Process.sleep(1000)
      wait_for_minio(retries - 1)
    end
  end

  defp minio_ready? do
    case ExAws.request(ExAws.S3.list_buckets()) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp create_bucket do
    bucket_name = Tuist.Environment.s3_bucket_name()

    case bucket_name |> ExAws.S3.put_bucket("") |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Created MinIO bucket: #{bucket_name}")

      {:error, {:http_error, 409, _}} ->
        Logger.info("MinIO bucket already exists: #{bucket_name}")

      {:error, error} ->
        Logger.error("Failed to create MinIO bucket: #{inspect(error)}")
    end
  end
end
