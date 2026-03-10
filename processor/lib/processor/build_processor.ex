defmodule Processor.BuildProcessor do
  @moduledoc false

  require Logger

  def process(storage_key) do
    bucket = Application.get_env(:processor, :s3_bucket, "tuist")

    case ExAws.S3.get_object(bucket, storage_key) |> ExAws.request() do
      {:ok, %{body: body}} ->
        process_archive(body)

      {:error, reason} ->
        Logger.error(
          "Failed to download build archive (storage_key: #{storage_key}): #{inspect(reason)}"
        )

        {:error, {:download_failed, reason}}
    end
  end

  def process_archive(archive_bytes) do
    case extract_archive(archive_bytes) do
      {:ok, temp_dir} ->
        try do
          with {:ok, xcactivitylog_path} <- find_xcactivitylog(temp_dir),
               cas_path = Path.join(temp_dir, "cas_metadata"),
               {:ok, parsed_data} <- parse_xcactivitylog(xcactivitylog_path, cas_path) do
            {:ok, parsed_data}
          else
            {:error, reason} ->
              Logger.error("Failed to process build archive: #{inspect(reason)}")
              {:error, reason}
          end
        after
          cleanup_temp(temp_dir)
        end

      {:error, reason} ->
        Logger.error("Failed to process build archive: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_archive(archive_bytes) do
    temp_dir = Path.join(System.tmp_dir!(), "processor_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(temp_dir)
    archive_path = Path.join(temp_dir, "archive.zip")
    File.write!(archive_path, archive_bytes)

    case :zip.unzip(~c"#{archive_path}", [{:cwd, ~c"#{temp_dir}"}]) do
      {:ok, _} -> {:ok, temp_dir}
      {:error, reason} -> {:error, {:unzip_failed, reason}}
    end
  end

  defp find_xcactivitylog(temp_dir) do
    xcactivitylog_dir = Path.join(temp_dir, "build_archive/xcactivitylog")

    case File.ls(xcactivitylog_dir) do
      {:ok, files} ->
        case Enum.find(files, &String.ends_with?(&1, ".xcactivitylog")) do
          nil -> {:error, :xcactivitylog_not_found}
          file -> {:ok, Path.join(xcactivitylog_dir, file)}
        end

      {:error, _} ->
        {:error, :xcactivitylog_dir_not_found}
    end
  end

  defp parse_xcactivitylog(xcactivitylog_path, cas_path) do
    case Processor.XCActivityLogNIF.parse(xcactivitylog_path, cas_path, true) do
      {:ok, parsed_data} -> {:ok, parsed_data}
      {:error, reason} -> {:error, {:parse_failed, reason}}
    end
  end

  defp cleanup_temp(nil), do: :ok

  defp cleanup_temp(temp_dir) do
    File.rm_rf(temp_dir)
    :ok
  end
end
