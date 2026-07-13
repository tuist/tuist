defmodule TuistRegistry.S3 do
  @moduledoc """
  Object-storage helper functions for registry read paths.

  Isolated behind a module for easy testing without mutating global config.

  Registry metadata and artifacts are stored in the configured registry bucket.
  """

  import Cachex.Spec, only: [limit: 1]

  alias TuistRegistry.Config

  require Logger

  @exists_cache :s3_exists_cache
  @exists_negative_ttl to_timeout(second: 30)

  def child_spec(_) do
    %{
      id: __MODULE__,
      start:
        {Cachex, :start_link, [@exists_cache, [limit: limit(size: 500_000, policy: Cachex.Policy.LRW, reclaim: 0.1)]]}
    }
  end

  def exists_cache_name, do: @exists_cache

  @doc """
  Generates a presigned download URL for an artifact.

  ## Options

    * `:type` - The storage type. Only `:registry` is supported.

  Returns `{:ok, url}` on success or `{:error, reason}` on failure.
  Returns `{:error, :registry_disabled}` if type is `:registry` and registry storage is not configured.
  """
  def presign_download_url(key, opts \\ []) when is_binary(key) do
    type = Keyword.get(opts, :type, :registry)

    case bucket_for_type(type) do
      nil ->
        {:error, :registry_disabled}

      bucket ->
        config = ExAws.Config.new(:s3)
        ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: 600)
    end
  end

  @doc """
  Fetches an object from S3 into memory.

  Intended for small objects like Package.swift manifests where we want to
  inject response headers (e.g. `Link` for alternate manifests) before
  returning the body to the caller, which a 307 redirect to a presigned URL
  cannot deliver.

  ## Options

    * `:type` - The storage type. Only `:registry` is supported.

  Returns `{:ok, body}` on success, `{:error, :not_found}` if the object is
  missing, or `{:error, reason}` on other failures.
  """
  def get_object(key, opts \\ []) when is_binary(key) do
    type = Keyword.get(opts, :type, :registry)

    case bucket_for_type(type) do
      nil ->
        {:error, :registry_disabled}

      bucket ->
        case bucket |> ExAws.S3.get_object(key) |> ExAws.request() do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, body}

          {:ok, %{status_code: 404}} ->
            {:error, :not_found}

          {:ok, %{status_code: status}} ->
            {:error, {:s3_error, status}}

          {:error, {:http_error, 404, _}} ->
            {:error, :not_found}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Lists object keys with the given prefix.

  ## Options

    * `:type` - The storage type. Only `:registry` is supported.

  Returns `{:ok, keys}` on success, `{:error, reason}` on failure.
  """
  def list_objects(prefix, opts \\ []) when is_binary(prefix) do
    type = Keyword.get(opts, :type, :registry)

    case bucket_for_type(type) do
      nil ->
        {:error, :registry_disabled}

      bucket ->
        {duration, result} =
          :timer.tc(fn ->
            try do
              keys =
                bucket
                |> ExAws.S3.list_objects_v2(prefix: prefix)
                |> ExAws.stream!()
                |> Enum.map(& &1.key)

              {:ok, keys}
            rescue
              error -> {:error, error}
            catch
              :exit, reason -> {:error, reason}
            end
          end)

        case result do
          {:ok, keys} ->
            :telemetry.execute([:tuist_registry, :s3, :list], %{duration: duration, count: length(keys)}, %{
              result: :ok
            })

            {:ok, keys}

          {:error, reason} ->
            :telemetry.execute([:tuist_registry, :s3, :list], %{duration: duration, count: 0}, %{result: :error})
            {:error, reason}
        end
    end
  end

  @doc """
  Checks if an artifact exists in S3, with a short negative Cachex caching layer.

  Positive results are not cached because purge runs from the server sync
  runtime and cannot invalidate per-pod read-side caches.

  ## Options

    * `:type` - The storage type. Only `:registry` is supported.

  Returns `false` if type is `:registry` and registry storage is not configured.
  """
  def exists?(key, opts \\ []) when is_binary(key) do
    type = Keyword.get(opts, :type, :registry)
    cache_key = {type, key}

    case Cachex.get(@exists_cache, cache_key) do
      {:ok, nil} ->
        case do_exists?(key, opts) do
          {:ok, true} ->
            true

          {:ok, false} ->
            Cachex.put(@exists_cache, cache_key, false, ttl: @exists_negative_ttl)
            false

          {:error, reason} ->
            Logger.warning("S3 exists check failed for artifact #{key}: #{inspect(reason)}")
            false
        end

      {:ok, cached} ->
        :telemetry.execute([:tuist_registry, :s3, :head], %{duration: 0}, %{result: :cache_hit})
        cached
    end
  end

  defp do_exists?(key, opts) do
    type = Keyword.get(opts, :type, :registry)

    case bucket_for_type(type) do
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

  defp bucket_for_type(:registry), do: Config.registry_bucket()
  defp bucket_for_type(_type), do: Config.registry_bucket()

  defp head_object_status(bucket, key, request_opts) do
    {duration, result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.head_object(key)
        |> ExAws.request(request_opts)
      end)

    case result do
      {:ok, _response} ->
        :telemetry.execute([:tuist_registry, :s3, :head], %{duration: duration}, %{result: :found})
        :exists

      {:error, {:http_error, 404, _}} ->
        :telemetry.execute([:tuist_registry, :s3, :head], %{duration: duration}, %{result: :not_found})
        :not_found

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:tuist_registry, :s3, :head], %{duration: duration}, %{result: :rate_limited})
        {:error, :rate_limited}

      {:error, reason} ->
        :telemetry.execute([:tuist_registry, :s3, :head], %{duration: duration}, %{result: :error})
        {:error, reason}
    end
  end
end
