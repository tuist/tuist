defmodule Tuist.Storage.AzureBlob do
  @moduledoc false

  import SweetXml, only: [sigil_x: 2]

  alias Tuist.Environment

  @default_block_size 10 * 1024 * 1024
  @delete_objects_max_concurrency 4

  def multipart_generate_url(object_key, upload_id, part_number, opts \\ []) do
    presigned_url(object_key,
      permissions: "cw",
      expires_in: Keyword.get(opts, :expires_in, 3600),
      query_params: [
        {"comp", "block"},
        {"blockid", block_id(upload_id, part_number)}
      ]
    )
  end

  def multipart_complete_upload(object_key, upload_id, parts) do
    body =
      IO.iodata_to_binary([
        ~s(<?xml version="1.0" encoding="utf-8"?><BlockList>),
        parts
        |> Enum.sort_by(fn {part_number, _etag} -> part_number end)
        |> Enum.map(fn {part_number, _etag} -> ["<Latest>", block_id(upload_id, part_number), "</Latest>"] end),
        "</BlockList>"
      ])

    case request(:put, object_key,
           query_params: [{"comp", "blocklist"}],
           headers: [{"content-type", "application/xml"}],
           body: body
         ) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, multipart_complete_upload_error(reason)}
    end
  end

  def generate_download_url(object_key, opts \\ []) do
    presigned_url(object_key,
      permissions: "r",
      expires_in: Keyword.get(opts, :expires_in, 3600)
    )
  end

  def generate_upload_url(object_key, opts \\ []) do
    presigned_url(object_key,
      permissions: "cw",
      expires_in: Keyword.get(opts, :expires_in, 3600)
    )
  end

  def stream_object(object_key) do
    parent = self()
    ref = make_ref()

    Stream.resource(
      fn ->
        task =
          Task.async(fn ->
            object_key
            |> finch_request(:get)
            |> Finch.stream(Tuist.Finch, nil, fn
              {:status, status}, acc when status in 200..299 ->
                acc

              {:status, status}, acc ->
                send(parent, {ref, {:error, {:http_error, status}}})
                acc

              {:headers, _headers}, acc ->
                acc

              {:data, data}, acc ->
                send(parent, {ref, {:data, data}})
                acc
            end)
            |> case do
              {:ok, _acc} -> send(parent, {ref, :done})
              {:error, reason} -> send(parent, {ref, {:error, reason}})
            end
          end)

        {ref, task}
      end,
      fn {ref, task} = acc ->
        receive do
          {^ref, {:data, data}} ->
            {[data], acc}

          {^ref, :done} ->
            {:halt, acc}

          {^ref, {:error, reason}} ->
            Task.shutdown(task, :brutal_kill)
            raise "Azure Blob stream failed: #{inspect(reason)}"

          {:DOWN, _monitor_ref, :process, pid, _reason} when pid == task.pid ->
            {:halt, acc}
        end
      end,
      fn {_ref, task} ->
        Task.shutdown(task, :brutal_kill)
      end
    )
  end

  def upload(source, object_key) do
    upload_id = UUIDv7.generate()

    parts =
      source
      |> Stream.chunk_every(1)
      |> Stream.map(&IO.iodata_to_binary/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.with_index(1)
      |> Enum.map(fn {chunk, part_number} ->
        :ok = put_block(object_key, upload_id, part_number, chunk)
        {part_number, nil}
      end)

    if parts == [] do
      put_object(object_key, "")
    else
      multipart_complete_upload(object_key, upload_id, parts)
    end
  end

  def upload_file(file_path, object_key, opts \\ []) do
    block_size = Keyword.get(opts, :block_size, @default_block_size)

    file_path
    |> then(fn path -> File.stream!(path, block_size, []) end)
    |> upload(object_key)
  end

  def put_object(object_key, content) do
    request!(:put, object_key,
      headers: [
        {"content-type", "application/octet-stream"},
        {"x-ms-blob-type", "BlockBlob"}
      ],
      body: content
    )
  end

  def object_exists?(object_key) do
    case request(:head, object_key) do
      {:ok, _response} -> true
      {:error, _reason} -> false
    end
  end

  def download_to_file(object_key, file_path) do
    object_key
    |> stream_object()
    |> Stream.into(File.stream!(file_path))
    |> Stream.run()

    {:ok, :done}
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  def get_object_as_string(object_key) do
    case request(:get, object_key) do
      {:ok, %{body: content}} -> content
      {:error, {:http_error, 404, _response}} -> nil
      {:error, _reason} -> nil
    end
  end

  def multipart_start(_object_key), do: UUIDv7.generate()

  def delete_all_objects(prefix) do
    with {:ok, objects} <- list_all_objects(prefix) do
      delete_objects(Enum.map(objects, & &1.key))
    end
  end

  def delete_objects(object_keys, opts \\ [])
  def delete_objects([], _opts), do: :ok

  def delete_objects(object_keys, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @delete_objects_max_concurrency)

    object_keys
    |> Task.async_stream(&delete_object(&1, opts), max_concurrency: max_concurrency, ordered: false)
    |> Enum.reduce_while(:ok, fn
      {:ok, :ok}, :ok -> {:cont, :ok}
      {:ok, {:error, reason}}, :ok -> {:halt, {:error, reason}}
      {:exit, reason}, :ok -> {:halt, {:error, reason}}
    end)
  end

  def list_objects(container_name, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")
    max_keys = Keyword.get(opts, :max_keys, 1000)
    marker = Keyword.get(opts, :continuation_token)

    query_params =
      maybe_put_query_param(
        [{"restype", "container"}, {"comp", "list"}, {"prefix", prefix}, {"maxresults", to_string(max_keys)}],
        "marker",
        marker
      )

    case request(:get, nil, container_name: container_name, query_params: query_params) do
      {:ok, %{body: body}} ->
        {:ok, %{body: parse_list_objects_response(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_object_size(object_key) do
    case request(:head, object_key) do
      {:ok, response} ->
        {:ok, response |> response_header("content-length") |> String.to_integer()}

      {:error, {:http_error, 404, _response}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp put_block(object_key, upload_id, part_number, chunk) do
    case request(:put, object_key,
           query_params: [
             {"comp", "block"},
             {"blockid", block_id(upload_id, part_number)}
           ],
           body: chunk
         ) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_object(object_key, opts) do
    case request(:delete, object_key, container_name: Keyword.get(opts, :container_name, config().container_name)) do
      {:ok, _response} -> :ok
      {:error, {:http_error, 404, _response}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_all_objects(prefix, continuation_token \\ nil, acc \\ []) do
    case list_objects(config().container_name,
           prefix: prefix,
           max_keys: 5000,
           continuation_token: continuation_token
         ) do
      {:ok, %{body: %{contents: contents, next_continuation_token: nil}}} ->
        {:ok, acc ++ contents}

      {:ok, %{body: %{contents: contents, next_continuation_token: next_continuation_token}}} ->
        list_all_objects(prefix, next_continuation_token, acc ++ contents)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp presigned_url(object_key, opts) do
    config = config()
    expires_in = Keyword.fetch!(opts, :expires_in)
    permissions = Keyword.fetch!(opts, :permissions)
    resource = "b"
    protocol = signed_protocol(config.endpoint)
    expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second) |> format_iso8601()

    string_to_sign =
      Enum.join(
        [
          permissions,
          "",
          expires_at,
          canonicalized_sas_resource(config, object_key),
          "",
          "",
          protocol,
          config.service_version,
          resource,
          "",
          "",
          "",
          "",
          "",
          "",
          ""
        ],
        "\n"
      )

    sas_params =
      maybe_put_query_param(
        [
          {"sp", permissions},
          {"se", expires_at},
          {"sv", config.service_version},
          {"sr", resource},
          {"sig", sign(config.account_key, string_to_sign)}
        ],
        "spr",
        empty_to_nil(protocol)
      )

    object_key
    |> blob_url(config: config, query_params: Keyword.get(opts, :query_params, []) ++ sas_params)
    |> URI.to_string()
  end

  defp request!(method, object_key, opts) do
    case request(method, object_key, opts) do
      {:ok, response} -> response
      {:error, reason} -> raise "Azure Blob request failed: #{inspect(reason)}"
    end
  end

  defp request(method, object_key, opts \\ []) do
    req_opts =
      method
      |> signed_request_opts(object_key, opts)
      |> Keyword.merge(receive_timeout: Environment.s3_receive_timeout(), pool_timeout: Environment.s3_pool_timeout())

    case Req.request(req_opts) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %{status: status} = response} ->
        {:error, {:http_error, status, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finch_request(object_key, method, opts \\ []) do
    {url, headers, body} = signed_request_parts(method, object_key, opts)
    Finch.build(method, url, headers, body)
  end

  defp signed_request_opts(method, object_key, opts) do
    {url, headers, body} = signed_request_parts(method, object_key, opts)

    [
      method: method,
      url: url,
      headers: headers,
      body: body,
      decode_body: false,
      finch: Tuist.Finch
    ]
  end

  defp signed_request_parts(method, object_key, opts) do
    config = config()
    body = Keyword.get(opts, :body, "")
    content_length = IO.iodata_length(body)

    headers =
      opts
      |> Keyword.get(:headers, [])
      |> put_header("content-length", to_string(content_length))
      |> put_header("x-ms-date", rfc1123_now())
      |> put_header("x-ms-version", config.service_version)

    uri =
      blob_url(object_key,
        config: config,
        container_name: Keyword.get(opts, :container_name, config.container_name),
        query_params: Keyword.get(opts, :query_params, [])
      )

    authorization = authorization_header(config, method, uri, headers)
    headers = put_header(headers, "authorization", authorization)

    {URI.to_string(uri), headers, body}
  end

  defp authorization_header(config, method, uri, headers) do
    string_to_sign =
      Enum.join(
        [
          method |> to_string() |> String.upcase(),
          header_value(headers, "content-encoding"),
          header_value(headers, "content-language"),
          content_length_for_signature(headers),
          header_value(headers, "content-md5"),
          header_value(headers, "content-type"),
          "",
          header_value(headers, "if-modified-since"),
          header_value(headers, "if-match"),
          header_value(headers, "if-none-match"),
          header_value(headers, "if-unmodified-since"),
          header_value(headers, "range"),
          canonicalized_headers(headers) <> canonicalized_resource(config.account_name, uri)
        ],
        "\n"
      )

    "SharedKey #{config.account_name}:#{sign(config.account_key, string_to_sign)}"
  end

  defp canonicalized_headers(headers) do
    headers
    |> Enum.map(fn {key, value} -> {String.downcase(to_string(key)), normalize_header_value(value)} end)
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, "x-ms-") end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("", fn {key, value} -> "#{key}:#{value}\n" end)
  end

  defp canonicalized_resource(account_name, uri) do
    query =
      uri.query
      |> parse_query()
      |> Enum.group_by(fn {key, _value} -> String.downcase(key) end, fn {_key, value} -> value end)
      |> Enum.sort_by(fn {key, _values} -> key end)
      |> Enum.map_join("", fn {key, values} ->
        "\n#{key}:#{values |> Enum.sort() |> Enum.join(",")}"
      end)

    "/#{account_name}#{uri.path}#{query}"
  end

  defp canonicalized_sas_resource(config, object_key) do
    "/blob/#{config.account_name}/#{config.container_name}/#{object_key}"
  end

  defp blob_url(object_key, opts) do
    config = Keyword.fetch!(opts, :config)
    container_name = Keyword.get(opts, :container_name, config.container_name)
    query_params = Keyword.get(opts, :query_params, [])

    path =
      case object_key do
        nil -> "/#{container_name}"
        object_key -> "/#{container_name}/#{encode_blob_name(object_key)}"
      end

    config.endpoint
    |> URI.parse()
    |> Map.put(:path, path)
    |> Map.put(:query, query_string(query_params))
  end

  defp parse_list_objects_response(body) do
    contents =
      body
      |> SweetXml.xpath(~x"//Blobs/Blob"l,
        key: ~x"./Name/text()"s,
        last_modified: ~x"./Properties/Last-Modified/text()"s
      )
      |> Enum.map(fn object ->
        %{object | last_modified: parse_http_date(object.last_modified)}
      end)

    next_marker = SweetXml.xpath(body, ~x"string(//NextMarker)"s)

    %{
      contents: contents,
      is_truncated: next_marker != "",
      next_continuation_token: empty_to_nil(next_marker)
    }
  end

  defp parse_query(nil), do: []

  defp parse_query(query) do
    query
    |> String.split("&", trim: true)
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> {URI.decode_www_form(key), URI.decode_www_form(value)}
        [key] -> {URI.decode_www_form(key), ""}
      end
    end)
  end

  defp parse_http_date(nil), do: nil
  defp parse_http_date(""), do: nil

  defp parse_http_date(value) do
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      {{year, month, day}, {hour, minute, second}} ->
        year
        |> NaiveDateTime.new!(month, day, hour, minute, second)
        |> DateTime.from_naive!("Etc/UTC")

      _ ->
        nil
    end
  end

  defp response_header(response, header_name) do
    Enum.find_value(response.headers, fn
      {key, [value | _values]} when is_binary(key) -> if String.downcase(key) == header_name, do: value
      {key, value} when is_binary(key) -> if String.downcase(key) == header_name, do: value
      _header -> nil
    end)
  end

  defp header_value(headers, header_name) do
    Enum.find_value(headers, "", fn {key, value} ->
      if String.downcase(to_string(key)) == header_name do
        normalize_header_value(value)
      end
    end)
  end

  defp content_length_for_signature(headers) do
    case header_value(headers, "content-length") do
      "0" -> ""
      value -> value
    end
  end

  defp put_header(headers, key, value) do
    headers
    |> Enum.reject(fn {existing_key, _value} -> String.downcase(to_string(existing_key)) == key end)
    |> Kernel.++([{key, value}])
  end

  defp normalize_header_value(value) when is_list(value), do: value |> Enum.join(",") |> normalize_header_value()

  defp normalize_header_value(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.replace(~r/[\r\n\t ]+/, " ")
  end

  defp maybe_put_query_param(params, _key, nil), do: params
  defp maybe_put_query_param(params, _key, ""), do: params
  defp maybe_put_query_param(params, key, value), do: params ++ [{key, value}]

  defp query_string([]), do: nil

  defp query_string(query_params) do
    case URI.encode_query(query_params) do
      "" -> nil
      query -> query
    end
  end

  defp block_id(upload_id, part_number) do
    Base.encode64("#{upload_id}-#{String.pad_leading(to_string(part_number), 10, "0")}")
  end

  defp encode_blob_name(object_key) do
    object_key
    |> String.split("/")
    |> Enum.map_join("/", fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)
  end

  defp sign(account_key, string_to_sign) do
    :hmac
    |> :crypto.mac(:sha256, Base.decode64!(account_key), string_to_sign)
    |> Base.encode64()
  end

  defp config do
    %{
      account_name: required_config(:account_name, Environment.azure_storage_account_name()),
      account_key: required_config(:account_key, Environment.azure_storage_account_key()),
      container_name: required_config(:container_name, Environment.azure_blob_container_name()),
      endpoint: required_config(:endpoint, Environment.azure_blob_endpoint()),
      service_version: Environment.azure_blob_service_version()
    }
  end

  defp required_config(key, value) when value in [nil, ""] do
    raise "Azure Blob storage is missing #{key}. Configure the corresponding TUIST_AZURE_* environment variable."
  end

  defp required_config(_key, value), do: value

  defp rfc1123_now do
    Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")
  end

  defp format_iso8601(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp signed_protocol(endpoint) do
    case URI.parse(endpoint).scheme do
      "https" -> "https"
      _scheme -> ""
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(value), do: value

  defp multipart_complete_upload_error({:http_error, 400, %{body: body}} = reason) when is_binary(body) do
    if String.contains?(body, "<Code>InvalidBlockList</Code>") do
      :multipart_upload_not_found
    else
      reason
    end
  end

  defp multipart_complete_upload_error({:http_error, 404, _response}), do: :multipart_upload_not_found
  defp multipart_complete_upload_error(reason), do: reason
end
