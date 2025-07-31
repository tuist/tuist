defmodule Tuist.Storage do
  @moduledoc ~S"""
  A module that provides functions for storing and retrieving files from cloud storages
  """
  import SweetXml

  alias Tuist.Environment
  alias Tuist.Performance
  alias Tuist.Storage.LocalS3

  def multipart_generate_url(object_key, upload_id, part_number, opts \\ []) do
    content_length = Keyword.get(opts, :content_length)

    headers =
      if is_nil(content_length) do
        []
      else
        [{"Content-Length", Integer.to_string(content_length)}]
      end

    url =
      if Environment.use_local_storage?() do
        # For local storage, generate a direct URL to our local S3 controller
        bucket = Environment.s3_bucket_name()
        base_url = Environment.app_url()
        params = URI.encode_query([{"uploadId", upload_id}, {"partNumber", part_number}])
        "#{base_url}/s3/#{bucket}/#{object_key}?#{params}"
      else
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
        if Environment.use_local_storage?() do
          # For local storage, make a direct HTTP request to our local S3 controller
          bucket = Environment.s3_bucket_name()
          base_url = Environment.app_url()
          url = "#{base_url}/s3/#{bucket}/#{object_key}?uploadId=#{upload_id}"

          # Build the XML body for complete multipart upload
          parts_xml =
            Enum.map_join(parts, "", fn
              {part_number, etag} ->
                "<Part><PartNumber>#{part_number}</PartNumber><ETag>#{etag}</ETag></Part>"

              %{etag: etag, part_number: part_number} ->
                "<Part><PartNumber>#{part_number}</PartNumber><ETag>#{etag}</ETag></Part>"
            end)

          body = """
          <?xml version="1.0" encoding="UTF-8"?>
          <CompleteMultipartUpload>
            #{parts_xml}
          </CompleteMultipartUpload>
          """

          case Req.post(url, body: body, headers: [{"content-type", "application/xml"}]) do
            {:ok, %{status: 200}} ->
              :ok

            {:ok, %{status: status, body: response_body}} ->
              {:error, "Failed to complete multipart upload - HTTP #{status}: #{inspect(response_body)}"}

            {:error, reason} ->
              {:error, "Failed to complete multipart upload - Request error: #{inspect(reason)}"}
          end
        else
          Environment.s3_bucket_name()
          |> ExAws.S3.complete_multipart_upload(object_key, upload_id, parts)
          |> ExAws.request!()

          :ok
        end
      end)

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
        if Environment.use_local_storage?() do
          # For local storage, generate a direct URL to our local S3 controller
          bucket = Environment.s3_bucket_name()
          base_url = Environment.app_url()
          "#{base_url}/s3/#{bucket}/#{object_key}"
        else
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
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_generate_download_presigned_url(),
      %{duration: time},
      %{object_key: object_key}
    )

    url
  end

  def generate_upload_url(object_key, opts \\ []) do
    url =
      if Environment.use_local_storage?() do
        # For local storage, generate a direct URL to our local S3 controller
        bucket = Environment.s3_bucket_name()
        base_url = Environment.app_url()
        "#{base_url}/s3/#{bucket}/#{object_key}"
      else
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

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_generate_upload_presigned_url(),
      %{},
      %{object_key: object_key}
    )

    url
  end

  def stream_object(object_key) do
    stream =
      if Environment.use_local_storage?() do
        # For local storage, stream the file directly from filesystem
        bucket = Environment.s3_bucket_name()
        completed_dir = LocalS3.completed_directory()
        object_path = Path.join([completed_dir, bucket, object_key])

        File.stream!(object_path)
      else
        Environment.s3_bucket_name()
        |> ExAws.S3.download_file(object_key, :memory)
        |> ExAws.stream!()
      end

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_stream_object(),
      %{},
      %{object_key: object_key}
    )

    stream
  end

  def upload(source, object_key) do
    if Environment.use_local_storage?() do
      # For local storage, upload directly to our local S3 controller
      bucket = Environment.s3_bucket_name()
      base_url = Environment.app_url()
      url = "#{base_url}/s3/#{bucket}/#{object_key}"

      content = File.read!(source)

      case Req.put(url, body: content) do
        {:ok, %{status: 200}} -> :ok
        _ -> {:error, "Failed to upload file"}
      end
    else
      bucket = Environment.s3_bucket_name()

      source
      |> ExAws.S3.upload(bucket, object_key)
      |> ExAws.request!()
    end
  end

  def put_object(object_key, content) do
    if Environment.use_local_storage?() do
      # For local storage, put directly to our local S3 controller
      bucket = Environment.s3_bucket_name()
      base_url = Environment.app_url()
      url = "#{base_url}/s3/#{bucket}/#{object_key}"

      case Req.put(url, body: content) do
        {:ok, %{status: 200}} -> :ok
        _ -> {:error, "Failed to put object"}
      end
    else
      Environment.s3_bucket_name()
      |> ExAws.S3.put_object(object_key, content)
      |> ExAws.request!()
    end
  end

  def object_exists?(object_key) do
    {time, exists} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          # For local storage, check file existence directly on filesystem
          bucket = Environment.s3_bucket_name()
          completed_dir = LocalS3.completed_directory()
          object_path = Path.join([completed_dir, bucket, object_key])
          File.exists?(object_path) && File.regular?(object_path)
        else
          case Environment.s3_bucket_name()
               |> ExAws.S3.head_object(object_key)
               |> ExAws.request() do
            {:ok, _} -> true
            {:error, _} -> false
          end
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_check_object_existence(),
      %{duration: time},
      %{object_key: object_key}
    )

    exists
  end

  def get_object_as_string(object_key) do
    {time, result} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          # For local storage, read directly from filesystem
          bucket = Environment.s3_bucket_name()
          completed_dir = LocalS3.completed_directory()
          object_path = Path.join([completed_dir, bucket, object_key])

          if File.exists?(object_path) && File.regular?(object_path) do
            File.read!(object_path)
          end
        else
          Environment.s3_bucket_name()
          |> ExAws.S3.get_object(object_key)
          |> ExAws.request()
          |> case do
            {:ok, %{body: content}} -> content
            {:error, {:http_error, 404, _}} -> nil
          end
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_get_object_as_string(),
      %{duration: time},
      %{object_key: object_key}
    )

    result
  end

  def multipart_start(object_key) do
    {time, upload_id} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          multipart_start_local(object_key)
        else
          multipart_start_remote(object_key)
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_start_upload(),
      %{duration: time},
      %{object_key: object_key}
    )

    upload_id
  end

  defp multipart_start_local(object_key) do
    bucket = Environment.s3_bucket_name()
    base_url = Environment.app_url()
    url = "#{base_url}/s3/#{bucket}/#{object_key}?uploads"

    case Req.post(url, headers: [{"content-type", "application/xml"}]) do
      {:ok, %{status: 200, body: body}} ->
        upload_id = xpath(body, ~x"//UploadId/text()"s)

        case upload_id do
          "" -> raise "Failed to parse upload ID from response: #{body}"
          _ -> upload_id
        end

      {:ok, %{status: status, body: body}} ->
        raise "Failed to initiate multipart upload - HTTP #{status}: #{inspect(body)}"

      {:error, reason} ->
        raise "Failed to initiate multipart upload - Request error: #{inspect(reason)}"
    end
  end

  defp multipart_start_remote(object_key) do
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
          # For local storage, we'd need to implement batch delete
          # For now, just return :ok as local storage is temporary
          :ok
        else
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
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_delete_all_objects(),
      %{duration: time},
      %{project_slug: prefix}
    )

    :ok
  end

  def get_object_size(object_key) do
    {time, size} =
      Performance.measure_time_in_milliseconds(fn ->
        if Environment.use_local_storage?() do
          # For local storage, get size directly from filesystem
          bucket = Environment.s3_bucket_name()
          completed_dir = LocalS3.completed_directory()
          object_path = Path.join([completed_dir, bucket, object_key])

          if File.exists?(object_path) && File.regular?(object_path) do
            %{size: size} = File.stat!(object_path)
            size
          else
            0
          end
        else
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
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_get_object_as_string_size(),
      %{duration: time, size: size},
      %{object_key: object_key}
    )

    size
  end
end
