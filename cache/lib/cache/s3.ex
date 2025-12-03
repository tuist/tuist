defmodule Cache.S3 do
  @moduledoc """
  S3 helper functions for generating presigned URLs.

  Isolated behind a module for easy testing without mutating global config.
  """

  require Logger

  def presign_download_url(key) when is_binary(key) do
    bucket = Application.get_env(:cache, :s3)[:bucket]
    config = ExAws.Config.new(:s3)
    ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: 600)
  end

  def generate_download_url(key, opts \\ []) when is_binary(key) do
    bucket = Application.get_env(:cache, :s3)[:bucket]
    config = ExAws.Config.new(:s3)
    expires_in = Keyword.get(opts, :expires_in, 3600)
    {:ok, url} = ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: expires_in)
    url
  end

  def multipart_start(key) when is_binary(key) do
    bucket = Application.get_env(:cache, :s3)[:bucket]
    config = ExAws.Config.new(:s3)

    %{body: %{upload_id: upload_id}} =
      bucket
      |> ExAws.S3.initiate_multipart_upload(key)
      |> ExAws.request!(config)

    upload_id
  end

  def multipart_generate_url(key, upload_id, part_number, opts \\ []) when is_binary(key) do
    bucket = Application.get_env(:cache, :s3)[:bucket]
    config = ExAws.Config.new(:s3)
    expires_in = Keyword.get(opts, :expires_in, 120)

    query_params = [
      {"partNumber", part_number},
      {"uploadId", upload_id}
    ]

    {:ok, url} =
      ExAws.S3.presigned_url(config, :put, bucket, key,
        expires_in: expires_in,
        query_params: query_params
      )

    url
  end

  def multipart_complete(key, upload_id, parts) when is_binary(key) do
    bucket = Application.get_env(:cache, :s3)[:bucket]
    config = ExAws.Config.new(:s3)

    bucket
    |> ExAws.S3.complete_multipart_upload(key, upload_id, parts)
    |> ExAws.request!(config)

    :ok
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
         |> ExAws.request() do
      {:ok, _response} -> true
      {:error, {:http_error, 404, _}} -> false
      {:error, _reason} -> false
    end
  end
end
