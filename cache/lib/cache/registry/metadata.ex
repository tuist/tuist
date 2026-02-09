defmodule Cache.Registry.Metadata do
  @moduledoc """
  Schema and functions for registry package metadata stored as JSON in S3.

  Unlike the server which uses PostgreSQL, cache nodes store package metadata
  as JSON files in S3 at `registry/metadata/{scope}/{name}/index.json`.

  ## JSON Schema

  ```json
  {
    "scope": "string",
    "name": "string",
    "repository_full_handle": "string",
    "releases": {
      "<version>": {
        "checksum": "string (sha256 hex lowercase)",
        "manifests": [
          {
            "swift_version": "string | null",
            "swift_tools_version": "string | null"
          }
        ]
      }
    },
    "updated_at": "ISO8601 timestamp"
  }
  ```

  ## Field Descriptions

  * `scope` - The package scope (e.g., "apple" for github.com/apple/...)
  * `name` - The package name (e.g., "swift-argument-parser")
  * `repository_full_handle` - Full GitHub handle (e.g., "apple/swift-argument-parser")
  * `releases` - Map of version strings to release data
  * `releases.<version>.checksum` - SHA256 checksum of the source archive (hex, lowercase)
  * `releases.<version>.manifests` - List of Package.swift variants for this release
  * `releases.<version>.manifests[].swift_version` - Swift version suffix (e.g., "5.9") or null for default
  * `releases.<version>.manifests[].swift_tools_version` - Swift tools version from manifest or null
  * `updated_at` - ISO8601 timestamp of last sync (for staleness detection)

  ## Example

  ```json
  {
    "scope": "apple",
    "name": "swift-argument-parser",
    "repository_full_handle": "apple/swift-argument-parser",
    "releases": {
      "1.2.0": {
        "checksum": "abc123...",
        "manifests": [
          {"swift_version": null, "swift_tools_version": "5.7"},
          {"swift_version": "5.9", "swift_tools_version": "5.9"}
        ]
      },
      "1.3.0": {
        "checksum": "def456...",
        "manifests": [
          {"swift_version": null, "swift_tools_version": "5.9"}
        ]
      }
    },
    "updated_at": "2024-01-15T10:30:00Z"
  }
  ```

  ## API Response Support

  This schema supports generating all required API responses:

  * `list_releases` - Uses `releases` map to build version → URL mapping
  * `show_release` - Uses `releases.<version>.checksum` for resource checksum
  * `alternate_manifests_link` - Uses `releases.<version>.manifests` to build Link header

  ## S3 Storage

  Metadata is stored at: `registry/metadata/{scope}/{name}/index.json`

  Example: `registry/metadata/apple/swift-argument-parser/index.json`
  """

  alias Cache.Config
  alias Cache.Registry.KeyNormalizer
  alias Cache.S3

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
  doesn't exist in S3.

  ## Options

    * `:fresh` - when true, bypasses the cache and reads from S3 directly.
  """
  def get_package(scope, name, opts \\ []) do
    fresh = Keyword.get(opts, :fresh, false)
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)
    cache_key = cache_key(scope, name)

    if fresh do
      fetch_from_s3(scope, name, cache_key)
    else
      case Cachex.get(cache_name(), cache_key) do
        {:ok, nil} ->
          fetch_from_s3(scope, name, cache_key)

        {:ok, %{metadata: metadata} = cached} ->
          maybe_revalidate(scope, name, cache_key, cached, metadata)

        {:ok, metadata} when is_map(metadata) ->
          {:ok, metadata}

        _ ->
          fetch_from_s3(scope, name, cache_key)
      end
    end
  end

  @doc """
  Writes package metadata to S3 and invalidates the cache.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  def put_package(scope, name, metadata) do
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)
    key = s3_key(scope, name)
    bucket = bucket()
    json_body = Jason.encode!(metadata)

    {duration, result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.put_object(key, json_body, content_type: "application/json")
        |> ExAws.request()
      end)

    case result do
      {:ok, _response} ->
        :telemetry.execute([:cache, :s3, :upload], %{duration: duration}, %{result: :ok})
        Cachex.del(cache_name(), cache_key(scope, name))
        :ok

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:cache, :s3, :upload], %{duration: duration}, %{result: :rate_limited})
        Logger.warning("S3 rate limited writing metadata for #{scope}/#{name}")
        {:error, {:s3_error, :rate_limited}}

      {:error, reason} ->
        :telemetry.execute([:cache, :s3, :upload], %{duration: duration}, %{result: :error})
        Logger.error("Failed to write metadata to S3 for #{scope}/#{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deletes package metadata from S3 and invalidates the cache.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  def delete_package(scope, name) do
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)
    key = s3_key(scope, name)
    bucket = bucket()

    {duration, result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.delete_object(key)
        |> ExAws.request()
      end)

    case result do
      {:ok, _response} ->
        :telemetry.execute([:cache, :s3, :delete], %{duration: duration, count: 1}, %{result: :ok})
        Cachex.del(cache_name(), cache_key(scope, name))
        :ok

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:cache, :s3, :delete], %{duration: duration, count: 0}, %{result: :rate_limited})
        Logger.warning("S3 rate limited deleting metadata for #{scope}/#{name}")
        {:error, {:s3_error, :rate_limited}}

      {:error, reason} ->
        :telemetry.execute([:cache, :s3, :delete], %{duration: duration, count: 0}, %{result: :error})
        Logger.error("Failed to delete metadata from S3 for #{scope}/#{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists all package metadata keys in S3.

  Returns a list of `{scope, name}` tuples for all packages stored in S3.
  Used for cache registry sync and diagnostics.
  """
  def list_all_packages do
    bucket = bucket()
    prefix = "registry/metadata/"

    bucket
    |> ExAws.S3.list_objects_v2(prefix: prefix)
    |> ExAws.stream!()
    |> Stream.filter(fn %{key: key} -> String.ends_with?(key, "/index.json") end)
    |> Stream.map(fn %{key: key} -> parse_s3_key(key) end)
    |> Stream.reject(&is_nil/1)
    |> Enum.to_list()
  end

  defp fetch_from_s3(scope, name, cache_key) do
    key = s3_key(scope, name)
    bucket = bucket()

    {duration, result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.get_object(key)
        |> ExAws.request()
      end)

    case result do
      {:ok, %{body: body, headers: headers}} ->
        :telemetry.execute([:cache, :s3, :get], %{duration: duration}, %{result: :ok})

        case Jason.decode(body) do
          {:ok, metadata} ->
            etag = S3.etag_from_headers(headers)
            Cachex.put(cache_name(), cache_key, cache_value(metadata, etag), ttl: @ttl)
            {:ok, metadata}

          {:error, _reason} ->
            {:error, :not_found}
        end

      {:error, {:http_error, 404, _}} ->
        :telemetry.execute([:cache, :s3, :get], %{duration: duration}, %{result: :not_found})
        {:error, :not_found}

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:cache, :s3, :get], %{duration: duration}, %{result: :rate_limited})
        {:error, {:s3_error, :rate_limited}}

      {:error, reason} ->
        :telemetry.execute([:cache, :s3, :get], %{duration: duration}, %{result: :error})
        Logger.warning("S3 error fetching metadata for #{scope}/#{name}: #{inspect(reason)}")
        {:error, {:s3_error, reason}}
    end
  end

  defp maybe_revalidate(scope, name, cache_key, cached, metadata) do
    case Map.get(cached, :checked_at) do
      %DateTime{} = checked_at ->
        if DateTime.diff(DateTime.utc_now(), checked_at) >= @revalidate_interval_seconds do
          revalidate_cached(scope, name, cache_key, cached, metadata)
        else
          {:ok, metadata}
        end

      _ ->
        revalidate_cached(scope, name, cache_key, cached, metadata)
    end
  end

  defp revalidate_cached(scope, name, cache_key, cached, metadata) do
    cached_etag = Map.get(cached, :etag)

    case head_etag(scope, name) do
      {:ok, ^cached_etag} when is_binary(cached_etag) ->
        Cachex.put(cache_name(), cache_key, cache_value(metadata, cached_etag), ttl: @ttl)
        {:ok, metadata}

      {:ok, _etag} ->
        fetch_from_s3(scope, name, cache_key)

      {:error, :not_found} ->
        Cachex.del(cache_name(), cache_key)
        {:error, :not_found}

      {:error, _reason} ->
        {:ok, metadata}
    end
  end

  defp head_etag(scope, name) do
    key = s3_key(scope, name)
    bucket = bucket()

    {duration, result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.head_object(key)
        |> ExAws.request()
      end)

    case result do
      {:ok, %{headers: headers}} ->
        :telemetry.execute([:cache, :s3, :head], %{duration: duration}, %{result: :found})
        {:ok, S3.etag_from_headers(headers)}

      {:error, {:http_error, 404, _}} ->
        :telemetry.execute([:cache, :s3, :head], %{duration: duration}, %{result: :not_found})
        {:error, :not_found}

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:cache, :s3, :head], %{duration: duration}, %{result: :rate_limited})
        {:error, {:s3_error, :rate_limited}}

      {:error, reason} ->
        :telemetry.execute([:cache, :s3, :head], %{duration: duration}, %{result: :error})
        {:error, reason}
    end
  end

  defp s3_key(scope, name), do: "registry/metadata/#{scope}/#{name}/index.json"

  defp cache_key(scope, name), do: {scope, name}

  defp bucket, do: Config.registry_bucket()

  defp cache_value(metadata, etag) do
    %{
      metadata: metadata,
      etag: etag,
      checked_at: DateTime.truncate(DateTime.utc_now(), :second)
    }
  end

  defp parse_s3_key(key) do
    case Regex.run(~r{^registry/metadata/([^/]+)/([^/]+)/index\.json$}, key) do
      [_, scope, name] -> {scope, name}
      _ -> nil
    end
  end
end
