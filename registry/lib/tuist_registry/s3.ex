defmodule TuistRegistry.S3 do
  @moduledoc """
  Object-storage helper functions for registry read paths.

  Isolated behind a module for easy testing without mutating global config.

  Registry metadata and artifacts are stored in the configured registry bucket.
  """

  alias TuistRegistry.Config

  @doc false
  def request(%{headers: headers} = operation) do
    operation
    |> Map.put(:headers, Map.put(headers, "X-Tigris-Consistent", "true"))
    |> ExAws.request()
  end

  @doc """
  Generates a presigned download URL for an artifact.

  ## Options

    * `:type` - The storage type. Only `:registry` is supported.
    * `:content_type` - Overrides the content type returned by object storage.

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

        presign_opts =
          case Keyword.fetch(opts, :content_type) do
            {:ok, content_type} ->
              [expires_in: 600, query_params: [{"response-content-type", content_type}]]

            :error ->
              [expires_in: 600]
          end

        ExAws.S3.presigned_url(config, :get, bucket, key, presign_opts)
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
        case bucket |> ExAws.S3.get_object(key) |> request() do
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
end
