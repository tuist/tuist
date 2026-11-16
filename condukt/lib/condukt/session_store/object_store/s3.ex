defmodule Condukt.SessionStore.ObjectStore.S3 do
  @moduledoc """
  A `Condukt.SessionStore.ObjectStore.Bucket` on S3 or a service compatible
  with it, such as Tigris, R2, or MinIO, signed with AWS Signature V4.

      {Condukt.SessionStore.ObjectStore.S3,
       endpoint: "https://t3.storage.dev",
       bucket: "sessions",
       region: "auto",
       access_key_id: "...",
       secret_access_key: "..."}

  Config: `:endpoint`, `:bucket`, `:access_key_id`, and `:secret_access_key`
  are required. `:region` defaults to `"auto"`, and `:req_options` are merged
  into every request. Objects are addressed path-style
  (`endpoint/bucket/key`).

  Creates use `If-None-Match: *`, so the service must support conditional
  writes, as AWS S3, Tigris, R2, and MinIO do.
  """

  @behaviour Condukt.SessionStore.ObjectStore.Bucket

  @impl true
  def create(config, key, body) do
    case request(config, method: :put, url: object_url(config, key), body: body, headers: [{"if-none-match", "*"}]) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      # 409 is a create racing another create of the same key on AWS S3.
      {:ok, %{status: status}} when status in [409, 412] -> {:error, :exists}
      {:ok, response} -> {:error, {:http, response.status}}
      {:error, exception} -> {:error, {:transport, Exception.message(exception)}}
    end
  end

  @impl true
  def get(config, key) do
    case request(config, method: :get, url: object_url(config, key)) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> :not_found
      {:ok, response} -> {:error, {:http, response.status}}
      {:error, exception} -> {:error, {:transport, Exception.message(exception)}}
    end
  end

  @impl true
  def list(config, prefix, start_after), do: list(config, prefix, start_after, nil, [])

  defp list(config, prefix, start_after, token, acc) do
    params =
      [{"list-type", "2"}, {"prefix", prefix}]
      |> put_param("start-after", start_after)
      |> put_param("continuation-token", token)

    case request(config, method: :get, url: bucket_url(config), params: params) do
      {:ok, %{status: 200, body: body}} ->
        keys = acc ++ xml_values(body, "Key")

        case {xml_values(body, "IsTruncated"), xml_values(body, "NextContinuationToken")} do
          {["true"], [next]} -> list(config, prefix, start_after, next, keys)
          _ -> {:ok, keys}
        end

      {:ok, response} ->
        {:error, {:http, response.status}}

      {:error, exception} ->
        {:error, {:transport, Exception.message(exception)}}
    end
  end

  @impl true
  def delete(config, key) do
    case request(config, method: :delete, url: object_url(config, key)) do
      {:ok, %{status: status}} when status in [200, 204, 404] -> :ok
      {:ok, response} -> {:error, {:http, response.status}}
      {:error, exception} -> {:error, {:transport, Exception.message(exception)}}
    end
  end

  # Writes are retried too: a create whose response was lost comes back as
  # `:exists`, which the store tells apart by reading the object back.
  defp request(config, options) do
    [
      aws_sigv4: [
        service: :s3,
        region: Keyword.get(config, :region, "auto"),
        access_key_id: Keyword.fetch!(config, :access_key_id),
        secret_access_key: Keyword.fetch!(config, :secret_access_key)
      ],
      retry: :transient,
      max_retries: 2,
      decode_body: false
    ]
    |> Keyword.merge(options)
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request()
  end

  defp bucket_url(config), do: String.trim_trailing(Keyword.fetch!(config, :endpoint), "/") <> "/" <> config[:bucket]
  defp object_url(config, key), do: bucket_url(config) <> "/" <> key

  defp put_param(params, _name, nil), do: params
  defp put_param(params, name, value), do: params ++ [{name, value}]

  defp xml_values(body, tag) do
    ~r/<#{tag}>(.*?)<\/#{tag}>/s
    |> Regex.scan(body, capture: :all_but_first)
    |> Enum.map(fn [value] -> unescape(value) end)
  end

  defp unescape(value) do
    value
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end
end
