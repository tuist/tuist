defmodule TuistRegistry.Swift.Metadata do
  @moduledoc """
  Read-side cache and object-storage wrapper for Swift package registry metadata.

  The shared metadata contract lives in `TuistCommon.Registry.Swift.Metadata`;
  this module only owns the registry runtime's cache and read calls.
  """

  alias TuistCommon.Registry.Swift.KeyNormalizer
  alias TuistCommon.Registry.Swift.Metadata, as: MetadataContract
  alias TuistRegistry.Config
  alias TuistRegistry.S3

  require Logger

  @cache_name :registry_metadata_cache
  @ttl to_timeout(minute: 10)
  @revalidate_interval_seconds 60

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Cachex, :start_link, [cache_name(), []]}
    }
  end

  def cache_name, do: @cache_name

  @doc """
  Fetches package metadata from cache or S3.

  Returns `{:ok, metadata_map}` on success, `{:error, :not_found}` if the package
  doesn't exist in S3. Returned metadata is sanitized so only valid normalized
  storage versions remain in `releases` and `skipped_releases`.

  ## Options

    * `:fresh` - when true, bypasses the cache and reads from S3 directly.
  """
  def get_package(scope, name, opts \\ []) do
    fresh = Keyword.get(opts, :fresh, false)
    cache_name = Keyword.get(opts, :cache_name, cache_name())
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)
    cache_key = cache_key(scope, name)

    if fresh do
      fetch_from_s3(scope, name, cache_key, cache_name)
    else
      case Cachex.get(cache_name, cache_key) do
        {:ok, nil} ->
          fetch_from_s3(scope, name, cache_key, cache_name)

        {:ok, %{metadata: metadata} = cached} ->
          sanitized_metadata = MetadataContract.sanitize_package(metadata)
          cached = maybe_cache_sanitized_metadata(cache_name, cache_key, cached, sanitized_metadata)
          maybe_revalidate(scope, name, cache_key, cached, sanitized_metadata, cache_name)

        _ ->
          fetch_from_s3(scope, name, cache_key, cache_name)
      end
    end
  end

  @doc """
  Lists all package metadata keys in S3.

  Returns a list of `{scope, name}` tuples for all packages stored in S3.
  Used for cache registry sync and diagnostics.
  """
  def list_all_packages do
    prefix = "registry/metadata/"

    case S3.list_objects(prefix) do
      {:ok, keys} ->
        keys
        |> Stream.filter(&String.ends_with?(&1, "/index.json"))
        |> Stream.map(&MetadataContract.parse_s3_key/1)
        |> Stream.reject(&is_nil/1)
        |> Enum.to_list()

      {:error, reason} ->
        Logger.warning("S3 error listing metadata packages: #{inspect(reason)}")
        []
    end
  end

  defp fetch_from_s3(scope, name, cache_key, cache_name) do
    key = MetadataContract.s3_key(scope, name)
    bucket = bucket()

    {duration, result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.get_object(key)
        |> ExAws.request()
      end)

    case result do
      {:ok, %{body: body, headers: headers}} ->
        :telemetry.execute([:tuist_registry, :s3, :get], %{duration: duration}, %{result: :ok})

        case MetadataContract.decode_package(body) do
          {:ok, metadata} ->
            etag = S3.etag_from_headers(headers)
            Cachex.put(cache_name, cache_key, cache_value(metadata, etag), ttl: @ttl)
            {:ok, metadata}

          {:error, _reason} ->
            {:error, :not_found}
        end

      {:error, {:http_error, 404, _}} ->
        :telemetry.execute([:tuist_registry, :s3, :get], %{duration: duration}, %{result: :not_found})
        {:error, :not_found}

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:tuist_registry, :s3, :get], %{duration: duration}, %{result: :rate_limited})
        {:error, {:s3_error, :rate_limited}}

      {:error, reason} ->
        :telemetry.execute([:tuist_registry, :s3, :get], %{duration: duration}, %{result: :error})
        Logger.warning("S3 error fetching metadata for #{scope}/#{name}: #{inspect(reason)}")
        {:error, {:s3_error, reason}}
    end
  end

  defp maybe_revalidate(scope, name, cache_key, cached, metadata, cache_name) do
    case Map.get(cached, :checked_at) do
      %DateTime{} = checked_at ->
        if DateTime.diff(DateTime.utc_now(), checked_at) >= @revalidate_interval_seconds do
          revalidate_cached(scope, name, cache_key, cached, metadata, cache_name)
        else
          {:ok, metadata}
        end

      _ ->
        revalidate_cached(scope, name, cache_key, cached, metadata, cache_name)
    end
  end

  defp revalidate_cached(scope, name, cache_key, cached, metadata, cache_name) do
    cached_etag = Map.get(cached, :etag)

    case head_etag(scope, name) do
      {:ok, ^cached_etag} when is_binary(cached_etag) ->
        Cachex.put(cache_name, cache_key, cache_value(metadata, cached_etag), ttl: @ttl)
        {:ok, metadata}

      {:ok, _etag} ->
        fetch_from_s3(scope, name, cache_key, cache_name)

      {:error, :not_found} ->
        Cachex.del(cache_name, cache_key)
        {:error, :not_found}

      {:error, _reason} ->
        {:ok, metadata}
    end
  end

  defp head_etag(scope, name) do
    key = MetadataContract.s3_key(scope, name)
    bucket = bucket()

    {duration, result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.head_object(key)
        |> ExAws.request()
      end)

    case result do
      {:ok, %{headers: headers}} ->
        :telemetry.execute([:tuist_registry, :s3, :head], %{duration: duration}, %{result: :found})
        {:ok, S3.etag_from_headers(headers)}

      {:error, {:http_error, 404, _}} ->
        :telemetry.execute([:tuist_registry, :s3, :head], %{duration: duration}, %{result: :not_found})
        {:error, :not_found}

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:tuist_registry, :s3, :head], %{duration: duration}, %{result: :rate_limited})
        {:error, {:s3_error, :rate_limited}}

      {:error, reason} ->
        :telemetry.execute([:tuist_registry, :s3, :head], %{duration: duration}, %{result: :error})
        {:error, reason}
    end
  end

  defp cache_key(scope, name), do: {scope, name}

  defp bucket, do: Config.registry_bucket()

  defp cache_value(metadata, etag) do
    %{
      metadata: metadata,
      etag: etag,
      checked_at: DateTime.truncate(DateTime.utc_now(), :second)
    }
  end

  defp maybe_cache_sanitized_metadata(cache_name, cache_key, cached, sanitized_metadata) do
    if sanitized_metadata == cached.metadata do
      cached
    else
      sanitized_cached = %{cached | metadata: sanitized_metadata}
      Cachex.put(cache_name, cache_key, sanitized_cached, ttl: @ttl)
      sanitized_cached
    end
  end
end
