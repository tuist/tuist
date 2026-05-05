defmodule Tuist.Registry.Metadata do
  @moduledoc """
  Schema and functions for registry package metadata stored as JSON in S3.

  Metadata is stored at `registry/metadata/{scope}/{name}/index.json` in the
  registry bucket. See `Tuist.Registry.KeyNormalizer` for the storage key
  format used for releases and manifests.

  ## JSON shape

  ```json
  {
    "scope": "string",
    "name": "string",
    "repository_full_handle": "string",
    "releases": {
      "<version>": {
        "checksum": "sha256 hex",
        "manifests": [
          {"swift_version": "string | null", "swift_tools_version": "string | null"}
        ]
      }
    },
    "skipped_releases": {
      "<version>": {"reason": "string"}
    },
    "updated_at": "ISO8601"
  }
  ```
  """

  alias Tuist.Registry.KeyNormalizer
  alias Tuist.Registry.Storage

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
          sanitized_metadata = sanitize_package(metadata)
          cached = maybe_cache_sanitized_metadata(cache_name, cache_key, cached, sanitized_metadata)
          maybe_revalidate(scope, name, cache_key, cached, sanitized_metadata, cache_name)

        _ ->
          fetch_from_s3(scope, name, cache_key, cache_name)
      end
    end
  end

  def put_package(scope, name, metadata, opts \\ []) do
    cache_name = Keyword.get(opts, :cache_name, cache_name())
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)
    key = s3_key(scope, name)
    metadata = sanitize_package(metadata)
    json_body = JSON.encode!(metadata)

    case Storage.put_object(key, json_body, content_type: "application/json") do
      {:ok, _response} ->
        Cachex.del(cache_name, cache_key(scope, name))
        :ok

      {:error, {:http_error, 429, _}} ->
        Logger.warning("S3 rate limited writing metadata for #{scope}/#{name}")
        {:error, {:s3_error, :rate_limited}}

      {:error, reason} ->
        Logger.error("Failed to write metadata to S3 for #{scope}/#{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def delete_package(scope, name, opts \\ []) do
    cache_name = Keyword.get(opts, :cache_name, cache_name())
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)
    key = s3_key(scope, name)

    case Storage.delete_object(key) do
      {:ok, _response} ->
        Cachex.del(cache_name, cache_key(scope, name))
        :ok

      {:error, {:http_error, 429, _}} ->
        {:error, {:s3_error, :rate_limited}}

      {:error, reason} ->
        Logger.error("Failed to delete metadata from S3 for #{scope}/#{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def list_all_packages do
    "registry/metadata/"
    |> Storage.list_objects_v2()
    |> Stream.filter(fn %{key: key} -> String.ends_with?(key, "/index.json") end)
    |> Stream.map(fn %{key: key} -> parse_s3_key(key) end)
    |> Stream.reject(&is_nil/1)
    |> Enum.to_list()
  end

  defp fetch_from_s3(scope, name, cache_key, cache_name) do
    key = s3_key(scope, name)

    case Storage.get_object(key) do
      {:ok, body, etag} ->
        case JSON.decode(body) do
          {:ok, metadata} ->
            metadata = sanitize_package(metadata)
            Cachex.put(cache_name, cache_key, cache_value(metadata, etag), ttl: @ttl)
            {:ok, metadata}

          {:error, _reason} ->
            {:error, :not_found}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, {:http_error, 429, _}} ->
        {:error, {:s3_error, :rate_limited}}

      {:error, reason} ->
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

    case Storage.head_object(s3_key(scope, name)) do
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

  defp s3_key(scope, name), do: "registry/metadata/#{scope}/#{name}/index.json"

  defp cache_key(scope, name), do: {scope, name}

  defp cache_value(metadata, etag) do
    %{
      metadata: metadata,
      etag: etag,
      checked_at: DateTime.truncate(DateTime.utc_now(), :second)
    }
  end

  defp sanitize_package(metadata) do
    metadata
    |> sanitize_versions("releases")
    |> sanitize_versions("skipped_releases")
  end

  defp sanitize_versions(metadata, key) do
    case Map.fetch(metadata, key) do
      {:ok, versions} ->
        filtered_versions =
          Enum.reduce(versions, %{}, fn {version, value}, acc ->
            if KeyNormalizer.valid_storage_version?(version) do
              Map.put(acc, version, value)
            else
              acc
            end
          end)

        Map.put(metadata, key, filtered_versions)

      :error ->
        metadata
    end
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

  defp parse_s3_key(key) do
    case Regex.run(~r{^registry/metadata/([^/]+)/([^/]+)/index\.json$}, key) do
      [_, scope, name] -> {scope, name}
      _ -> nil
    end
  end
end
