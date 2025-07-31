defmodule TuistWeb.LocalS3Controller do
  use TuistWeb, :controller

  import SweetXml

  alias Tuist.Storage.LocalS3

  require Logger

  defp uploads_dir do
    LocalS3.uploads_directory()
  end

  defp completed_dir do
    LocalS3.completed_directory()
  end

  def init(opts), do: opts

  def put_object(conn, %{"bucket" => bucket, "key" => key} = params) do
    # Check query params for multipart upload
    query_params = conn.query_params

    if Map.has_key?(query_params, "uploadId") && Map.has_key?(query_params, "partNumber") do
      # This is a multipart upload part
      upload_part(conn, Map.merge(params, query_params))
    else
      ensure_storage_dirs()

      object_path = get_object_path(bucket, key)
      ensure_parent_dir(object_path)

      case read_full_body(conn) do
        {:ok, body, conn} ->
          File.write!(object_path, body)

          conn
          |> put_status(200)
          |> send_resp(200, "")

        {:error, _reason} ->
          conn
          |> put_status(400)
          |> json(%{error: "Failed to read request body"})
      end
    end
  end

  def get_object(conn, %{"bucket" => bucket, "key" => key}) do
    object_path = get_object_path(bucket, key)

    if File.exists?(object_path) do
      content = File.read!(object_path)

      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("content-length", to_string(byte_size(content)))
      |> send_resp(200, content)
    else
      conn
      |> put_status(404)
      |> send_resp(404, "")
    end
  end

  def head_object(conn, %{"bucket" => bucket, "key" => key}) do
    object_path = get_object_path(bucket, key)

    if File.exists?(object_path) do
      stat = File.stat!(object_path)

      conn
      |> put_resp_header("content-length", to_string(stat.size))
      |> send_resp(200, "")
    else
      conn
      |> put_status(404)
      |> send_resp(404, "")
    end
  end

  def post_object(conn, %{"bucket" => _bucket, "key" => _key} = params) do
    # Check query params to determine operation type
    query_params = conn.query_params

    cond do
      Map.has_key?(query_params, "uploads") ->
        # This is an initiate multipart upload request
        initiate_multipart_upload(conn, params)

      Map.has_key?(query_params, "uploadId") ->
        # This is a complete multipart upload request
        complete_multipart_upload(conn, Map.merge(params, query_params))

      true ->
        # Unknown POST operation
        conn
        |> put_status(400)
        |> json(%{error: "Unknown operation"})
    end
  end

  def delete_objects(conn, %{"bucket" => bucket}) do
    {:ok, body, conn} = read_full_body(conn)
    {:ok, doc} = parse_delete_xml(body)

    objects = extract_objects_to_delete(doc)

    results =
      Enum.map(objects, fn key ->
        object_path = get_object_path(bucket, key)

        if File.exists?(object_path) do
          File.rm!(object_path)
          {key, :deleted}
        else
          {key, :not_found}
        end
      end)

    response_xml = build_delete_response(results)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, response_xml)
  end

  def list_objects_v2(conn, %{"bucket" => bucket} = params) do
    prefix = Map.get(params, "prefix", "")
    max_keys = String.to_integer(Map.get(params, "max-keys", "1000"))

    bucket_path = Path.join(completed_dir(), bucket)

    objects =
      if File.exists?(bucket_path) do
        list_files_with_prefix(bucket_path, prefix, max_keys)
      else
        []
      end

    response_xml = build_list_response(bucket, prefix, objects)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, response_xml)
  end

  # Multipart upload operations
  def initiate_multipart_upload(conn, %{"bucket" => bucket, "key" => key}) do
    ensure_storage_dirs()
    upload_id = generate_upload_id()

    multipart_dir = get_multipart_dir(bucket, key, upload_id)
    File.mkdir_p!(multipart_dir)

    # Store metadata about the upload
    metadata = %{
      bucket: bucket,
      key: key,
      started_at: DateTime.utc_now(),
      parts: %{}
    }

    metadata_path = Path.join(multipart_dir, "metadata.json")
    File.write!(metadata_path, Jason.encode!(metadata))

    response_xml = build_initiate_multipart_response(bucket, key, upload_id)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, response_xml)
  end

  def upload_part(conn, %{"bucket" => bucket, "key" => key, "uploadId" => upload_id, "partNumber" => part_number}) do
    multipart_dir = get_multipart_dir(bucket, key, upload_id)

    if File.exists?(multipart_dir) do
      {:ok, body, conn} = read_full_body(conn)

      part_path = Path.join(multipart_dir, "part_#{part_number}")
      File.write!(part_path, body)

      # Calculate ETag (simplified - just use MD5 for local storage)
      etag = :md5 |> :crypto.hash(body) |> Base.encode16() |> String.downcase()

      conn
      |> put_resp_header("etag", "\"#{etag}\"")
      |> send_resp(200, "")
    else
      conn
      |> put_status(404)
      |> send_resp(404, "")
    end
  end

  def complete_multipart_upload(conn, %{"bucket" => bucket, "key" => key, "uploadId" => upload_id}) do
    multipart_dir = get_multipart_dir(bucket, key, upload_id)

    if File.exists?(multipart_dir) do
      {:ok, body, conn} = read_full_body(conn)
      {:ok, parts_info} = parse_complete_multipart_xml(body)

      # Combine all parts
      object_path = get_object_path(bucket, key)
      ensure_parent_dir(object_path)

      output_file = File.open!(object_path, [:write, :binary])

      parts_info
      |> Enum.sort_by(fn {part_number, _etag} -> part_number end)
      |> Enum.each(fn {part_number, _etag} ->
        part_path = Path.join(multipart_dir, "part_#{part_number}")
        content = File.read!(part_path)
        IO.binwrite(output_file, content)
      end)

      File.close(output_file)

      # Clean up multipart directory and all parent directories up to uploads root
      File.rm_rf!(multipart_dir)
      cleanup_empty_parent_dirs(multipart_dir, uploads_dir())

      # Calculate final ETag
      final_content = File.read!(object_path)
      etag = :md5 |> :crypto.hash(final_content) |> Base.encode16() |> String.downcase()

      response_xml = build_complete_multipart_response(bucket, key, etag)

      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, response_xml)
    else
      conn
      |> put_status(404)
      |> send_resp(404, "")
    end
  end

  # Private helper functions
  defp ensure_storage_dirs do
    File.mkdir_p!(uploads_dir())
    File.mkdir_p!(completed_dir())
  end

  defp get_object_path(bucket, key) do
    # Handle key as either string or list (from wildcard route)
    key_string =
      case key do
        key when is_list(key) -> Enum.join(key, "/")
        key when is_binary(key) -> key
      end

    # Ensure key uses forward slashes and map to directory hierarchy
    normalized_key = String.replace(key_string, ~r/[\\]+/, "/")
    Path.join([completed_dir(), bucket, normalized_key])
  end

  defp get_multipart_dir(bucket, key, upload_id) do
    # Handle key as either string or list (from wildcard route)
    key_string =
      case key do
        key when is_list(key) -> Enum.join(key, "/")
        key when is_binary(key) -> key
      end

    # Ensure key uses forward slashes
    normalized_key = String.replace(key_string, ~r/[\\]+/, "/")
    Path.join([uploads_dir(), bucket, normalized_key, upload_id])
  end

  defp ensure_parent_dir(path) do
    path |> Path.dirname() |> File.mkdir_p!()
  end

  defp generate_upload_id do
    16 |> :crypto.strong_rand_bytes() |> Base.encode16() |> String.downcase()
  end

  defp read_full_body(conn, body \\ "") do
    case Plug.Conn.read_body(conn) do
      {:ok, data, conn} ->
        {:ok, body <> data, conn}

      {:more, data, conn} ->
        read_full_body(conn, body <> data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_delete_xml(xml) do
    {:ok, xml}
  end

  defp extract_objects_to_delete(xml) do
    xpath(xml, ~x"//Object/Key/text()"sl)
  end

  defp build_delete_response(results) do
    deleted_objects =
      results
      |> Enum.filter(fn {_key, status} -> status == :deleted end)
      |> Enum.map_join("\n", fn {key, _} -> "<Deleted><Key>#{key}</Key></Deleted>" end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <DeleteResult>
      #{deleted_objects}
    </DeleteResult>
    """
  end

  defp build_initiate_multipart_response(bucket, key, upload_id) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <InitiateMultipartUploadResult>
      <Bucket>#{bucket}</Bucket>
      <Key>#{key}</Key>
      <UploadId>#{upload_id}</UploadId>
    </InitiateMultipartUploadResult>
    """
  end

  defp build_complete_multipart_response(bucket, key, etag) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <CompleteMultipartUploadResult>
      <Location>http://localhost:8080/s3/#{bucket}/#{key}</Location>
      <Bucket>#{bucket}</Bucket>
      <Key>#{key}</Key>
      <ETag>"#{etag}"</ETag>
    </CompleteMultipartUploadResult>
    """
  end

  defp list_files_with_prefix(bucket_path, prefix, max_keys) do
    bucket_path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(fn path ->
      key = Path.relative_to(path, bucket_path)
      stat = File.stat!(path)

      if String.starts_with?(key, prefix) do
        %{
          key: key,
          size: stat.size,
          last_modified: stat.mtime |> elem(0) |> DateTime.from_unix!()
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(max_keys)
  end

  defp build_list_response(bucket, prefix, objects) do
    contents =
      Enum.map_join(objects, "\n", fn obj ->
        """
        <Contents>
          <Key>#{obj.key}</Key>
          <Size>#{obj.size}</Size>
          <LastModified>#{DateTime.to_iso8601(obj.last_modified)}</LastModified>
        </Contents>
        """
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <ListBucketResult>
      <Name>#{bucket}</Name>
      <Prefix>#{prefix}</Prefix>
      <MaxKeys>1000</MaxKeys>
      <IsTruncated>false</IsTruncated>
      #{contents}
    </ListBucketResult>
    """
  end

  defp parse_complete_multipart_xml(xml) do
    parts =
      xml
      |> xpath(
        ~x"//Part"l,
        part_number: transform_by(~x"./PartNumber/text()"s, &String.to_integer/1),
        etag: ~x"./ETag/text()"s
      )
      |> Enum.map(fn %{part_number: part_number, etag: etag} ->
        {part_number, etag}
      end)

    {:ok, parts}
  end

  defp cleanup_empty_parent_dirs(dir, stop_at) do
    parent = Path.dirname(dir)

    if parent != stop_at and parent != "/" and parent != "." do
      case File.ls(parent) do
        {:ok, []} ->
          File.rmdir(parent)
          cleanup_empty_parent_dirs(parent, stop_at)

        _ ->
          :ok
      end
    end
  end
end
