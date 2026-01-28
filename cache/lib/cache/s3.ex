defmodule Cache.S3 do
  @moduledoc """
  S3 helper functions for presigned URLs, uploads, and downloads.

  Isolated behind a module for easy testing without mutating global config.

  This module operates on the cache bucket (CAS and module artifacts).
  For registry-specific operations, use the registry-prefixed functions.
  """

  alias Cache.Config
  alias ExAws.S3.Upload

  require Logger

  @doc """
  Generates a presigned download URL for an artifact.

  ## Options

    * `:type` - The storage type, either `:cache` (default) or `:registry`

  Returns `{:ok, url}` on success or `{:error, reason}` on failure.
  Returns `{:error, :registry_disabled}` if type is `:registry` and registry storage is not configured.
  """
  def presign_download_url(key, opts \\ []) when is_binary(key) do
    type = Keyword.get(opts, :type, :cache)

    case bucket_for_type(type) do
      nil ->
        {:error, :registry_disabled}

      bucket ->
        config = ExAws.Config.new(:s3)
        ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: 600)
    end
  end

  @doc """
  Build the internal X-Accel-Redirect path used by nginx to proxy a remote URL.

  Always uses https and excludes any explicit port.

  Returns a path of the form:
    /internal/remote/https/<host>/<path>?<query>
  """
  def remote_accel_path(url) when is_binary(url) do
    %URI{host: host, path: path, query: query} = URI.parse(url)

    path = path || "/"

    base = "/internal/remote/https/" <> host <> path

    case query do
      nil -> base
      "" -> base
      _ -> base <> "?" <> query
    end
  end

  @doc """
  Checks if an artifact exists in S3.

  ## Options

    * `:type` - The storage type, either `:cache` (default) or `:registry`

  Returns `false` if type is `:registry` and registry storage is not configured.
  """
  def exists?(key, opts \\ []) when is_binary(key) do
    type = Keyword.get(opts, :type, :cache)

    case bucket_for_type(type) do
      nil ->
        false

      bucket ->
        case bucket
             |> ExAws.S3.head_object(key)
             |> ExAws.request(http_opts: [receive_timeout: 2_000]) do
          {:ok, _response} -> true
          {:error, {:http_error, 404, _}} -> false
          {:error, _reason} -> false
        end
    end
  end

  @doc """
  Uploads an artifact to S3.

  Returns :ok on success, {:error, :rate_limited} on 429 errors (should be retried),
  or {:error, reason} on other failures.
  If the local file does not exist, returns :ok (the file may have been evicted).
  """
  def upload(key) do
    local_path = Cache.Disk.artifact_path(key)

    Logger.info("Starting S3 upload for artifact: #{key}")

    case upload_file(key, local_path) do
      :ok ->
        Logger.info("Successfully uploaded artifact to S3: #{key}")
        :ok

      {:error, :rate_limited} = error ->
        Logger.warning("S3 upload rate limited for artifact: #{key}")
        error

      {:error, reason} = error ->
        Logger.error("S3 upload failed for artifact #{key}: #{inspect(reason)}")
        error
    end
  end

  defp upload_file(key, local_path) do
    if File.exists?(local_path) do
      bucket = Config.cache_bucket()

      case local_path
           |> Upload.stream_file()
           |> ExAws.S3.upload(bucket, key, timeout: 120_000)
           |> ExAws.request() do
        {:ok, _response} ->
          :ok

        {:error, {:http_error, 429, _}} ->
          {:error, :rate_limited}

        {:error, reason} ->
          {:error, reason}
      end
    else
      Logger.warning("Local file not found for S3 upload: #{local_path}")
      :ok
    end
  end

  @doc """
  Downloads an artifact from S3 to local disk.

  Returns :ok on success, {:error, :rate_limited} on 429 errors (should be retried),
  or {:error, reason} on other failures.
  If the artifact does not exist in S3, returns {:ok, :miss}.
  """
  def download(key) do
    Logger.info("Starting S3 download for artifact: #{key}")

    case check_exists(key) do
      {:ok, true} ->
        local_path = Cache.Disk.artifact_path(key)

        case download_file(key, local_path) do
          :ok ->
            {:ok, :hit}

          {:error, :rate_limited} = error ->
            Logger.warning("S3 download rate limited for artifact: #{key}")
            error

          {:error, reason} ->
            Logger.error("S3 download failed for artifact #{key}: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, false} ->
        Logger.info("Artifact not found in S3, skipping download: #{key}")
        {:ok, :miss}

      {:error, :rate_limited} = error ->
        Logger.warning("S3 exists check rate limited for artifact: #{key}")
        error
    end
  end

  defp check_exists(key) do
    bucket = Config.cache_bucket()

    case bucket
         |> ExAws.S3.head_object(key)
         |> ExAws.request() do
      {:ok, _response} -> {:ok, true}
      {:error, {:http_error, 404, _}} -> {:ok, false}
      {:error, {:http_error, 429, _}} -> {:error, :rate_limited}
      {:error, _reason} -> {:ok, false}
    end
  end

  defp download_file(key, local_path) do
    bucket = Config.cache_bucket()

    local_path |> Path.dirname() |> File.mkdir_p!()

    case bucket
         |> ExAws.S3.download_file(key, local_path)
         |> ExAws.request() do
      {:ok, :done} ->
        :ok

      {:error, {:http_error, 429, _}} ->
        {:error, :rate_limited}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes all objects with the given prefix from S3 (cache bucket).

  Lists all objects matching the prefix and deletes them in batches.
  Returns {:ok, deleted_count} on success, or {:error, reason} on failure.
  """
  def delete_all_with_prefix(prefix) do
    bucket = Config.cache_bucket()

    Logger.info("Deleting all S3 objects with prefix: #{prefix}")

    case list_and_delete_objects(bucket, prefix, 0) do
      {:ok, count} ->
        Logger.info("Successfully deleted #{count} objects from S3 with prefix: #{prefix}")
        {:ok, count}

      {:error, reason} = error ->
        Logger.error("Failed to delete S3 objects with prefix #{prefix}: #{inspect(reason)}")
        error
    end
  end

  defp list_and_delete_objects(bucket, prefix, acc) do
    bucket
    |> ExAws.S3.list_objects(prefix: prefix)
    |> ExAws.stream!()
    |> Stream.map(& &1.key)
    |> Stream.chunk_every(1000)
    |> Enum.reduce_while({:ok, acc}, fn keys, {:ok, count} ->
      case bucket
           |> ExAws.S3.delete_multiple_objects(keys)
           |> ExAws.request() do
        {:ok, _} ->
          {:cont, {:ok, count + length(keys)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp bucket_for_type(:cache), do: Config.cache_bucket()
  defp bucket_for_type(:registry), do: Config.registry_bucket()
end
