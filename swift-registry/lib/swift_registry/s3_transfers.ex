defmodule SwiftRegistry.S3Transfers do
  @moduledoc """
  Context module for managing the registry S3 transfer queue.
  """

  import Ecto.Query

  alias SwiftRegistry.Repo
  alias SwiftRegistry.S3Transfer
  alias SwiftRegistry.S3TransfersBuffer

  @registry_sentinel_handle "registry"

  def enqueue_registry_upload(key) do
    enqueue(:upload, @registry_sentinel_handle, @registry_sentinel_handle, :registry, key)
  end

  def enqueue_registry_download(key) do
    enqueue(:download, @registry_sentinel_handle, @registry_sentinel_handle, :registry, key)
  end

  def pending(type, limit) when type in [:upload, :download] do
    S3Transfer
    |> where([t], t.type == ^type)
    |> order_by([t], asc: t.inserted_at, asc: t.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def delete(id) do
    S3TransfersBuffer.enqueue_delete(id)
  end

  def delete_all(ids) when is_list(ids) do
    Enum.each(ids, &S3TransfersBuffer.enqueue_delete/1)
  end

  defp enqueue(type, account_handle, project_handle, artifact_type, key) do
    S3TransfersBuffer.enqueue(type, account_handle, project_handle, artifact_type, key)
  end
end
