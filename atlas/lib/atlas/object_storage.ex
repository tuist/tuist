defmodule Atlas.ObjectStorage do
  @moduledoc """
  S3-compatible object storage client.

  Production is wired to Hetzner Object Storage through runtime config, but the
  implementation stays generic so tests and future environments can point at any
  S3-compatible endpoint.
  """

  alias AWSAuth.Credentials

  @service "s3"
  @config_keys [
    :endpoint_url,
    :region,
    :bucket,
    :access_key_id,
    :secret_access_key,
    :public_base_url
  ]

  defstruct [
    :endpoint_url,
    :region,
    :bucket,
    :access_key_id,
    :secret_access_key,
    :public_base_url
  ]

  def put_object(key, body, opts \\ []) when is_binary(key) and is_binary(body) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    request(:put, key,
      body: body,
      headers: [{"content-type", content_type}],
      config: Keyword.get(opts, :config),
      request: Keyword.get(opts, :request, &Req.request/1),
      success_statuses: [200, 201, 204]
    )
  end

  def get_object(key, opts \\ []) when is_binary(key) do
    with {:ok, response} <- request(:get, key, Keyword.put(opts, :success_statuses, [200])) do
      {:ok,
       %{
         body: response.body,
         content_type: content_type(response.headers),
         key: key
       }}
    end
  end

  def head_object(key, opts \\ []) when is_binary(key) do
    request(:head, key, Keyword.put(opts, :success_statuses, [200]))
  end

  def delete_object(key, opts \\ []) when is_binary(key) do
    request(:delete, key, Keyword.put(opts, :success_statuses, [200, 202, 204]))
  end

  @doc """
  Returns a short-lived, SigV4-signed URL that lets a client `PUT` the object
  directly. When `:content_type` is given it is bound into the signature: the
  client MUST send the same `Content-Type` header at upload time or the store
  rejects the request. Defaults to a 1 hour expiry, capped at 7 days by SigV4.
  """
  def presigned_put_url(key, opts \\ []) when is_binary(key) do
    config = config!(opts)
    url = object_url(config, key)

    headers =
      case Keyword.get(opts, :content_type) do
        content_type when is_binary(content_type) and content_type != "" ->
          %{"content-type" => content_type}

        _no_content_type ->
          %{}
      end

    credentials = %Credentials{
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region
    }

    signed =
      AWSAuth.sign_url(credentials, "PUT", url, @service,
        region: config.region,
        headers: headers,
        expires_in: Keyword.get(opts, :expires_in, 3600),
        payload: :unsigned
      )

    {:ok, signed}
  end

  def presigned_get_url(key, opts \\ []) when is_binary(key) do
    config = config!(opts)
    url = object_url(config, key)

    credentials = %Credentials{
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region
    }

    signed =
      AWSAuth.sign_url(credentials, "GET", url, @service,
        region: config.region,
        expires_in: Keyword.get(opts, :expires_in, 300)
      )

    {:ok, signed}
  end

  def public_url(key, opts \\ []) when is_binary(key) do
    config = config!(opts)
    base_url = config.public_base_url || object_url(config, key)

    if config.public_base_url do
      {:ok, join_url(config.public_base_url, key)}
    else
      {:ok, base_url}
    end
  end

  def configured?(opts \\ []) do
    case config(opts) do
      {:ok, _config} -> true
      {:error, _reason} -> false
    end
  end

  @doc "Returns the configured bucket name, or nil when storage is unconfigured."
  def bucket(opts \\ []) do
    case config(opts) do
      {:ok, config} -> config.bucket
      {:error, _reason} -> nil
    end
  end

  def config(opts \\ []) do
    (Keyword.get(opts, :config) || Application.get_env(:atlas, :object_storage, []))
    |> config_from_value()
  end

  defp request(method, key, opts) do
    config = config!(opts)
    body = Keyword.get(opts, :body, "")
    headers = Keyword.get(opts, :headers, [])
    success_statuses = Keyword.fetch!(opts, :success_statuses)
    url = object_url(config, key)

    request =
      [
        method: method,
        url: url,
        body: body,
        headers: signed_headers(config, method, url, body, headers)
      ]

    request_fun = Keyword.get(opts, :request, &Req.request/1)

    case request_fun.(request) do
      {:ok, %{status: status} = response} ->
        if status in success_statuses do
          {:ok, response}
        else
          {:error, {:unexpected_status, status, Map.get(response, :body)}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp signed_headers(%__MODULE__{} = config, method, url, body, headers) do
    credentials = %Credentials{
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region
    }

    AWSAuth.sign_authorization_header(
      credentials,
      method |> to_string() |> String.upcase(),
      url,
      @service,
      headers: normalize_headers(headers),
      payload: body,
      region: config.region,
      return_format: :list
    )
  end

  defp normalize_headers(headers) do
    Map.new(headers, fn {name, value} ->
      {name |> to_string() |> String.downcase(), canonical_header_value(value)}
    end)
  end

  defp canonical_header_value(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp content_type(headers) do
    Enum.find_value(headers, fn
      {name, value} when is_binary(name) ->
        if String.downcase(name) == "content-type", do: value

      _other ->
        nil
    end)
  end

  defp object_url(%__MODULE__{} = config, key) do
    config.endpoint_url
    |> String.trim_trailing("/")
    |> join_url(Path.join(config.bucket, key))
  end

  defp join_url(base, path) do
    encoded_path =
      path
      |> String.split("/", trim: true)
      |> Enum.map_join("/", fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)

    base
    |> URI.parse()
    |> URI.append_path("/#{encoded_path}")
    |> URI.to_string()
  end

  defp config!(opts) do
    case config(opts) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "object storage is not configured: #{reason}"
    end
  end

  defp config_from_value(%__MODULE__{} = config), do: {:ok, config}
  defp config_from_value(config) when is_list(config), do: config_from_keyword(config)

  defp config_from_keyword(config) do
    config = Keyword.take(config, @config_keys)

    missing =
      [:endpoint_url, :region, :bucket, :access_key_id, :secret_access_key]
      |> Enum.reject(&present?(Keyword.get(config, &1)))

    if missing == [] do
      {:ok, struct!(__MODULE__, config)}
    else
      {:error, "missing #{Enum.join(missing, ", ")}"}
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
