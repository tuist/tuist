defmodule Tuist.Storage do
  @moduledoc ~S"""
  A module that provides functions for storing and retrieving files from cloud storages
  """
  alias Tuist.Environment
  alias Tuist.Performance

  def multipart_generate_url(object_key, upload_id, part_number, actor, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:query_params, [
        {"partNumber", part_number},
        {"uploadId", upload_id}
      ])
      |> Keyword.put(:actor, actor)

    url =
      presigned_url(:put, object_key, opts)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_generate_upload_part_presigned_url(),
      %{},
      %{object_key: object_key, upload_id: upload_id, part_number: part_number}
    )

    url
  end

  defp presigned_url(method, object_key, opts) do
    query_params = Keyword.get(opts, :query_params, [])
    actor = Keyword.fetch!(opts, :actor)

    {config, bucket_name} = s3_config_and_bucket(actor)

    {:ok, url} =
      ExAws.S3.presigned_url(config, method, bucket_name, object_key,
        query_params: query_params,
        expires_in: Keyword.get(opts, :expires_in, 3600)
      )

    url
  end

  def multipart_complete_upload(object_key, upload_id, parts, actor) do
    {time, result} =
      Performance.measure_time_in_milliseconds(fn ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        bucket_name
        |> ExAws.S3.complete_multipart_upload(object_key, upload_id, parts)
        |> ExAws.request!(config)

        :ok
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_complete_upload(),
      %{duration: time, parts_count: Enum.count(parts)},
      %{object_key: object_key, upload_id: upload_id}
    )

    result
  end

  def generate_download_url(object_key, actor, opts \\ []) do
    opts = Keyword.put(opts, :actor, actor)
    url = presigned_url(:get, object_key, opts)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_generate_download_presigned_url(),
      %{},
      %{object_key: object_key}
    )

    url
  end

  def generate_upload_url(object_key, actor, opts \\ []) do
    opts = Keyword.put(opts, :actor, actor)
    url = presigned_url(:put, object_key, opts)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_generate_upload_presigned_url(),
      %{},
      %{object_key: object_key}
    )

    url
  end

  def stream_object(object_key, actor) do
    {config, bucket_name} = s3_config_and_bucket(actor)

    stream =
      bucket_name
      |> ExAws.S3.download_file(object_key, :memory)
      |> ExAws.stream!(config)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_stream_object(),
      %{},
      %{object_key: object_key}
    )

    stream
  end

  def upload(source, object_key, actor) do
    {config, bucket_name} = s3_config_and_bucket(actor)

    source
    |> ExAws.S3.upload(bucket_name, object_key)
    |> ExAws.request!(config)
  end

  def put_object(object_key, content, actor) do
    {config, bucket_name} = s3_config_and_bucket(actor)

    bucket_name
    |> ExAws.S3.put_object(object_key, content)
    |> ExAws.request!(config)
  end

  def object_exists?(object_key, actor) do
    {time, exists} =
      Performance.measure_time_in_milliseconds(fn ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        case bucket_name
             |> ExAws.S3.head_object(object_key)
             |> ExAws.request(config) do
          {:ok, _} -> true
          {:error, _} -> false
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_check_object_existence(),
      %{duration: time},
      %{object_key: object_key}
    )

    exists
  end

  def get_object_as_string(object_key, actor) do
    {time, result} =
      Performance.measure_time_in_milliseconds(fn ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        bucket_name
        |> ExAws.S3.get_object(object_key)
        |> ExAws.request(config)
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_get_object_as_string(),
      %{duration: time},
      %{object_key: object_key}
    )

    case result do
      {:ok, %{body: content}} -> content
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  def multipart_start(object_key, actor) do
    {time, upload_id} =
      Performance.measure_time_in_milliseconds(fn ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        %{body: %{upload_id: upload_id}} =
          bucket_name |> ExAws.S3.initiate_multipart_upload(object_key) |> ExAws.request!(config)

        upload_id
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_start_upload(),
      %{duration: time},
      %{object_key: object_key}
    )

    upload_id
  end

  def delete_all_objects(prefix, actor) do
    {time, _} =
      Performance.measure_time_in_milliseconds(fn ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        # Check if there are any objects with the given prefix
        any_objects? =
          bucket_name
          |> ExAws.S3.list_objects_v2(prefix: prefix, max_keys: 1)
          |> ExAws.request!(config)
          |> Map.get(:body)
          |> Map.get(:contents)
          |> Enum.any?()

        if any_objects? do
          stream =
            bucket_name
            |> ExAws.S3.list_objects_v2(prefix: prefix, max_keys: 1000)
            |> ExAws.stream!(config)
            |> Stream.map(& &1.key)

          {:ok, _} =
            bucket_name |> ExAws.S3.delete_all_objects(stream) |> ExAws.request(config)
        else
          :ok
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_delete_all_objects(),
      %{duration: time},
      %{project_slug: prefix}
    )

    :ok
  end

  def get_object_size(object_key, actor) do
    {time, size} =
      Performance.measure_time_in_milliseconds(fn ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        bucket_name
        |> ExAws.S3.head_object(object_key)
        |> ExAws.request!(config)
        |> Map.get(:headers)
        |> Enum.find(fn {key, _value} -> key == "content-length" end)
        |> elem(1)
        |> List.first()
        |> String.to_integer()
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_get_object_as_string_size(),
      %{duration: time, size: size},
      %{object_key: object_key}
    )

    size
  end

  defp s3_config_and_bucket(actor) do
    if use_tigris?(actor) do
      {ExAws.Config.new(:s3_tigris), Environment.s3_bucket_name(:tigris, Environment.decrypt_secrets())}
    else
      {ExAws.Config.new(:s3), Environment.s3_bucket_name()}
    end
  end

  defp use_tigris?(actor) do
    case actor do
      :registry -> FunWithFlags.enabled?(:tigris)
      _ -> FunWithFlags.enabled?(:tigris, for: actor)
    end
  end
end
