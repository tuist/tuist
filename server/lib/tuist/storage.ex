defmodule Tuist.Storage do
  @moduledoc ~S"""
  A module that provides functions for storing and retrieving files from cloud storages
  """
  alias Tuist.Accounts.Account
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

    presigned_url_opts = [
      query_params: query_params,
      expires_in: Keyword.get(opts, :expires_in, 3600)
    ]

    {:ok, url} =
      ExAws.S3.presigned_url(config, method, bucket_name, object_key, presigned_url_opts)

    url
  end

  def multipart_complete_upload(object_key, upload_id, parts, actor) do
    {time, result} =
      Performance.measure_time_in_milliseconds(fn ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        bucket_name
        |> ExAws.S3.complete_multipart_upload(object_key, upload_id, parts)
        |> ExAws.request!(Map.merge(config, fast_api_req_opts()))

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
    headers = region_headers(actor)

    operation =
      bucket_name
      |> ExAws.S3.put_object(object_key, content)
      |> Map.update(:headers, Map.new(headers), &Map.merge(&1, Map.new(headers)))

    ExAws.request!(operation, Map.merge(config, fast_api_req_opts()))
  end

  def object_exists?(object_key, actor) do
    {time, exists} =
      Performance.measure_time_in_milliseconds(fn ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        case bucket_name
             |> ExAws.S3.head_object(object_key)
             |> ExAws.request(Map.merge(config, fast_api_req_opts())) do
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
        |> ExAws.request(Map.merge(config, fast_api_req_opts()))
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
        headers = region_headers(actor)

        operation =
          bucket_name
          |> ExAws.S3.initiate_multipart_upload(object_key)
          |> Map.put(:headers, Map.new(headers))

        %{body: %{upload_id: upload_id}} = ExAws.request!(operation, Map.merge(config, fast_api_req_opts()))

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
    {config, bucket_name} = s3_config_and_bucket(actor)

    case bucket_name
         |> ExAws.S3.head_object(object_key)
         |> ExAws.request(Map.merge(config, fast_api_req_opts())) do
      {:ok, response} ->
        {time, size} =
          Performance.measure_time_in_milliseconds(fn ->
            response
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

        {:ok, size}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp s3_config_and_bucket(actor) do
    if has_custom_storage?(actor) do
      {custom_s3_config(actor), actor.s3_bucket_name}
    else
      {ExAws.Config.new(:s3), Environment.s3_bucket_name()}
    end
  end

  defp has_custom_storage?(%Account{
         s3_bucket_name: bucket,
         s3_access_key_id: access_key,
         s3_secret_access_key: secret_key
       })
       when not is_nil(bucket) and not is_nil(access_key) and not is_nil(secret_key), do: true

  defp has_custom_storage?(_), do: false

  defp custom_s3_config(%Account{} = account) do
    base_config = %{
      access_key_id: account.s3_access_key_id,
      secret_access_key: account.s3_secret_access_key,
      region: account.s3_region || "us-east-1"
    }

    if account.s3_endpoint do
      uri = URI.parse(account.s3_endpoint)

      base_config
      |> Map.put(:scheme, "#{uri.scheme}://")
      |> Map.put(:host, uri.host)
      |> Map.put(:port, uri.port)
    else
      base_config
    end
  end

  defp fast_api_req_opts do
    %{
      receive_timeout: 5_000,
      pool_timeout: 1_000
    }
  end

  defp region_headers(actor) do
    if has_custom_storage?(actor) do
      []
    else
      case actor do
        %Account{region: :europe} ->
          [{"X-Tigris-Regions", "eur"}]

        %Account{region: :usa} ->
          [{"X-Tigris-Regions", "usa"}]

        _ ->
          []
      end
    end
  end
end
