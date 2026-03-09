defmodule Processor.BuildProcessor do
  @moduledoc false

  require Logger

  def process(storage_key, account_id) do
    with {:ok, temp_dir} <- download_and_extract(storage_key, account_id),
         {:ok, manifest} <- read_manifest(temp_dir),
         {:ok, xcactivitylog_path} <- find_xcactivitylog(temp_dir),
         cas_path = Path.join(temp_dir, "cas_metadata"),
         {:ok, parsed_data} <- parse_xcactivitylog(xcactivitylog_path, cas_path, manifest) do
      cleanup_temp(temp_dir)
      {:ok, parsed_data}
    else
      {:error, reason} ->
        Logger.error("Failed to process build (storage_key: #{storage_key}): #{inspect(reason)}")
        cleanup_temp(nil)
        {:error, reason}
    end
  end

  defp download_and_extract(storage_key, _account_id) do
    temp_dir = Path.join(System.tmp_dir!(), "processor_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(temp_dir)
    archive_path = Path.join(temp_dir, "archive.zip")

    bucket = Application.get_env(:processor, :s3_bucket, "tuist")

    case ExAws.S3.get_object(bucket, storage_key) |> ExAws.request() do
      {:ok, %{body: body}} ->
        File.write!(archive_path, body)

        case :zip.unzip(~c"#{archive_path}", [{:cwd, ~c"#{temp_dir}"}]) do
          {:ok, _} -> {:ok, temp_dir}
          {:error, reason} -> {:error, {:unzip_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end

  defp read_manifest(temp_dir) do
    manifest_path = Path.join(temp_dir, "build_archive/manifest.json")

    if File.exists?(manifest_path) do
      case File.read(manifest_path) do
        {:ok, content} -> Jason.decode(content)
        {:error, reason} -> {:error, {:manifest_read_failed, reason}}
      end
    else
      {:ok, %{}}
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

  defp parse_xcactivitylog(xcactivitylog_path, cas_path, manifest) do
    cache_upload_enabled = Map.get(manifest, "cache_upload_enabled", false)

    case Processor.XCActivityLogNIF.parse(xcactivitylog_path, cas_path, cache_upload_enabled) do
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
