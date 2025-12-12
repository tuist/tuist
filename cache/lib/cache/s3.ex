defmodule Cache.S3 do
  @moduledoc """
  S3 helper functions for presigned URLs, uploads, and downloads.

  Isolated behind a module for easy testing without mutating global config.
  """

  require Logger

  def presign_download_url(key) when is_binary(key) do
    bucket = Application.get_env(:cache, :s3)[:bucket]
    config = ExAws.Config.new(:s3)
    ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: 600)
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

  def exists?(key) when is_binary(key) do
    bucket = Application.get_env(:cache, :s3)[:bucket]

    case bucket
         |> ExAws.S3.head_object(key)
         |> ExAws.request(http_opts: [recv_timeout: 2_000]) do
      {:ok, _response} -> true
      {:error, {:http_error, 404, _}} -> false
      {:error, _reason} -> false
    end
  end

  @doc """
  Uploads an artifact to S3.

  Returns :ok on success, {:error, :rate_limited} on 429 errors (should be retried),
  or {:error, reason} on other failures.
  If the local file does not exist, returns :ok (the file may have been evicted).

  Supports both CAS artifacts and module cache artifacts. Module cache artifacts
  are identified by an artifact_id starting with "module::".
  """
  def upload(account_handle, project_handle, "module::" <> rest) do
    [category, hash, name] = String.split(rest, "::", parts: 3)
    key = Cache.Disk.module_key(account_handle, project_handle, category, hash, name)
    local_path = Cache.Disk.artifact_path(key)

    Logger.info("Starting S3 upload for module artifact: #{key}")

    case upload_file(key, local_path) do
      :ok ->
        Logger.info("Successfully uploaded module artifact to S3: #{key}")
        :ok

      {:error, :rate_limited} = error ->
        Logger.warning("S3 upload rate limited for module artifact: #{key}")
        error

      {:error, reason} = error ->
        Logger.error("S3 upload failed for module artifact #{key}: #{inspect(reason)}")
        error
    end
  end

  def upload(account_handle, project_handle, artifact_id) do
    key = Cache.Disk.cas_key(account_handle, project_handle, artifact_id)
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
      bucket = Application.get_env(:cache, :s3)[:bucket]

      case local_path
           |> ExAws.S3.Upload.stream_file()
           |> ExAws.S3.upload(bucket, key)
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
  If the artifact does not exist in S3, returns :ok (nothing to download).

  Supports both CAS artifacts and module cache artifacts. Module cache artifacts
  are identified by an artifact_id starting with "module::".
  """
  def download(account_handle, project_handle, "module::" <> rest) do
    [category, hash, name] = String.split(rest, "::", parts: 3)
    key = Cache.Disk.module_key(account_handle, project_handle, category, hash, name)
    Logger.info("Starting S3 download for module artifact: #{key}")

    case check_exists(key) do
      {:ok, true} ->
        local_path = Cache.Disk.artifact_path(key)

        case download_file(key, local_path) do
          :ok ->
            {:ok, %{size: size}} = Cache.Disk.module_stat(account_handle, project_handle, category, hash, name)

            :telemetry.execute([:cache, :module, :download, :s3_hit], %{size: size}, %{
              category: category,
              hash: hash,
              name: name,
              account_handle: account_handle,
              project_handle: project_handle
            })

            :ok

          {:error, :rate_limited} = error ->
            Logger.warning("S3 download rate limited for module artifact: #{key}")
            error

          {:error, reason} ->
            Logger.error("S3 download failed for module artifact #{key}: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, false} ->
        :telemetry.execute([:cache, :module, :download, :s3_miss], %{}, %{
          category: category,
          hash: hash,
          name: name,
          account_handle: account_handle,
          project_handle: project_handle
        })

        Logger.info("Module artifact not found in S3, skipping download: #{key}")
        :ok

      {:error, :rate_limited} = error ->
        Logger.warning("S3 exists check rate limited for module artifact: #{key}")
        error
    end
  end

  def download(account_handle, project_handle, artifact_id) do
    key = Cache.Disk.cas_key(account_handle, project_handle, artifact_id)
    Logger.info("Starting S3 download for artifact: #{key}")

    case check_exists(key) do
      {:ok, true} ->
        local_path = Cache.Disk.artifact_path(key)

        case download_file(key, local_path) do
          :ok ->
            {:ok, %{size: size}} = Cache.Disk.stat(account_handle, project_handle, artifact_id)

            :telemetry.execute([:cache, :cas, :download, :s3_hit], %{size: size}, %{
              cas_id: artifact_id,
              account_handle: account_handle,
              project_handle: project_handle
            })

            :ok

          {:error, :rate_limited} = error ->
            Logger.warning("S3 download rate limited for artifact: #{key}")
            error

          {:error, reason} ->
            Logger.error("S3 download failed for artifact #{key}: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, false} ->
        :telemetry.execute([:cache, :cas, :download, :s3_miss], %{}, %{
          cas_id: artifact_id,
          account_handle: account_handle,
          project_handle: project_handle
        })

        Logger.info("Artifact not found in S3, skipping download: #{key}")
        :ok

      {:error, :rate_limited} = error ->
        Logger.warning("S3 exists check rate limited for artifact: #{key}")
        error
    end
  end

  defp check_exists(key) do
    bucket = Application.get_env(:cache, :s3)[:bucket]

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
    bucket = Application.get_env(:cache, :s3)[:bucket]

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
end
