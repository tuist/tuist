defmodule Condukt.SessionStore.ObjectStore.Memory do
  @moduledoc """
  An in-memory `Condukt.SessionStore.ObjectStore.Bucket`, for tests.

      {:ok, bucket} = Condukt.SessionStore.ObjectStore.Memory.start_link()
      session_store: {Condukt.SessionStore.ObjectStore, bucket: {Condukt.SessionStore.ObjectStore.Memory, bucket}}

  The objects live in an `Agent`, so every process using the same pid sees the
  same bucket, and creates are atomic like an S3 conditional write.
  """

  @behaviour Condukt.SessionStore.ObjectStore.Bucket

  def start_link(opts \\ []), do: Agent.start_link(fn -> %{} end, opts)

  @impl true
  def create(bucket, key, body) do
    Agent.get_and_update(bucket, fn objects ->
      if Map.has_key?(objects, key),
        do: {{:error, :exists}, objects},
        else: {:ok, Map.put(objects, key, body)}
    end)
  end

  @impl true
  def get(bucket, key) do
    case Agent.get(bucket, &Map.fetch(&1, key)) do
      {:ok, body} -> {:ok, body}
      :error -> :not_found
    end
  end

  @impl true
  def list(bucket, prefix, start_after) do
    keys =
      bucket
      |> Agent.get(&Map.keys/1)
      |> Enum.filter(&(String.starts_with?(&1, prefix) and (is_nil(start_after) or &1 > start_after)))
      |> Enum.sort()

    {:ok, keys}
  end

  @impl true
  def delete(bucket, key), do: Agent.update(bucket, &Map.delete(&1, key))
end
