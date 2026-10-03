defmodule Atlas.TestSupport.Documents.Storage do
  @moduledoc false

  alias Atlas.TestSupport.ProcessRegistry

  @bucket "test-documents"

  def bucket, do: @bucket

  def put_object(key, body, _opts \\ []) do
    ProcessRegistry.put({__MODULE__, key}, body)
    {:ok, %{bucket: @bucket, key: key}}
  end

  def get_object(key, _opts \\ []) do
    case ProcessRegistry.get({__MODULE__, key}) do
      nil -> {:error, :not_found}
      body -> {:ok, %{body: body, content_type: nil, key: key}}
    end
  end

  def delete_object(key, _opts \\ []) do
    :ok = ProcessRegistry.delete({__MODULE__, key})
    {:ok, %{key: key}}
  end

  def head_object(key, _opts \\ []) do
    case ProcessRegistry.get({__MODULE__, key}) do
      nil ->
        {:error, :not_found}

      body when is_binary(body) ->
        {:ok, %{status: 200, headers: [{"content-length", Integer.to_string(byte_size(body))}]}}
    end
  end

  def presigned_put_url(key, opts \\ []) do
    query = URI.encode_query(Map.new(opts, fn {k, v} -> {to_string(k), to_string(v)} end))
    {:ok, "https://test.atlas.tuist.dev/uploads/#{key}?#{query}"}
  end
end
