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
        if Environment.on_premise?() do
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
        else
          {:ok, url} =
            ExAws.Config.new(:s3)
            |> ExAws.S3.presigned_url(:put, Environment.s3_bucket_name(), object_key,
              query_params: [
                {"partNumber", part_number},
                {"uploadId", upload_id}
              ],
              headers: [],
              virtual_host: true,
              expires_in: opts |> Keyword.get(:expires_in, 3600)
            )

          url
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_generate_upload_part_presigned_url(),
      %{duration: time},
      %{object_key: object_key, upload_id: upload_id, part_number: part_number}
    )

    Logger.info("Multi-part pre-signed URL generated in #{time} ms.")

    url
  end

  def multipart_complete_upload(object_key, upload_id, parts) do
    {time, result} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        if Environment.on_premise?() do
          Native.s3_multipart_complete_upload(%S3MultipartCompleteUploadOptions{
            bucket_name: Environment.s3_bucket_name(),
            region: native_region(),
            object_key: object_key,
            upload_id: upload_id,
            parts: parts,
            credentials: native_credentials()
          })
        else
          {:ok, _} =
            Environment.s3_bucket_name()
            |> ExAws.S3.complete_multipart_upload(object_key, upload_id, parts)
            |> ExAws.request()

          :ok
        end
      end)

    Logger.debug("Multi-part upload completed in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_complete_upload(),
      %{duration: time, parts_count: Enum.count(parts)},
      %{object_key: object_key, upload_id: upload_id}
    )

    result
  end

  def generate_download_url(object_key, opts \\ []) do
    {time, url} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        if Environment.on_premise?() do
          {:ok, url} =
            Native.s3_download_presigned_url(%S3DownloadPresignedURLOptions{
              bucket_name: Environment.s3_bucket_name(),
              region: native_region(),
              object_key: object_key,
              expires_in: opts |> Keyword.get(:expires_in, 3600),
              credentials: native_credentials()
            })

          url
        else
          Logger.info("Generating url with Elixir...")

          {:ok, url} =
            ExAws.Config.new(:s3)
            |> ExAws.S3.presigned_url(:get, Environment.s3_bucket_name(), object_key,
              query_params: [],
              expires_in: opts |> Keyword.get(:expires_in, 3600),
              virtual_host: true
            )

          url
        end
      end)

    Logger.info("Pre-signed URL generated in #{time} ms.")

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
        if Environment.on_premise?() do
          {:ok, exists} =
            Native.s3_exists(%S3ExistsOptions{
              bucket_name: Environment.s3_bucket_name(),
              region: native_region(),
              object_key: object_key,
              credentials: native_credentials()
            })

          exists
        else
          tuist_hosted_object_exists?(object_key)
        end
      end)

    Logger.debug("Object's existence checked in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_check_object_existence(),
      %{duration: time},
      %{object_key: object_key}
    )

    exists
  end

  defp tuist_hosted_object_exists?(object_key) do
    case Environment.s3_bucket_name()
         |> ExAws.S3.head_object(object_key)
         |> ExAws.request() do
      {:ok, _} -> true
      _ -> false
    end
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
    {time, result} =
      Tuist.Performance.measure_time_in_milliseconds(fn ->
        if Environment.on_premise?() do
          Native.s3_multipart_start(%S3MultipartStartOptions{
            bucket_name: Environment.s3_bucket_name(),
            region: native_region(),
            object_key: object_key,
            credentials: native_credentials()
          })
        else
          tuist_hosted_multipart_start(object_key)
        end
      end)

    Logger.debug("Multi-part upload started in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_start_upload(),
      %{duration: time},
      %{object_key: object_key}
    )

    result
  end

  defp tuist_hosted_multipart_start(object_key) do
    case Environment.s3_bucket_name()
         |> ExAws.S3.initiate_multipart_upload(object_key)
         |> ExAws.request() do
      {:ok, response} -> {:ok, response.body.upload_id}
      {:error, error} -> {:error, error}
    end
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

      {:error, error} ->
        {:error, error}
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
