defmodule Tuist.Registry.Storage do
  @moduledoc """
  S3 helpers scoped to the registry bucket.

  All registry artifacts (manifests, source archives, package metadata, sync
  state) live under the `registry/` prefix of `Tuist.Environment.registry_bucket/0`.
  This module wraps the few `ExAws.S3` calls the registry needs so callers don't
  thread the bucket name explicitly.
  """

  alias ExAws.S3.Upload
  alias Tuist.Environment

  require Logger

  @exists_cache :registry_s3_exists_cache
  @exists_positive_ttl to_timeout(hour: 6)
  @exists_negative_ttl to_timeout(second: 30)

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {Cachex, :start_link, [@exists_cache, []]}
    }
  end

  def exists_cache_name, do: @exists_cache

  def presign_download_url(key) when is_binary(key) do
    case bucket() do
      nil ->
        {:error, :registry_disabled}

      bucket ->
        config = ExAws.Config.new(:s3)
        ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: 600)
    end
  end

  def remote_accel_path(url) when is_binary(url) do
    %URI{host: host, path: raw_path, query: query} = URI.parse(url)

    path = raw_path || "/"
    base = "/internal/remote/https/" <> host <> path

    case query do
      nil -> base
      "" -> base
      _ -> base <> "?" <> query
    end
  end

  def exists?(key) when is_binary(key) do
    case Cachex.get(@exists_cache, key) do
      {:ok, nil} ->
        case do_exists?(key) do
          {:ok, result} ->
            ttl = if result, do: @exists_positive_ttl, else: @exists_negative_ttl
            Cachex.put(@exists_cache, key, result, ttl: ttl)
            result

          {:error, reason} ->
            Logger.warning("Registry S3 exists check failed for #{key}: #{inspect(reason)}")
            false
        end

      {:ok, cached} ->
        cached
    end
  end

  defp do_exists?(key) do
    case bucket() do
      nil ->
        {:ok, false}

      bucket ->
        case head_object_status(bucket, key, http_opts: [receive_timeout: 2_000]) do
          :exists -> {:ok, true}
          :not_found -> {:ok, false}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def upload_file(key, local_path, opts \\ []) when is_binary(key) and is_binary(local_path) do
    content_type_opt = Keyword.get(opts, :content_type)
    bucket = bucket()

    upload_opts =
      if content_type_opt,
        do: [content_type: content_type_opt, timeout: 120_000, max_concurrency: 8],
        else: [timeout: 120_000, max_concurrency: 8]

    case local_path
         |> Upload.stream_file()
         |> ExAws.S3.upload(bucket, key, upload_opts)
         |> ExAws.request() do
      {:ok, _response} ->
        :ok

      {:error, {:http_error, 429, _}} ->
        {:error, :rate_limited}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def upload_content(key, content, opts \\ []) when is_binary(key) do
    content_type_opt = Keyword.get(opts, :content_type)
    bucket = bucket()
    put_opts = if content_type_opt, do: [content_type: content_type_opt], else: []

    case bucket
         |> ExAws.S3.put_object(key, content, put_opts)
         |> ExAws.request() do
      {:ok, _response} ->
        :ok

      {:error, {:http_error, 429, _}} ->
        {:error, :rate_limited}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_object(key) when is_binary(key) do
    case bucket()
         |> ExAws.S3.get_object(key)
         |> ExAws.request() do
      {:ok, %{body: body, headers: headers}} -> {:ok, body, etag_from_headers(headers)}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def put_object(key, body, opts \\ []) when is_binary(key) and is_binary(body) do
    bucket()
    |> ExAws.S3.put_object(key, body, opts)
    |> ExAws.request()
  end

  def delete_object(key) when is_binary(key) do
    bucket()
    |> ExAws.S3.delete_object(key)
    |> ExAws.request()
  end

  def head_object(key) when is_binary(key) do
    case bucket()
         |> ExAws.S3.head_object(key)
         |> ExAws.request() do
      {:ok, %{headers: headers}} -> {:ok, etag_from_headers(headers)}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_objects_v2(prefix) when is_binary(prefix) do
    bucket()
    |> ExAws.S3.list_objects_v2(prefix: prefix)
    |> ExAws.stream!()
  end

  def download_to_file(key, local_path) when is_binary(key) and is_binary(local_path) do
    bucket()
    |> ExAws.S3.download_file(key, local_path)
    |> ExAws.request()
  end

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

  defp head_object_status(bucket, key, request_opts) do
    case bucket
         |> ExAws.S3.head_object(key)
         |> ExAws.request(request_opts) do
      {:ok, _response} -> :exists
      {:error, {:http_error, 404, _}} -> :not_found
      {:error, {:http_error, 429, _}} -> {:error, :rate_limited}
      {:error, reason} -> {:error, reason}
    end
  end

  defp bucket, do: Environment.registry_bucket()
end
