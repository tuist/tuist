defmodule Atlas.Documents.Storage do
  @moduledoc """
  S3-compatible object storage for executive documents.
  """

  def put_object(key, body, opts \\ []), do: client().put_object(key, body, opts)
  def get_object(key, opts \\ []), do: client().get_object(key, opts)
  def delete_object(key, opts \\ []), do: client().delete_object(key, opts)
  def bucket, do: client().bucket()

  @doc """
  Returns `{:ok, response}` when the object exists, or `{:error, reason}` when
  it does not or the client cannot report existence.
  """
  def head_object(key, opts \\ []) do
    client = client()

    cond do
      function_exported?(client, :head_object, 2) ->
        client.head_object(key, opts)

      function_exported?(client, :get_object, 2) ->
        with {:ok, %{body: body}} <- client.get_object(key, opts) do
          {:ok, %{status: 200, headers: [{"content-length", Integer.to_string(byte_size(body))}]}}
        end

      true ->
        {:error, :not_supported}
    end
  end

  @doc """
  Returns a short-lived, signed URL for downloading an object, when the backing
  store supports it. Returns `{:error, :not_supported}` for stores (such as
  local disk) that have no signed-URL concept, so callers can fall back to
  streaming the bytes themselves.
  """
  def presigned_get_url(key, opts \\ []) do
    client = client()

    if function_exported?(client, :presigned_get_url, 2) do
      client.presigned_get_url(key, opts)
    else
      {:error, :not_supported}
    end
  end

  @doc """
  Returns a short-lived, signed URL a client can `PUT` bytes to directly.
  `:content_type` is bound into the signature so the client must send the same
  header at upload time. `:expires_in` is in seconds, defaults to 1 hour.
  """
  def presigned_put_url(key, opts \\ []) do
    client = client()

    if function_exported?(client, :presigned_put_url, 2) do
      client.presigned_put_url(key, opts)
    else
      {:error, :not_supported}
    end
  end

  def configured?, do: is_binary(bucket()) and bucket() != ""

  defp client do
    :atlas
    |> Application.get_env(:documents, [])
    |> Keyword.get(:storage_client, Atlas.ObjectStorage)
  end
end
