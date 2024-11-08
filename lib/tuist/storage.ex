defmodule Tuist.Storage do
  @moduledoc ~S"""
  A module that provides functions for storing and retrieving files from cloud storages
  """
  alias Tuist.Environment
  alias Tuist.Performance

  require Logger

  def multipart_generate_url(object_key, upload_id, part_number, opts \\ []) do
    content_length = opts |> Keyword.get(:content_length)

    headers =
      if is_nil(content_length) do
        []
      else
        [{"Content-Length", Integer.to_string(content_length)}]
      end

    {:ok, url} =
      ExAws.Config.new(:s3)
      |> ExAws.S3.presigned_url(:put, Environment.s3_bucket_name(), object_key,
        query_params: [
          {"partNumber", part_number},
          {"uploadId", upload_id}
        ],
        headers: headers,
        virtual_host: true,
        expires_in: opts |> Keyword.get(:expires_in, 3600)
      )

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_generate_upload_part_presigned_url(),
      %{},
      %{object_key: object_key, upload_id: upload_id, part_number: part_number}
    )

    url
  end

  def multipart_complete_upload(object_key, upload_id, parts) do
    {time, result} =
      Performance.measure_time_in_milliseconds(fn ->
        Environment.s3_bucket_name()
        |> ExAws.S3.complete_multipart_upload(object_key, upload_id, parts)
        |> ExAws.request!()

        :ok
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
      Performance.measure_time_in_milliseconds(fn ->
        {:ok, url} =
          ExAws.Config.new(:s3)
          |> ExAws.S3.presigned_url(:get, Environment.s3_bucket_name(), object_key,
            query_params: [],
            expires_in: opts |> Keyword.get(:expires_in, 3600),
            virtual_host: true
          )

        url
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_generate_download_presigned_url(),
      %{duration: time},
      %{object_key: object_key}
    )

    url
  end

  def generate_upload_url(object_key, opts \\ []) do
    {:ok, url} =
      ExAws.Config.new(:s3)
      |> ExAws.S3.presigned_url(:put, Environment.s3_bucket_name(), object_key,
        query_params: [],
        expires_in: opts |> Keyword.get(:expires_in, 3600),
        virtual_host: true
      )

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_generate_upload_presigned_url(),
      %{},
      %{object_key: object_key}
    )

    url
  end

  def stream_object(object_key) do
    stream =
      Environment.s3_bucket_name()
      |> ExAws.S3.download_file(object_key, :memory)
      |> ExAws.stream!()

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_stream_object(),
      %{},
      %{object_key: object_key}
    )

    stream
  end

  def object_exists?(object_key) do
    {time, exists} =
      Performance.measure_time_in_milliseconds(fn ->
        case Environment.s3_bucket_name()
             |> ExAws.S3.head_object(object_key)
             |> ExAws.request() do
          {:ok, _} -> true
          {:error, _} -> false
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

  def get_object_as_string(object_key) do
    {time, content} =
      Performance.measure_time_in_milliseconds(fn ->
        %{body: content} =
          Environment.s3_bucket_name()
          |> ExAws.S3.get_object(object_key)
          |> ExAws.request!()

        content
      end)

    Logger.debug("Object retrieved in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_get_object_as_string(),
      %{duration: time},
      %{object_key: object_key}
    )

    content
  end

  def multipart_start(object_key) do
    {time, upload_id} =
      Performance.measure_time_in_milliseconds(fn ->
        %{body: %{upload_id: upload_id}} =
          Environment.s3_bucket_name()
          |> ExAws.S3.initiate_multipart_upload(object_key)
          |> ExAws.request!()

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
      Performance.measure_time_in_milliseconds(fn ->
        stream =
          Environment.s3_bucket_name()
          |> ExAws.S3.list_objects_v2(prefix: project_slug, max_keys: 1000)
          |> ExAws.stream!()
          |> Stream.map(& &1.key)

        ExAws.S3.delete_all_objects(Environment.s3_bucket_name(), stream)
        |> ExAws.request!()
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
    {time, size} =
      Performance.measure_time_in_milliseconds(fn ->
        Environment.s3_bucket_name()
        |> ExAws.S3.head_object(object_key)
        |> ExAws.request!()
        |> Map.get(:headers)
        |> Enum.find(fn {key, _value} -> key == "content-length" end)
        |> elem(1)
        |> List.first()
        |> String.to_integer()
      end)

    Logger.debug("Object size checked in #{time} ms.")

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_get_object_as_string_size(),
      %{duration: time, size: size},
      %{object_key: object_key}
    )

    size
  end
end
