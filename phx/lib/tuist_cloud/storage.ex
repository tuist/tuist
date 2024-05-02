defmodule TuistCloud.Storage do
  @moduledoc ~S"""
  A module that provides functions for storing and retrieving files from cloud storages
  """
  alias TuistCloud.Environment

  def generate_multipart_upload_url(item, upload_id, part_number, opts \\ []) do
    expires_in = opts |> Keyword.get(:expires_in, 3600)
    key = object_key(item)
    bucket = Environment.s3_bucket_name()

    {:ok, url} =
      ExAws.Config.new(:s3)
      |> ExAws.S3.presigned_url(:put, bucket, key,
        query_params: [
          {"partNumber", String.to_integer(part_number)},
          {"uploadId", upload_id}
        ],
        headers: [],
        virtual_host: true,
        expires_in: expires_in
      )

    url
  end

  def complete_multipart_upload(item, upload_id, parts) do
    {:ok, _} =
      Environment.s3_bucket_name()
      |> ExAws.S3.complete_multipart_upload(object_key(item), upload_id, parts)
      |> ExAws.request()

    :ok
  end

  def generate_download_url(item, opts \\ []) do
    expires_in = opts |> Keyword.get(:expires_in, 3600)

    {:ok, url} =
      ExAws.Config.new(:s3)
      |> ExAws.S3.presigned_url(:get, Environment.s3_bucket_name(), object_key(item),
        query_params: [],
        expires_in: expires_in,
        virtual_host: true
      )

    url
  end

  def exists(item) do
    case Environment.s3_bucket_name()
         |> ExAws.S3.head_object(object_key(item))
         |> ExAws.request() do
      {:ok, _} -> true
      _ -> false
    end
  end

  def multipart_start(item) do
    {:ok, response} =
      Environment.s3_bucket_name()
      |> ExAws.S3.initiate_multipart_upload(object_key(item))
      |> ExAws.request()

    response.body.upload_id
  end

  def object_key(%{
        hash: hash,
        cache_category: cache_category,
        name: name,
        project_slug: project_slug
      }) do
    if cache_category != nil do
      "#{project_slug}/#{cache_category}/#{hash}/#{name}"
    else
      "#{project_slug}/#{hash}/#{name}"
    end
  end

  def delete_all_objects(project_slug) do
    bucket_name = Environment.s3_bucket_name()

    stream =
      bucket_name
      |> ExAws.S3.list_objects(prefix: project_slug)
      |> ExAws.stream!()
      |> Stream.map(& &1.key)

    {:ok, _} =
      bucket_name
      |> ExAws.S3.delete_all_objects(stream)
      |> ExAws.request()
  end

  def get_object(item) do
    {:ok, object} =
      Environment.s3_bucket_name() |> ExAws.S3.get_object(object_key(item)) |> ExAws.request()

    %{
      content_length: String.to_integer(Map.new(object.headers)["Content-Length"])
    }
  end
end
