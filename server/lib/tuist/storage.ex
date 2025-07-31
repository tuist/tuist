defmodule Tuist.Storage do
  @moduledoc ~S"""
  A module that provides functions for storing and retrieving files from cloud storages
  """
  import SweetXml
  import XmlBuilder

  alias Tuist.Environment
  alias Tuist.Performance
  alias Tuist.Storage.LocalS3

  def multipart_generate_url(object_key, upload_id, part_number, opts \\ []) do
    url =
      if Environment.use_local_storage?() do
        multipart_generate_url_local_s3(object_key, upload_id, part_number, opts)
      else
        multipart_generate_url_remote_s3(object_key, upload_id, part_number, opts)
      end

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_generate_upload_part_presigned_url(),
      %{},
      %{object_key: object_key, upload_id: upload_id, part_number: part_number}
    )

    url
  end

  defp multipart_generate_url_local_s3(object_key, upload_id, part_number, _opts) do
    bucket = Environment.s3_bucket_name()
    base_url = Environment.app_url()
    params = URI.encode_query([{"uploadId", upload_id}, {"partNumber", part_number}])
    "#{base_url}/s3/#{bucket}/#{object_key}?#{params}"
  end

  defp multipart_generate_url_remote_s3(object_key, upload_id, part_number, opts) do
    content_length = Keyword.get(opts, :content_length)

    headers =
      if is_nil(content_length) do
        []
      else
        [{"Content-Length", Integer.to_string(content_length)}]
      end

    {:ok, url} =
      :s3
      |> ExAws.Config.new()
      |> ExAws.S3.presigned_url(:put, Environment.s3_bucket_name(), object_key,
        query_params: [
          {"partNumber", part_number},
          {"uploadId", upload_id}
        ],
        headers: headers,
        virtual_host: true,
        expires_in: Keyword.get(opts, :expires_in, 3600)
      )

    url
  end

  def multipart_complete_upload(object_key, upload_id, parts) do
    {time, result} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          multipart_complete_upload_local_s3(object_key, upload_id, parts)
        else
          multipart_complete_upload_remote_s3(object_key, upload_id, parts)
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_complete_upload(),
      %{duration: time, parts_count: Enum.count(parts)},
      %{object_key: object_key, upload_id: upload_id}
    )

    result
  end

  defp multipart_complete_upload_local_s3(object_key, upload_id, parts) do
    bucket = Environment.s3_bucket_name()
    base_url = Environment.app_url()
    url = "#{base_url}/s3/#{bucket}/#{object_key}?uploadId=#{upload_id}"

    parts_elements =
      Enum.map(parts, fn
        {part_number, etag} ->
          element(:Part, [
            element(:PartNumber, part_number),
            element(:ETag, etag)
          ])

        %{etag: etag, part_number: part_number} ->
          element(:Part, [
            element(:PartNumber, part_number),
            element(:ETag, etag)
          ])
      end)

    body =
      element(:CompleteMultipartUpload, parts_elements)
      |> document()
      |> generate()

    case Req.post(url, body: body, headers: [{"content-type", "application/xml"}]) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: response_body}} ->
        {:error, "Failed to complete multipart upload - HTTP #{status}: #{inspect(response_body)}"}

      {:error, reason} ->
        {:error, "Failed to complete multipart upload - Request error: #{inspect(reason)}"}
    end
  end

  defp multipart_complete_upload_remote_s3(object_key, upload_id, parts) do
    Environment.s3_bucket_name()
    |> ExAws.S3.complete_multipart_upload(object_key, upload_id, parts)
    |> ExAws.request!()

    :ok
  end

  def generate_download_url(object_key, opts \\ []) do
    {time, url} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          generate_download_url_local_s3(object_key)
        else
          generate_download_url_remote_s3(object_key, opts)
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_generate_download_presigned_url(),
      %{duration: time},
      %{object_key: object_key}
    )

    url
  end

  defp generate_download_url_local_s3(object_key) do
    bucket = Environment.s3_bucket_name()
    base_url = Environment.app_url()
    "#{base_url}/s3/#{bucket}/#{object_key}"
  end

  defp generate_download_url_remote_s3(object_key, opts) do
    {:ok, url} =
      :s3
      |> ExAws.Config.new()
      |> ExAws.S3.presigned_url(:get, Environment.s3_bucket_name(), object_key,
        query_params: [],
        expires_in: Keyword.get(opts, :expires_in, 3600),
        virtual_host: true
      )

    url
  end

  def generate_upload_url(object_key, opts \\ []) do
    url =
      if Environment.use_local_storage?() do
        generate_upload_url_local_s3(object_key)
      else
        generate_upload_url_remote_s3(object_key, opts)
      end

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_generate_upload_presigned_url(),
      %{},
      %{object_key: object_key}
    )

    url
  end

  defp generate_upload_url_local_s3(object_key) do
    bucket = Environment.s3_bucket_name()
    base_url = Environment.app_url()
    "#{base_url}/s3/#{bucket}/#{object_key}"
  end

  defp generate_upload_url_remote_s3(object_key, opts) do
    {:ok, url} =
      :s3
      |> ExAws.Config.new()
      |> ExAws.S3.presigned_url(:put, Environment.s3_bucket_name(), object_key,
        query_params: [],
        expires_in: Keyword.get(opts, :expires_in, 3600),
        virtual_host: true
      )

    url
  end

  def stream_object(object_key) do
    stream =
      if Environment.use_local_storage?() do
        stream_object_local_s3(object_key)
      else
        stream_object_remote_s3(object_key)
      end

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_stream_object(),
      %{},
      %{object_key: object_key}
    )

    stream
  end

  defp stream_object_local_s3(object_key) do
    bucket = Environment.s3_bucket_name()
    completed_dir = LocalS3.completed_directory()
    object_path = Path.join([completed_dir, bucket, object_key])

    File.stream!(object_path)
  end

  defp stream_object_remote_s3(object_key) do
    Environment.s3_bucket_name()
    |> ExAws.S3.download_file(object_key, :memory)
    |> ExAws.stream!()
  end

  def upload(source, object_key) do
    if Environment.use_local_storage?() do
      upload_local_s3(source, object_key)
    else
      upload_remote_s3(source, object_key)
    end
  end

  defp upload_local_s3(source, object_key) do
    bucket = Environment.s3_bucket_name()
    base_url = Environment.app_url()
    url = "#{base_url}/s3/#{bucket}/#{object_key}"

    content = File.read!(source)

    case Req.put(url, body: content) do
      {:ok, %{status: 200}} -> :ok
      _ -> {:error, "Failed to upload file"}
    end
  end

  defp upload_remote_s3(source, object_key) do
    bucket = Environment.s3_bucket_name()

    source
    |> ExAws.S3.upload(bucket, object_key)
    |> ExAws.request!()
  end

  def put_object(object_key, content) do
    if Environment.use_local_storage?() do
      put_object_local_s3(object_key, content)
    else
      put_object_remote_s3(object_key, content)
    end
  end

  defp put_object_local_s3(object_key, content) do
    bucket = Environment.s3_bucket_name()
    base_url = Environment.app_url()
    url = "#{base_url}/s3/#{bucket}/#{object_key}"

    case Req.put(url, body: content) do
      {:ok, %{status: 200}} -> :ok
      _ -> {:error, "Failed to put object"}
    end
  end

  defp put_object_remote_s3(object_key, content) do
    Environment.s3_bucket_name()
    |> ExAws.S3.put_object(object_key, content)
    |> ExAws.request!()
  end

  def object_exists?(object_key) do
    {time, exists} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          object_exists_local_s3?(object_key)
        else
          object_exists_remote_s3?(object_key)
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_check_object_existence(),
      %{duration: time},
      %{object_key: object_key}
    )

    exists
  end

  defp object_exists_local_s3?(object_key) do
    bucket = Environment.s3_bucket_name()
    completed_dir = LocalS3.completed_directory()
    object_path = Path.join([completed_dir, bucket, object_key])
    File.exists?(object_path) && File.regular?(object_path)
  end

  defp object_exists_remote_s3?(object_key) do
    case Environment.s3_bucket_name()
         |> ExAws.S3.head_object(object_key)
         |> ExAws.request() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  def get_object_as_string(object_key) do
    {time, result} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          get_object_as_string_local_s3(object_key)
        else
          get_object_as_string_remote_s3(object_key)
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_get_object_as_string(),
      %{duration: time},
      %{object_key: object_key}
    )

    result
  end

  defp get_object_as_string_local_s3(object_key) do
    bucket = Environment.s3_bucket_name()
    completed_dir = LocalS3.completed_directory()
    object_path = Path.join([completed_dir, bucket, object_key])

    if File.exists?(object_path) && File.regular?(object_path) do
      File.read!(object_path)
    end
  end

  defp get_object_as_string_remote_s3(object_key) do
    Environment.s3_bucket_name()
    |> ExAws.S3.get_object(object_key)
    |> ExAws.request()
    |> case do
      {:ok, %{body: content}} -> content
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  def multipart_start(object_key) do
    {time, upload_id} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          multipart_start_local_s3(object_key)
        else
          multipart_start_remote_s3(object_key)
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_start_upload(),
      %{duration: time},
      %{object_key: object_key}
    )

    upload_id
  end

  defp multipart_start_local_s3(object_key) do
    bucket = Environment.s3_bucket_name()
    base_url = Environment.app_url()
    url = "#{base_url}/s3/#{bucket}/#{object_key}?uploads"

    case Req.post(url, headers: [{"content-type", "application/xml"}]) do
      {:ok, %{status: 200, body: body}} ->
        upload_id = xpath(body, ~x"//UploadId/text()"s)

        if upload_id == "" do
          raise "Failed to parse upload ID from response: #{body}"
        else
          upload_id
        end

      {:ok, %{status: status, body: body}} ->
        raise "Failed to initiate multipart upload - HTTP #{status}: #{inspect(body)}"

      {:error, reason} ->
        raise "Failed to initiate multipart upload - Request error: #{inspect(reason)}"
    end
  end

  defp multipart_start_remote_s3(object_key) do
    %{body: %{upload_id: upload_id}} =
      Environment.s3_bucket_name()
      |> ExAws.S3.initiate_multipart_upload(object_key)
      |> ExAws.request!()

    upload_id
  end

  def delete_all_objects(prefix) do
    {time, _} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          delete_all_objects_local_s3(prefix)
        else
          delete_all_objects_remote_s3(prefix)
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_delete_all_objects(),
      %{duration: time},
      %{project_slug: prefix}
    )

    :ok
  end

  defp delete_all_objects_local_s3(_prefix) do
    # For local storage, we'd need to implement batch delete
    # For now, just return :ok as local storage is temporary
    :ok
  end

  defp delete_all_objects_remote_s3(prefix) do
    # Check if there are any objects with the given prefix
    any_objects? =
      Environment.s3_bucket_name()
      |> ExAws.S3.list_objects_v2(prefix: prefix, max_keys: 1)
      |> ExAws.request!()
      |> Map.get(:body)
      |> Map.get(:contents)
      |> Enum.any?()

    if any_objects? do
      stream =
        Environment.s3_bucket_name()
        |> ExAws.S3.list_objects_v2(prefix: prefix, max_keys: 1000)
        |> ExAws.stream!()
        |> Stream.map(& &1.key)

      {:ok, _} =
        Environment.s3_bucket_name() |> ExAws.S3.delete_all_objects(stream) |> ExAws.request()
    else
      :ok
    end
  end

  def get_object_size(object_key) do
    {time, size} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          get_object_size_local_s3(object_key)
        else
          get_object_size_remote_s3(object_key)
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_get_object_as_string_size(),
      %{duration: time, size: size},
      %{object_key: object_key}
    )

    size
  end

  defp get_object_size_local_s3(object_key) do
    bucket = Environment.s3_bucket_name()
    completed_dir = LocalS3.completed_directory()
    object_path = Path.join([completed_dir, bucket, object_key])

    if File.exists?(object_path) && File.regular?(object_path) do
      %{size: size} = File.stat!(object_path)
      size
    else
      0
    end
  end

  defp get_object_size_remote_s3(object_key) do
    Environment.s3_bucket_name()
    |> ExAws.S3.head_object(object_key)
    |> ExAws.request!()
    |> Map.get(:headers)
    |> Enum.find(fn {key, _value} -> key == "content-length" end)
    |> case do
      {_, value} when is_list(value) -> List.first(value)
      {_, value} -> value
      nil -> "0"
    end
    |> String.to_integer()
  end
end
