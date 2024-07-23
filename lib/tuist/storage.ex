defmodule Tuist.Storage do
  @moduledoc ~S"""
  A module that provides functions for storing and retrieving files from cloud storages
  """
  alias Tuist.Environment
  alias Tuist.Native

  alias Tuist.Native.{
    S3DownloadPresignedURLOptions,
    S3ExistsOptions,
    S3MultipartStartOptions,
    S3MultipartGenerateURLOptions,
    S3MultipartCompleteUploadOptions,
    S3SizeOptions,
    S3DeleteAllObjectsOptions,
    S3AccessKeyPair,
    S3GetObjectOptions
  }

  require Logger

  def multipart_generate_url(object_key, upload_id, part_number, opts \\ []) do
    {time, url} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        {:ok, url} =
          Native.s3_multipart_generate_url(%S3MultipartGenerateURLOptions{
            bucket_name: Environment.s3_bucket_name(),
            region: native_region(),
            object_key: object_key,
            expires_in: opts |> Keyword.get(:expires_in, 3600),
            part_number:
              if is_integer(part_number) do
                part_number
              else
                String.to_integer(part_number)
              end,
            upload_id: upload_id,
            credentials: native_credentials()
          })

        url
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_generate_upload_part_presigned_url(),
      %{duration: time},
      %{object_key: object_key, upload_id: upload_id, part_number: part_number}
    )

    Logger.debug("Multi-part pre-signed URL generated in #{time} ms.")

    url
  end

  def multipart_complete_upload(object_key, upload_id, parts) do
    {time, :ok} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        Native.s3_multipart_complete_upload(%S3MultipartCompleteUploadOptions{
          bucket_name: Environment.s3_bucket_name(),
          region: native_region(),
          object_key: object_key,
          upload_id: upload_id,
          parts: parts,
          credentials: native_credentials()
        })
      end)

    Logger.debug("Multi-part upload completed in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_complete_upload(),
      %{duration: time, parts_count: Enum.count(parts)},
      %{object_key: object_key, upload_id: upload_id}
    )

    :ok
  end

  def generate_download_url(object_key, opts \\ []) do
    {time, url} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        {:ok, url} =
          Native.s3_download_presigned_url(%S3DownloadPresignedURLOptions{
            bucket_name: Environment.s3_bucket_name(),
            region: native_region(),
            object_key: object_key,
            expires_in: opts |> Keyword.get(:expires_in, 3600),
            credentials: native_credentials()
          })

        url
      end)

    Logger.debug("Pre-signed URL generated in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_generate_download_presigned_url(),
      %{duration: time},
      %{object_key: object_key}
    )

    url
  end

  def object_exists?(object_key) do
    {time, exists} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        {:ok, exists} =
          Native.s3_exists(%S3ExistsOptions{
            bucket_name: Environment.s3_bucket_name(),
            region: native_region(),
            object_key: object_key,
            credentials: native_credentials()
          })

        exists
      end)

    Logger.debug("Object's existence checked in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_check_object_existence(),
      %{duration: time},
      %{object_key: object_key}
    )

    exists
  end

  def get_object_as_string(object_key) do
    {time, result} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        Native.s3_get_object_as_string(%S3GetObjectOptions{
          bucket_name: Environment.s3_bucket_name(),
          region: native_region(),
          object_key: object_key,
          credentials: native_credentials()
        })
      end)

    Logger.debug("Object retrieved in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_get_object_as_string(),
      %{duration: time},
      %{object_key: object_key}
    )

    result
  end

  def multipart_start(object_key) do
    {time, upload_id} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        {:ok, upload_id} =
          Native.s3_multipart_start(%S3MultipartStartOptions{
            bucket_name: Environment.s3_bucket_name(),
            region: native_region(),
            object_key: object_key,
            credentials: native_credentials()
          })

        upload_id
      end)

    Logger.debug("Multi-part upload started in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_start_upload(),
      %{duration: time},
      %{object_key: object_key}
    )

    upload_id
  end

  def delete_all_objects(project_slug) do
    {time, _} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        Native.s3_delete_all_objects(%S3DeleteAllObjectsOptions{
          bucket_name: Environment.s3_bucket_name(),
          region: native_region(),
          prefix: project_slug,
          credentials: native_credentials()
        })
      end)

    Logger.debug("All objects deleted in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_delete_all_objects(),
      %{duration: time},
      %{project_slug: project_slug}
    )

    :ok
  end

  def get_object_size(object_key) do
    {time, result} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        Native.s3_size(%S3SizeOptions{
          bucket_name: Environment.s3_bucket_name(),
          region: native_region(),
          object_key: object_key,
          credentials: native_credentials()
        })
      end)

    Logger.debug("Object size checked in #{time} ms.")

    case result do
      {:ok, size} ->
        :telemetry.execute(
          Tuist.Telemetry.event_name_storage_get_object_as_string_size(),
          %{duration: time, size: size},
          %{object_key: object_key}
        )

        {:ok, size}

      {:error, {:raw, error}} ->
        {:error, error}

      {:error, {:http, status, _}} when status in 500..599 ->
        {:error,
         {:http, status,
          "The storage service failed with the status code #{status} while obtaining the size of the object."}}
    end
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
