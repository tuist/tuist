defmodule Atlas.Vector do
  @moduledoc """
  Client for the in-cluster OpenData Vector service.

  The service stores Atlas search embeddings outside Postgres. This module keeps
  the wire format close to OpenData's API while giving callers a stable Atlas
  boundary for upserts, nearest-neighbor search, reads, and deletes.
  """

  require Logger

  @default_receive_timeout 10_000
  @json_content_type "application/protobuf+json"

  @doc """
  Upserts vector records.

  Each record must include an `:id` and `:vector`. Additional metadata can be
  passed in `:attributes` and is merged into OpenData's `attributes` object.

      Atlas.Vector.upsert_vectors([
        %{
          id: "event:123",
          vector: [0.1, 0.2],
          attributes: %{source_type: "event", source_id: "123"}
        }
      ])
  """
  def upsert_vectors(records, opts \\ []) when is_list(records) do
    with {:ok, client} <- client(opts) do
      payload = %{"upsertVectors" => Enum.map(records, &encode_record!/1)}

      request(client, :post, "/api/v1/vector/write", json: payload)
    end
  end

  @doc """
  Searches for nearest vectors.

  Options:

    * `:k` - number of neighbors to return, defaults to 10.
    * `:nprobe` - number of posting lists to search.
    * `:filter` - OpenData filter expression.
    * `:include_fields` - attributes to include in the response.
  """
  def search(vector, opts \\ []) when is_list(vector) do
    with {:ok, client} <- client(opts) do
      payload =
        %{"vector" => vector, "k" => Keyword.get(opts, :k, 10)}
        |> maybe_put("nprobe", Keyword.get(opts, :nprobe))
        |> maybe_put("filter", Keyword.get(opts, :filter))
        |> maybe_put("includeFields", Keyword.get(opts, :include_fields))

      request(client, :post, "/api/v1/vector/search", json: payload)
    end
  end

  @doc """
  Fetches one vector by ID.
  """
  def get_vector(id, opts \\ []) when is_binary(id) do
    with {:ok, client} <- client(opts) do
      request(client, :get, "/api/v1/vector/vectors/#{encode_path_segment(id)}")
    end
  end

  @doc """
  Deletes vectors by ID.
  """
  def delete_vectors(ids, opts \\ []) when is_list(ids) do
    with {:ok, client} <- client(opts) do
      request(client, :post, "/api/v1/vector/delete", json: %{"ids" => ids})
    end
  end

  def configured? do
    case client() do
      {:ok, _client} -> true
      :disabled -> false
    end
  end

  defp request(client, method, path, opts \\ []) do
    request =
      Req.new(
        method: method,
        url: client.base_url <> path,
        receive_timeout: client.receive_timeout,
        headers: [
          {"accept", @json_content_type},
          {"content-type", @json_content_type}
        ]
      )
      |> Req.merge(opts)

    case client.request.(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("OpenData Vector request failed: status=#{status} body=#{inspect(body)}")
        {:error, {:http, status, body}}

      {:error, reason} ->
        Logger.warning("OpenData Vector transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp encode_record!(%{id: id, vector: vector} = record) when is_binary(id) and is_list(vector) do
    attributes =
      record
      |> Map.get(:attributes, %{})
      |> stringify_keys()
      |> Map.put("vector", vector)

    %{"id" => id, "attributes" => attributes}
  end

  defp encode_record!(%{"id" => id, "vector" => vector} = record) when is_binary(id) and is_list(vector) do
    attributes =
      record
      |> Map.get("attributes", %{})
      |> stringify_keys()
      |> Map.put("vector", vector)

    %{"id" => id, "attributes" => attributes}
  end

  defp encode_record!(_record) do
    raise ArgumentError, "vector records must include an id and vector"
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp encode_path_segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp client(opts \\ []) do
    config = vector_config()

    base_url =
      opts
      |> configured_option(config, :base_url)
      |> base_url()

    case base_url do
      nil ->
        :disabled

      base_url ->
        {:ok,
         %{
           base_url: base_url,
           receive_timeout: receive_timeout(configured_option(opts, config, :receive_timeout)),
           request: Keyword.get(opts, :request, &Req.request/1)
         }}
    end
  end

  defp configured_option(opts, config, key) do
    if Keyword.has_key?(opts, key), do: Keyword.get(opts, key), else: Keyword.get(config, key)
  end

  defp base_url(nil), do: nil
  defp base_url(""), do: nil
  defp base_url(value) when is_binary(value), do: String.trim_trailing(value, "/")

  defp receive_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout
  defp receive_timeout(_timeout), do: @default_receive_timeout

  defp vector_config, do: Application.get_env(:atlas, :vector, [])
end
