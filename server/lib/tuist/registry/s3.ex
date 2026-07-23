defmodule Tuist.Registry.S3 do
  @moduledoc """
  S3 helpers for sync workers writing into the registry bucket.

  Server uses `Tuist.Storage` for account-scoped artifact buckets; this
  module is the parallel surface for the registry bucket and is only
  touched by `Tuist.Registry.Swift.*` workers. The standalone registry
  pod has its own equivalent (`TuistRegistry.S3`) for reads.
  """

  alias ExAws.S3.Upload
  alias Tuist.Registry

  require Logger

  def get_object(key) when is_binary(key) do
    bucket = Registry.registry_bucket()

    case bucket |> ExAws.S3.get_object(key) |> ExAws.request() do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: 404}} -> {:error, :not_found}
      {:ok, %{status_code: status}} -> {:error, {:s3_error, status}}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def upload_file(key, local_path, opts \\ []) when is_binary(key) and is_binary(local_path) do
    bucket = Registry.registry_bucket()
    content_type_opt = Keyword.get(opts, :content_type)

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
    content_type_opt = Keyword.get(opts, :content_type)
    put_opts = if content_type_opt, do: [content_type: content_type_opt], else: []

    {duration, result} =
      :timer.tc(fn ->
        bucket
        |> ExAws.S3.put_object(key, content, put_opts)
        |> ExAws.request()
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
    |> ExAws.stream!()
    |> Stream.map(& &1.key)
    |> Stream.chunk_every(1000)
    |> Enum.reduce_while({:ok, acc}, fn keys, {:ok, count} ->
      case bucket |> ExAws.S3.delete_multiple_objects(keys) |> ExAws.request() do
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

  defp normalize_etag(nil), do: nil
  defp normalize_etag([value | _]), do: normalize_etag(value)

  defp normalize_etag(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end
end
