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

  @exists_cache :s3_exists_cache
  @exists_positive_ttl to_timeout(hour: 6)
  @exists_negative_ttl to_timeout(second: 30)

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {Cachex, :start_link, [@exists_cache, []]}
    }
  end

  def exists_cache_name, do: @exists_cache

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
  Checks if an artifact exists in S3, with a Cachex caching layer.

  ## Options

    * `:type` - The storage type, either `:cache` (default) or `:registry`

  Returns `false` if type is `:registry` and registry storage is not configured.
  """
  def exists?(key, opts \\ []) when is_binary(key) do
    case Cachex.get(@exists_cache, key) do
      {:ok, nil} ->
        result = do_exists?(key, opts)
        ttl = if result, do: @exists_positive_ttl, else: @exists_negative_ttl
        Cachex.put(@exists_cache, key, result, ttl: ttl)
        result

      {:ok, cached} ->
        :telemetry.execute([:cache, :s3, :head], %{duration: 0}, %{result: :cache_hit})
        cached
    end
  end

  defp do_exists?(key, opts) do
    type = Keyword.get(opts, :type, :cache)

    case bucket_for_type(type) do
      nil ->
        false

      bucket ->
        {duration, result} =
          :timer.tc(fn ->
            bucket
            |> ExAws.S3.head_object(key)
            |> ExAws.request(http_opts: [receive_timeout: 2_000])
          end)

        case result do
          {:ok, _response} ->
            :telemetry.execute([:cache, :s3, :head], %{duration: duration}, %{result: :found})
            true

          {:error, {:http_error, 404, _}} ->
            :telemetry.execute([:cache, :s3, :head], %{duration: duration}, %{result: :not_found})
            false

          {:error, {:http_error, 429, _}} ->
            :telemetry.execute([:cache, :s3, :head], %{duration: duration}, %{result: :rate_limited})
            false

          {:error, _reason} ->
            :telemetry.execute([:cache, :s3, :head], %{duration: duration}, %{result: :error})
            false
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

    if File.exists?(local_path) do
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
    else
      Logger.warning("Local file not found for S3 upload: #{local_path}")
      :ok
    end
  end

  @doc """
  Downloads an artifact from S3 to local disk.

  ## Options

    * `:type` - The storage type, either `:cache` (default) or `:registry`

  Returns :ok on success, {:error, :rate_limited} on 429 errors (should be retried),
  or {:error, reason} on other failures.
  If the artifact does not exist in S3, returns {:ok, :miss}.
  """
  def download(key, opts \\ []) do
    type = Keyword.get(opts, :type, :cache)
    bucket = bucket_for_type(type)
    local_path = Cache.Disk.artifact_path(key)

    Logger.info("Starting S3 download for artifact: #{key}")

    {head_duration, head_result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.head_object(key)
        |> ExAws.request()
      end)

    case head_result do
      {:ok, _response} ->
        :telemetry.execute([:cache, :s3, :head], %{duration: head_duration}, %{result: :found})

        local_path |> Path.dirname() |> File.mkdir_p!()

        {dl_duration, dl_result} =
          :timer.tc(fn ->
            bucket
            |> ExAws.S3.download_file(key, local_path)
            |> ExAws.request()
          end)

        case dl_result do
          {:ok, :done} ->
            :telemetry.execute([:cache, :s3, :download], %{duration: dl_duration}, %{result: :ok})
            {:ok, :hit}

          {:error, {:http_error, 429, _}} ->
            :telemetry.execute([:cache, :s3, :download], %{duration: dl_duration}, %{result: :rate_limited})
            Logger.warning("S3 download rate limited for artifact: #{key}")
            {:error, :rate_limited}

          {:error, reason} ->
            :telemetry.execute([:cache, :s3, :download], %{duration: dl_duration}, %{result: :error})
            Logger.error("S3 download failed for artifact #{key}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, {:http_error, 404, _}} ->
        :telemetry.execute([:cache, :s3, :head], %{duration: head_duration}, %{result: :not_found})
        {:ok, :miss}

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:cache, :s3, :head], %{duration: head_duration}, %{result: :rate_limited})
        Logger.warning("S3 exists check rate limited for artifact: #{key}")
        {:error, :rate_limited}

      {:error, _reason} ->
        :telemetry.execute([:cache, :s3, :head], %{duration: head_duration}, %{result: :error})
        {:ok, :miss}
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

    {duration, result} = :timer.tc(fn -> list_and_delete_objects(bucket, prefix, 0) end)

    case result do
      {:ok, count} ->
        :telemetry.execute([:cache, :s3, :delete], %{duration: duration, count: count}, %{result: :ok})
        Logger.info("Successfully deleted #{count} objects from S3 with prefix: #{prefix}")
        {:ok, count}

      {:error, reason} = error ->
        :telemetry.execute([:cache, :s3, :delete], %{duration: duration, count: 0}, %{result: :error})
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

  @doc """
  Uploads a local file to S3 with streaming.

  ## Options

    * `:type` - The storage type, either `:cache` (default) or `:registry`
    * `:content_type` - The content type for the uploaded object

  Returns `:ok` on success, `{:error, :rate_limited}` on 429, or `{:error, reason}` on failure.
  """
  def upload_file(key, local_path, opts \\ []) when is_binary(key) and is_binary(local_path) do
    type = Keyword.get(opts, :type, :cache)
    content_type_opt = Keyword.get(opts, :content_type)

    bucket = bucket_for_type(type)

    upload_opts =
      if content_type_opt,
        do: [content_type: content_type_opt, timeout: 120_000, max_concurrency: 8],
        else: [timeout: 120_000, max_concurrency: 8]

    {duration, result} =
      :timer.tc(fn ->
        local_path
        |> Upload.stream_file()
        |> ExAws.S3.upload(bucket, key, upload_opts)
        |> ExAws.request()
      end)

    case result do
      {:ok, _response} ->
        :telemetry.execute([:cache, :s3, :upload], %{duration: duration}, %{result: :ok})
        :ok

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:cache, :s3, :upload], %{duration: duration}, %{result: :rate_limited})
        {:error, :rate_limited}

      {:error, reason} ->
        :telemetry.execute([:cache, :s3, :upload], %{duration: duration}, %{result: :error})
        {:error, reason}
    end
  end

  @doc """
  Uploads raw content to S3 as an object.

  ## Options

    * `:type` - The storage type, either `:cache` (default) or `:registry`
    * `:content_type` - The content type for the uploaded object

  Returns `:ok` on success, `{:error, :rate_limited}` on 429, or `{:error, reason}` on failure.
  """
  def upload_content(key, content, opts \\ []) when is_binary(key) do
    type = Keyword.get(opts, :type, :cache)
    content_type_opt = Keyword.get(opts, :content_type)

    bucket = bucket_for_type(type)
    put_opts = if content_type_opt, do: [content_type: content_type_opt], else: []

    {duration, result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.put_object(key, content, put_opts)
        |> ExAws.request()
      end)

    case result do
      {:ok, _response} ->
        :telemetry.execute([:cache, :s3, :upload], %{duration: duration}, %{result: :ok})
        :ok

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:cache, :s3, :upload], %{duration: duration}, %{result: :rate_limited})
        {:error, :rate_limited}

      {:error, reason} ->
        :telemetry.execute([:cache, :s3, :upload], %{duration: duration}, %{result: :error})
        {:error, reason}
    end
  end

  @doc """
  Extracts and normalizes the ETag value from S3 response headers.

  Handles both `"etag"` and `"ETag"` header keys, strips surrounding quotes,
  and unwraps list values.
  """
  def etag_from_headers(headers) when is_map(headers) do
    headers
    |> Map.get("etag", Map.get(headers, "ETag"))
    |> normalize_etag()
  end

  defp normalize_etag(nil), do: nil
  defp normalize_etag([value | _]), do: normalize_etag(value)

  defp normalize_etag(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp bucket_for_type(:cache), do: Config.cache_bucket()
  defp bucket_for_type(:registry), do: Config.registry_bucket()
end
