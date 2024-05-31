defmodule TuistCloud.Storage do
  @moduledoc ~S"""
  A module that provides functions for storing and retrieving files from cloud storages
  """
  alias TuistCloud.Environment
  alias TuistCloud.Native
  alias TuistCloud.Native.S3DownloadPresignedURLOptions
  alias TuistCloud.Native.S3ExistsOptions
  alias TuistCloud.Native.S3MultipartStartOptions
  alias TuistCloud.Native.S3MultipartGenerateURLOptions
  alias TuistCloud.Native.S3MultipartCompleteUploadOptions
  alias TuistCloud.Native.S3SizeOptions
  alias TuistCloud.Native.S3DeleteAllObjectsOptions
  alias TuistCloud.Native.S3AccessKeyPair

  def multipart_generate_url(object_key, upload_id, part_number, opts \\ []) do
    {:ok, url} =
      Native.s3_multipart_generate_url(%S3MultipartGenerateURLOptions{
        bucket_name: Environment.s3_bucket_name(),
        region: native_region(),
        object_key: object_key,
        expires_in: opts |> Keyword.get(:expires_in, 3600),
        part_number: String.to_integer(part_number),
        upload_id: upload_id,
        credentials: native_credentials()
      })

    url
  end

  def multipart_complete_upload(object_key, upload_id, parts) do
    :ok =
      Native.s3_multipart_complete_upload(%S3MultipartCompleteUploadOptions{
        bucket_name: Environment.s3_bucket_name(),
        region: native_region(),
        object_key: object_key,
        upload_id: upload_id,
        parts: parts,
        credentials: native_credentials()
      })

    :ok
  end

  def generate_download_url(object_key, opts \\ []) do
    {:ok, url} =
      Native.s3_download_presigned_url(%S3DownloadPresignedURLOptions{
        bucket_name: Environment.s3_bucket_name(),
        region: native_region(),
        object_key: object_key,
        expires_in: opts |> Keyword.get(:expires_in, 3600),
        credentials: native_credentials()
      })

    url
  end

  def exists(object_key) do
    {:ok, exists} =
      Native.s3_exists(%S3ExistsOptions{
        bucket_name: Environment.s3_bucket_name(),
        region: native_region(),
        object_key: object_key,
        credentials: native_credentials()
      })

    exists
  end

  def multipart_start(object_key) do
    {:ok, upload_id} =
      Native.s3_multipart_start(%S3MultipartStartOptions{
        bucket_name: Environment.s3_bucket_name(),
        region: native_region(),
        object_key: object_key,
        credentials: native_credentials()
      })

    upload_id
  end

  def delete_all_objects(project_slug) do
    Native.s3_delete_all_objects(%S3DeleteAllObjectsOptions{
      bucket_name: Environment.s3_bucket_name(),
      region: native_region(),
      prefix: project_slug,
      credentials: native_credentials()
    })
  end

  def size(object_key) do
    {:ok, size} =
      Native.s3_size(%S3SizeOptions{
        bucket_name: Environment.s3_bucket_name(),
        region: native_region(),
        object_key: object_key,
        credentials: native_credentials()
      })

    size
  end

  defp native_region() do
    if Environment.on_premise?() do
      :auto
    else
      {:fixed, %{region: Environment.aws_region(), endpoint: Environment.s3_endpoint()}}
    end
  end

  defp native_credentials() do
    if Environment.on_premise?() do
      :environment
    else
      {:access_key,
       %S3AccessKeyPair{
         access_key: Environment.s3_access_key_id(),
         secret_key: Environment.s3_secret_access_key()
       }}
    end
  end
end
