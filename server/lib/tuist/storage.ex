defmodule Tuist.Storage do
  @moduledoc ~S"""
  A module that provides functions for storing and retrieving files from cloud storages
  """
  import SweetXml, only: [sigil_x: 2]

  alias ExAws.S3.Upload
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Performance
  alias Tuist.Storage.AzureBlob

  @delete_objects_max_concurrency 4
  @file_upload_chunk_max_attempts 3
  @file_upload_chunk_attempt_timeout 30_000

  def multipart_generate_url(object_key, upload_id, part_number, actor, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:query_params, [
        {"partNumber", part_number},
        {"uploadId", upload_id}
      ])
      |> Keyword.put(:actor, actor)

    url = presigned_url(:put, object_key, opts)

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

    case storage_provider(actor) do
      :azure_blob when method == :get ->
        AzureBlob.generate_download_url(object_key, opts)

      :azure_blob when method == :put and query_params == [] ->
        AzureBlob.generate_upload_url(object_key, opts)

      :azure_blob when method == :put ->
        upload_id = query_params |> Enum.find(fn {key, _value} -> key == "uploadId" end) |> elem(1)
        part_number = query_params |> Enum.find(fn {key, _value} -> key == "partNumber" end) |> elem(1)
        AzureBlob.multipart_generate_url(object_key, upload_id, part_number, opts)

      :s3 ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        presigned_url_opts = [
          query_params: query_params,
          expires_in: Keyword.get(opts, :expires_in, 3600)
        ]

        {:ok, url} =
          ExAws.S3.presigned_url(config, method, bucket_name, object_key, presigned_url_opts)

        url
    end
  end

  def multipart_complete_upload(object_key, upload_id, parts, actor) do
    {time, result} =
      Performance.measure_time_in_milliseconds(fn ->
        case storage_provider(actor) do
          :azure_blob ->
            AzureBlob.multipart_complete_upload(object_key, upload_id, parts)

          :s3 ->
            {config, bucket_name} = s3_config_and_bucket(actor)

            result =
              bucket_name
              |> ExAws.S3.complete_multipart_upload(object_key, upload_id, parts)
              |> ExAws.request(Map.merge(config, fast_api_req_opts()))

            case result do
              {:ok, _response} -> :ok
              {:error, reason} -> {:error, multipart_complete_upload_error(reason)}
            end
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_complete_upload(),
      %{duration: time, parts_count: Enum.count(parts)},
      %{object_key: object_key, upload_id: upload_id}
    )

    result
  end

  defp multipart_complete_upload_error({:http_error, 404, %{body: body}} = reason) when is_binary(body) do
    if multipart_upload_not_found?(body), do: :multipart_upload_not_found, else: reason
  end

  defp multipart_complete_upload_error(reason), do: reason

  defp multipart_upload_not_found?(body) do
    Regex.match?(~r/<(?:\w+:)?Code>\s*NoSuchUpload\s*<\/(?:\w+:)?Code>/, body)
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
    stream =
      case storage_provider(actor) do
        :azure_blob ->
          AzureBlob.stream_object(object_key)

        :s3 ->
          {config, bucket_name} = s3_config_and_bucket(actor)

          bucket_name
          |> ExAws.S3.download_file(object_key, :memory)
          |> ExAws.stream!(config)
      end

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_stream_object(),
      %{},
      %{object_key: object_key}
    )

    stream
  end

  def upload(source, object_key, actor) do
    case storage_provider(actor) do
      :azure_blob ->
        AzureBlob.upload(source, object_key)

      :s3 ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        source
        |> ExAws.S3.upload(bucket_name, object_key)
        |> ExAws.request!(config)
    end
  end

  def upload_file(file_path, object_key, actor, opts \\ []) do
    result =
      case storage_provider(actor) do
        :azure_blob ->
          AzureBlob.upload_file(file_path, object_key, opts)

        :s3 ->
          bucket_name = Keyword.get(opts, :bucket_name)
          s3_upload_file(file_path, object_key, actor, bucket_name)
      end

    normalize_upload_file_result(result)
  end

  def put_object(object_key, content, actor) do
    case storage_provider(actor) do
      :azure_blob ->
        AzureBlob.put_object(object_key, content)

      :s3 ->
        {config, bucket_name} = s3_config_and_bucket(actor)
        headers = region_headers(actor)

        operation =
          bucket_name
          |> ExAws.S3.put_object(object_key, content)
          |> Map.update(:headers, Map.new(headers), &Map.merge(&1, Map.new(headers)))

        ExAws.request!(operation, Map.merge(config, fast_api_req_opts()))
    end
  end

  def object_exists?(object_key, actor) do
    {time, exists} =
      Performance.measure_time_in_milliseconds(fn ->
        case storage_provider(actor) do
          :azure_blob ->
            AzureBlob.object_exists?(object_key)

          :s3 ->
            {config, bucket_name} = s3_config_and_bucket(actor)

            case bucket_name
                 |> ExAws.S3.head_object(object_key)
                 |> ExAws.request(Map.merge(config, fast_api_req_opts())) do
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

  def download_to_file(object_key, file_path, actor) do
    case storage_provider(actor) do
      :azure_blob ->
        AzureBlob.download_to_file(object_key, file_path)

      :s3 ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        bucket_name
        |> ExAws.S3.download_file(object_key, file_path)
        |> ExAws.request(Map.merge(config, fast_api_req_opts()))
    end
  catch
    # ExAws downloads each chunk in a Task.async_stream whose per-chunk timeout
    # exits rather than raising, so a stalled S3 chunk escapes ExAws' own rescue
    # and would crash the calling job. Surface it as a retryable error instead.
    :exit, reason -> {:error, reason}
  end

  def get_object_as_string(object_key, actor) do
    {time, result} =
      Performance.measure_time_in_milliseconds(fn ->
        case storage_provider(actor) do
          :azure_blob ->
            {:ok, %{body: AzureBlob.get_object_as_string(object_key)}}

          :s3 ->
            {config, bucket_name} = s3_config_and_bucket(actor)

            bucket_name
            |> ExAws.S3.get_object(object_key)
            |> ExAws.request(Map.merge(config, fast_api_req_opts()))
        end
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
        case storage_provider(actor) do
          :azure_blob ->
            AzureBlob.multipart_start(object_key)

          :s3 ->
            {config, bucket_name} = s3_config_and_bucket(actor)
            headers = region_headers(actor)

            operation =
              bucket_name
              |> ExAws.S3.initiate_multipart_upload(object_key)
              |> Map.put(:headers, Map.new(headers))

            %{body: %{upload_id: upload_id}} = ExAws.request!(operation, Map.merge(config, fast_api_req_opts()))

            upload_id
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_multipart_start_upload(),
      %{duration: time},
      %{object_key: object_key}
    )

    upload_id
  end

  def delete_all_objects(prefix, actor) do
    {time, result} =
      Performance.measure_time_in_milliseconds(fn ->
        case storage_provider(actor) do
          :azure_blob ->
            AzureBlob.delete_all_objects(prefix)

          :s3 ->
            s3_delete_all_objects(prefix, actor)
        end
      end)

    :telemetry.execute(
      Tuist.Telemetry.event_name_storage_delete_all_objects(),
      %{duration: time},
      %{project_slug: prefix}
    )

    result
  end

  def delete_object(object_key, actor) do
    delete_objects([object_key], actor)
  end

  def delete_objects(object_keys, actor, opts \\ [])

  def delete_objects([], _actor, _opts), do: :ok

  def delete_objects(object_keys, actor, opts) do
    case storage_provider(actor) do
      :azure_blob ->
        AzureBlob.delete_objects(object_keys, opts)

      :s3 ->
        {config, bucket_name} = s3_config_and_bucket(actor)
        delete_objects_from_bucket(object_keys, bucket_name, config, opts)
    end
  end

  def delete_objects_from_bucket(object_keys, bucket_name, opts \\ [])

  def delete_objects_from_bucket([], _bucket_name, _opts), do: :ok

  def delete_objects_from_bucket(object_keys, bucket_name, opts) do
    case Keyword.get(opts, :storage_provider, :s3) do
      :azure_blob -> AzureBlob.delete_objects(object_keys, Keyword.put(opts, :container_name, bucket_name))
      :s3 -> delete_objects_from_bucket(object_keys, bucket_name, ExAws.Config.new(:s3), opts)
    end
  end

  def list_objects_from_bucket(bucket_name, opts \\ []) do
    case Keyword.get(opts, :storage_provider, :s3) do
      :azure_blob ->
        AzureBlob.list_objects(bucket_name, opts)

      :s3 ->
        prefix = Keyword.get(opts, :prefix, "")
        max_keys = Keyword.get(opts, :max_keys, 1000)
        continuation_token = Keyword.get(opts, :continuation_token)

        list_opts = maybe_put_continuation_token([prefix: prefix, max_keys: max_keys], continuation_token)

        bucket_name
        |> ExAws.S3.list_objects_v2(list_opts)
        |> ExAws.request(Map.merge(ExAws.Config.new(:s3), fast_api_req_opts()))
    end
  end

  defp delete_objects_from_bucket(object_keys, bucket_name, config, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @delete_objects_max_concurrency)
    request_opts = fast_api_req_opts(opts)
    task_timeout = Keyword.get(opts, :task_timeout, request_timeout(request_opts))

    object_keys
    |> Enum.chunk_every(1000)
    |> Task.async_stream(
      fn object_keys_chunk ->
        bucket_name
        |> ExAws.S3.delete_multiple_objects(object_keys_chunk)
        |> ExAws.request(Map.merge(config, request_opts))
        |> handle_delete_objects_response()
      end,
      max_concurrency: max_concurrency,
      ordered: false,
      timeout: task_timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while(:ok, fn
      {:ok, :ok}, :ok ->
        {:cont, :ok}

      {:ok, {:error, reason}}, :ok ->
        {:halt, {:error, reason}}

      {:exit, reason}, :ok ->
        {:halt, {:error, reason}}
    end)
  end

  defp handle_delete_objects_response({:ok, response}) do
    case delete_object_errors(response) do
      [] ->
        if successful_delete_objects_response?(response) do
          :ok
        else
          {:error, {:unexpected_response, response}}
        end

      errors ->
        {:error, {:delete_objects_failed, errors}}
    end
  end

  defp handle_delete_objects_response({:error, reason}), do: {:error, reason}

  defp successful_delete_objects_response?(%{status_code: status_code}) when status_code in 200..299, do: true
  defp successful_delete_objects_response?(%{status_code: _status_code}), do: false
  defp successful_delete_objects_response?(%{body: %{deleted: _deleted}}), do: true
  defp successful_delete_objects_response?(%{body: %{"Deleted" => _deleted}}), do: true
  defp successful_delete_objects_response?(_response), do: false

  defp delete_object_errors(%{body: body}), do: delete_object_errors(body)
  defp delete_object_errors(%{errors: errors}), do: normalize_delete_errors(errors)
  defp delete_object_errors(%{error: error}), do: normalize_delete_errors(error)
  defp delete_object_errors(%{"Errors" => errors}), do: normalize_delete_errors(errors)
  defp delete_object_errors(%{"Error" => error}), do: normalize_delete_errors(error)
  defp delete_object_errors(%{"errors" => errors}), do: normalize_delete_errors(errors)
  defp delete_object_errors(%{"error" => error}), do: normalize_delete_errors(error)

  defp delete_object_errors(body) when is_binary(body) do
    SweetXml.xpath(body, ~x"//Error"l,
      key: ~x"./Key/text()"s,
      version_id: ~x"./VersionId/text()"s,
      code: ~x"./Code/text()"s,
      message: ~x"./Message/text()"s
    )
  rescue
    _error -> []
  end

  defp delete_object_errors(_body), do: []

  defp normalize_delete_errors(nil), do: []
  defp normalize_delete_errors([]), do: []

  defp normalize_delete_errors(errors) when is_list(errors) do
    Enum.reject(errors, &empty_delete_error?/1)
  end

  defp normalize_delete_errors(error) do
    if empty_delete_error?(error), do: [], else: [error]
  end

  defp empty_delete_error?(nil), do: true
  defp empty_delete_error?(""), do: true
  defp empty_delete_error?(%{} = error), do: map_size(error) == 0
  defp empty_delete_error?(_error), do: false

  defp maybe_put_continuation_token(opts, nil), do: opts

  defp maybe_put_continuation_token(opts, continuation_token),
    do: Keyword.put(opts, :continuation_token, continuation_token)

  def get_object_size(object_key, actor) do
    case get_object_size_result(object_key, actor) do
      {:ok, response} ->
        {time, size} =
          Performance.measure_time_in_milliseconds(fn ->
            object_size_from_response(response, actor)
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

  defp get_object_size_result(object_key, actor) do
    case storage_provider(actor) do
      :azure_blob ->
        AzureBlob.get_object_size(object_key)

      :s3 ->
        {config, bucket_name} = s3_config_and_bucket(actor)

        bucket_name
        |> ExAws.S3.head_object(object_key)
        |> ExAws.request(Map.merge(config, fast_api_req_opts()))
    end
  end

  defp object_size_from_response(response, actor) do
    case storage_provider(actor) do
      :azure_blob -> response
      :s3 -> s3_object_size_from_response(response)
    end
  end

  defp s3_object_size_from_response(response) do
    response
    |> Map.get(:headers)
    |> Enum.find(fn {key, _value} -> key == "content-length" end)
    |> elem(1)
    |> List.first()
    |> String.to_integer()
  end

  defp s3_config_and_bucket(actor) do
    if has_custom_storage?(actor) do
      {custom_s3_config(actor), actor.s3_bucket_name}
    else
      {ExAws.Config.new(:s3), Environment.s3_bucket_name()}
    end
  end

  defp storage_provider(actor) do
    if has_custom_storage?(actor) do
      :s3
    else
      Environment.object_storage_provider()
    end
  end

  defp normalize_upload_file_result({:ok, _response} = result), do: result
  defp normalize_upload_file_result({:error, _reason} = result), do: result
  defp normalize_upload_file_result(:ok), do: {:ok, :done}
  defp normalize_upload_file_result(response), do: {:ok, response}

  defp s3_delete_all_objects(prefix, actor) do
    {config, bucket_name} = s3_config_and_bucket(actor)

    if s3_objects_with_prefix?(bucket_name, prefix, config) do
      s3_delete_all_objects_with_prefix(bucket_name, prefix, config)
    else
      :ok
    end
  end

  defp s3_objects_with_prefix?(bucket_name, prefix, config) do
    bucket_name
    |> ExAws.S3.list_objects_v2(prefix: prefix, max_keys: 1)
    |> ExAws.request!(config)
    |> Map.get(:body)
    |> Map.get(:contents)
    |> Enum.any?()
  end

  defp s3_delete_all_objects_with_prefix(bucket_name, prefix, config) do
    stream =
      bucket_name
      |> ExAws.S3.list_objects_v2(prefix: prefix, max_keys: 1000)
      |> ExAws.stream!(config)
      |> Stream.map(& &1.key)

    case bucket_name |> ExAws.S3.delete_all_objects(stream) |> ExAws.request(config) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp s3_upload_file(file_path, object_key, actor, bucket_name_override) do
    {config, bucket_name} = s3_config_and_bucket(actor)
    bucket_name = bucket_name_override || bucket_name

    with {:ok, %{body: %{upload_id: upload_id}}} <-
           bucket_name
           |> ExAws.S3.initiate_multipart_upload(object_key)
           |> ExAws.request(config),
         {:ok, parts} <- s3_upload_file_parts(file_path, bucket_name, object_key, upload_id, config) do
      bucket_name
      |> ExAws.S3.complete_multipart_upload(object_key, upload_id, parts)
      |> ExAws.request(config)
    end
  end

  defp s3_upload_file_parts(file_path, bucket_name, object_key, upload_id, config) do
    results =
      file_path
      |> Upload.stream_file()
      |> Stream.with_index(1)
      |> Task.async_stream(
        fn chunk -> s3_upload_file_part_with_retry(chunk, bucket_name, object_key, upload_id, config, 1) end,
        max_concurrency: 4,
        timeout: @file_upload_chunk_attempt_timeout * @file_upload_chunk_max_attempts + 5_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, value} -> value
        {:exit, reason} -> {:error, {:chunk_task_exit, reason}}
      end)

    cond do
      results == [] ->
        s3_upload_empty_file_part(bucket_name, object_key, upload_id, config)

      error = Enum.find(results, &match?({:error, _}, &1)) ->
        bucket_name
        |> ExAws.S3.abort_multipart_upload(object_key, upload_id)
        |> ExAws.request(config)

        error

      true ->
        {:ok, results}
    end
  end

  defp s3_upload_empty_file_part(bucket_name, object_key, upload_id, config) do
    case s3_upload_file_part_with_retry({"", 1}, bucket_name, object_key, upload_id, config, 1) do
      {:error, _reason} = error ->
        bucket_name
        |> ExAws.S3.abort_multipart_upload(object_key, upload_id)
        |> ExAws.request(config)

        error

      part ->
        {:ok, [part]}
    end
  end

  defp s3_upload_file_part_with_retry({chunk, index}, bucket_name, object_key, upload_id, config, attempt)
       when attempt < @file_upload_chunk_max_attempts do
    case s3_attempt_file_part_upload(chunk, index, bucket_name, object_key, upload_id, config) do
      {:ok, etag} -> {index, etag}
      _error -> s3_upload_file_part_with_retry({chunk, index}, bucket_name, object_key, upload_id, config, attempt + 1)
    end
  end

  defp s3_upload_file_part_with_retry({chunk, index}, bucket_name, object_key, upload_id, config, _attempt) do
    case s3_attempt_file_part_upload(chunk, index, bucket_name, object_key, upload_id, config) do
      {:ok, etag} -> {index, etag}
      other -> {:error, other}
    end
  end

  defp s3_attempt_file_part_upload(chunk, index, bucket_name, object_key, upload_id, config) do
    task =
      Task.async(fn ->
        bucket_name
        |> ExAws.S3.upload_part(object_key, upload_id, index, chunk)
        |> ExAws.request(config)
      end)

    case Task.yield(task, @file_upload_chunk_attempt_timeout) || Task.shutdown(task) do
      nil ->
        :timeout

      {:ok, {:ok, %{headers: headers}}} ->
        etag = Enum.find_value(headers, fn {key, value} -> if String.downcase(key) == "etag", do: value end)
        {:ok, etag}

      {:ok, {:error, reason}} ->
        {:error, reason}

      {:exit, reason} ->
        {:exit, reason}
    end
  end

  defp has_custom_storage?(actor), do: Account.custom_s3_storage_configured?(actor)

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

  defp fast_api_req_opts(opts \\ []) do
    %{
      receive_timeout: Keyword.get(opts, :receive_timeout, 5_000),
      pool_timeout: Keyword.get(opts, :pool_timeout, 1_000)
    }
  end

  defp request_timeout(request_opts) do
    case {Map.fetch!(request_opts, :receive_timeout), Map.fetch!(request_opts, :pool_timeout)} do
      {:infinity, _pool_timeout} -> :infinity
      {_receive_timeout, :infinity} -> :infinity
      {receive_timeout, pool_timeout} -> receive_timeout + pool_timeout + 1_000
    end
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
