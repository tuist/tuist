defmodule Cache.S3Transfers do
  @moduledoc """
  Context module for managing the S3 transfer queue.

  Provides functions to enqueue uploads and downloads, retrieve
  pending transfers for batch processing, and delete completed transfers.
  """

  import Ecto.Query

  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.S3TransfersBuffer

  @doc """
  Enqueues a CAS artifact for upload to S3.

  Entries are queued and flushed in batches to reduce SQLite contention.
  """
  def enqueue_cas_upload(account_handle, project_handle, key) do
    enqueue(:upload, account_handle, project_handle, :cas, key)
  end

  @doc """
  Enqueues a CAS artifact for download from S3 to local disk.

  Entries are queued and flushed in batches to reduce SQLite contention.
  """
  def enqueue_cas_download(account_handle, project_handle, key) do
    enqueue(:download, account_handle, project_handle, :cas, key)
  end

  @doc """
  Enqueues a module cache artifact for upload to S3.

  Entries are queued and flushed in batches to reduce SQLite contention.
  """
  def enqueue_module_upload(account_handle, project_handle, key) do
    enqueue(:upload, account_handle, project_handle, :module, key)
  end

  @doc """
  Enqueues a module cache artifact for download from S3 to local disk.

  Entries are queued and flushed in batches to reduce SQLite contention.
  """
  def enqueue_module_download(account_handle, project_handle, key) do
    enqueue(:download, account_handle, project_handle, :module, key)
  end

  @doc """
  Returns a list of pending transfers for the given type, ordered by insertion time (FIFO).
  """
  def pending(type, limit) when type in [:upload, :download] do
    _ = S3TransfersBuffer.flush()

    S3Transfer
    |> where([t], t.type == ^type)
    |> order_by([t], asc: t.inserted_at, asc: t.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Deletes a single transfer by ID.
  """
  def delete(id) do
    _ = S3TransfersBuffer.enqueue_deletes([id])
    _ = S3TransfersBuffer.flush()

    :ok
  end

  @doc """
  Deletes multiple transfers by their IDs.
  """
  def delete_all(ids) when is_list(ids) do
    _ = S3TransfersBuffer.enqueue_deletes(ids)
    _ = S3TransfersBuffer.flush()

    :ok
  end

  defp enqueue(type, account_handle, project_handle, artifact_type, key) do
    S3TransfersBuffer.enqueue(type, account_handle, project_handle, artifact_type, key)
  end
end
