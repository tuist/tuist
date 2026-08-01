defmodule Tuist.Registry.S3 do
  @moduledoc """
  S3 helpers for reading and writing the registry bucket.

  Server uses `Tuist.Storage` for account-scoped artifact buckets; this
  module is the parallel surface for the registry bucket. It always passes
  the registry's dedicated connection and credentials so operations-page
  reads cannot accidentally use the account-artifact storage configuration.
  The standalone registry pod has its own equivalent (`TuistRegistry.S3`).
  """

  alias ExAws.S3.Upload
  alias Tuist.Registry

  require Logger

  @doc false
  def request(%Upload{} = operation) do
    ExAws.request(operation, Registry.registry_s3_config())
  end

  def request(operation) do
    operation
    |> with_tigris_consistency()
    |> ExAws.request(Registry.registry_s3_config())
  end

  def get_object(key) when is_binary(key) do
    bucket = Registry.registry_bucket()

    case bucket |> ExAws.S3.get_object(key) |> request() do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: 404}} -> {:error, :not_found}
      {:ok, %{status_code: status}} -> {:error, {:s3_error, status}}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def head_object(key) when is_binary(key) do
    bucket = Registry.registry_bucket()

    case bucket |> ExAws.S3.head_object(key) |> request() do
      {:ok, %{status_code: 200, headers: headers}} -> {:ok, normalize_headers(headers)}
      {:ok, %{status_code: 404}} -> {:error, :not_found}
      {:ok, %{status_code: status}} -> {:error, {:s3_error, status}}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def upload_file(key, local_path, opts \\ []) when is_binary(key) and is_binary(local_path) do
    bucket = Registry.registry_bucket()

    # Forwards every option the caller set rather than only `:content_type`.
    # `:meta` was previously dropped here, so the archive digest a caller asked
    # to store never reached object storage and the read-back verification could
    # only ever observe `nil` — failing every upload it was meant to protect.
    #
    # Rejecting nils is load-bearing rather than tidiness: `put_object_headers/1`
    # reads `Map.get(opts, :meta, [])`, and a map default only applies to an
    # absent key, so a literal `meta: nil` would reach `build_meta_headers/1`
    # and raise.
    upload_opts =
      [timeout: 120_000, max_concurrency: 8]
      |> Keyword.merge(opts)
      |> Keyword.reject(fn {_key, value} -> is_nil(value) end)

    {duration, result} =
      :timer.tc(fn ->
        local_path
        |> Upload.stream_file()
        |> ExAws.S3.upload(bucket, key, upload_opts)
        |> request()
      end)

    case result do
      {:ok, _response} ->
        :telemetry.execute([:tuist_registry, :s3, :upload], %{duration: duration}, %{result: :ok})
        :ok

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:tuist_registry, :s3, :upload], %{duration: duration}, %{result: :rate_limited})
        {:error, :rate_limited}

      {:error, reason} ->
        :telemetry.execute([:tuist_registry, :s3, :upload], %{duration: duration}, %{result: :error})
        {:error, reason}
    end
  end

  def upload_content(key, content, opts \\ []) when is_binary(key) do
    bucket = Registry.registry_bucket()
    # Same shape as `upload_file/3` above, for the same reason: an option a
    # caller sets should be used or absent, never silently ignored.
    put_opts = Keyword.reject(opts, fn {_key, value} -> is_nil(value) end)

    {duration, result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.put_object(key, content, put_opts)
        |> request()
      end)

    case result do
      {:ok, _response} ->
        :telemetry.execute([:tuist_registry, :s3, :upload], %{duration: duration}, %{result: :ok})
        :ok

      {:error, {:http_error, 429, _}} ->
        :telemetry.execute([:tuist_registry, :s3, :upload], %{duration: duration}, %{result: :rate_limited})
        {:error, :rate_limited}

      {:error, reason} ->
        :telemetry.execute([:tuist_registry, :s3, :upload], %{duration: duration}, %{result: :error})
        {:error, reason}
    end
  end

  @doc """
  Lists all objects under `prefix` and deletes them in 1000-object
  batches. Returns `{:ok, deleted_count}` or `{:error, reason}`.
  """
  def delete_all_with_prefix(prefix) when is_binary(prefix) do
    bucket = Registry.registry_bucket()

    Logger.info("Deleting all S3 objects with prefix: #{prefix}")
    {duration, result} = :timer.tc(fn -> list_and_delete_objects(bucket, prefix, 0) end)

    case result do
      {:ok, count} ->
        :telemetry.execute([:tuist_registry, :s3, :delete], %{duration: duration, count: count}, %{result: :ok})
        Logger.info("Deleted #{count} objects with prefix: #{prefix}")
        {:ok, count}

      {:error, reason} = error ->
        :telemetry.execute([:tuist_registry, :s3, :delete], %{duration: duration, count: 0}, %{result: :error})
        Logger.error("Failed to delete objects with prefix #{prefix}: #{inspect(reason)}")
        error
    end
  end

  defp list_and_delete_objects(bucket, prefix, acc) do
    bucket
    |> ExAws.S3.list_objects(prefix: prefix)
    |> ExAws.stream!(Registry.registry_s3_config())
    |> Stream.map(& &1.key)
    |> Stream.chunk_every(1000)
    |> Enum.reduce_while({:ok, acc}, fn keys, {:ok, count} ->
      case bucket |> ExAws.S3.delete_multiple_objects(keys) |> request() do
        {:ok, _} -> {:cont, {:ok, count + length(keys)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def etag_from_headers(headers) when is_map(headers) do
    headers
    |> Map.get("etag", Map.get(headers, "ETag"))
    |> normalize_etag()
  end

  defp normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn {key, value} -> {String.downcase(key), header_value(value)} end)
  end

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {key, value} -> {String.downcase(key), header_value(value)} end)
  end

  # Whether a value arrives as a binary or wrapped in a list depends on the
  # configured HTTP client, not on the header, so callers cannot safely compare
  # against either shape. Normalizing here keeps that detail out of business
  # logic: a comparison against `["..."]` is never equal to the binary it looks
  # identical to when inspected.
  #
  # Only a single-element list is unwrapped. A header that genuinely repeats
  # keeps its list, so a caller sees the ambiguity rather than silently
  # receiving the first value and assuming it was the only one.
  defp header_value([value]), do: value
  defp header_value(value), do: value

  defp normalize_etag(nil), do: nil
  defp normalize_etag([value | _]), do: normalize_etag(value)

  defp normalize_etag(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp with_tigris_consistency(%{headers: headers} = operation) do
    %{operation | headers: Map.put(headers, "X-Tigris-Consistent", "true")}
  end
end
