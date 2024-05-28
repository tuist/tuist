defmodule TuistCloud.Storage do
  @moduledoc ~S"""
  A module that provides functions for storing and retrieving files from cloud storages
  """
  alias TuistCloud.Environment

  def generate_multipart_upload_url(object_key, upload_id, part_number, opts \\ []) do
    expires_in = opts |> Keyword.get(:expires_in, 3600)
    bucket = Environment.s3_bucket_name()

    {:ok, url} =
      ExAws.Config.new(:s3)
      |> ExAws.S3.presigned_url(:put, bucket, object_key,
        query_params: [
          {"partNumber", part_number},
          {"uploadId", upload_id}
        ],
        headers: [],
        virtual_host: true,
        expires_in: expires_in
      )

    url
  end

  def complete_multipart_upload(object_key, upload_id, parts) do
    {:ok, _} =
      Environment.s3_bucket_name()
      |> ExAws.S3.complete_multipart_upload(object_key, upload_id, parts)
      |> ExAws.request()

    :ok
  end

  def generate_download_url(object_key, opts \\ []) do
    expires_in = opts |> Keyword.get(:expires_in, 3600)

    {:ok, url} =
      ExAws.Config.new(:s3)
      |> ExAws.S3.presigned_url(:get, Environment.s3_bucket_name(), object_key,
        query_params: [],
        expires_in: expires_in,
        virtual_host: true
      )

    url
  end

  def exists(object_key) do
    case Environment.s3_bucket_name()
         |> ExAws.S3.head_object(object_key)
         |> ExAws.request() do
      {:ok, _} -> true
      _ -> false
    end
  end

  def multipart_start(object_key) do
    {:ok, response} =
      Environment.s3_bucket_name()
      |> ExAws.S3.initiate_multipart_upload(object_key)
      |> ExAws.request()

    response.body.upload_id
  end

  def delete_all_objects(project_slug) do
    bucket_name = Environment.s3_bucket_name()

    {:ok, %{body: %{contents: contents}}} =
      ExAws.S3.list_objects_v2(bucket_name, prefix: project_slug, max_keys: 1) |> ExAws.request()

    # Calling delete_all_objects when there are no objects with a given prefix returns a 400 error
    if contents == [] do
      :ok
    else
      stream =
        bucket_name
        |> ExAws.S3.list_objects_v2(prefix: project_slug)
        |> ExAws.stream!()
        |> Stream.map(& &1.key)

      {:ok, _} =
        bucket_name
        |> ExAws.S3.delete_all_objects(stream)
        |> ExAws.request()

      :ok
    end
  end

  def head_object(object_key) do
    {:ok, object} =
      Environment.s3_bucket_name() |> ExAws.S3.head_object(object_key) |> ExAws.request()

    %{
      content_length: String.to_integer(Map.new(object.headers)["Content-Length"])
    }
  end
end
