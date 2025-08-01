defmodule Tuist.MinioBucketCreator do
  @moduledoc false
  use Task

  require Logger

  def start_link(_) do
    Task.start_link(__MODULE__, :run, [])
  end

  def run do
    if not Tuist.Environment.dev_use_remote_storage?() do
      Process.sleep(3000)
      create_bucket()
    end
  end

  defp create_bucket do
    bucket_name = Tuist.Environment.s3_bucket_name()
    
    case ExAws.S3.put_bucket(bucket_name, "") |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Created MinIO bucket: #{bucket_name}")
        
      {:error, {:http_error, 409, _}} ->
        Logger.info("MinIO bucket already exists: #{bucket_name}")
        
      {:error, error} ->
        Logger.error("Failed to create MinIO bucket: #{inspect(error)}")
    end
  end
end