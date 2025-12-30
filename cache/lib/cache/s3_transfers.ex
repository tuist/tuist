defmodule Cache.S3Transfers do
  @moduledoc """
  Context module for managing the S3 transfer queue.

  Provides functions to enqueue uploads and downloads, retrieve
  pending transfers for batch processing, and delete completed transfers.
  """

  import Ecto.Query

  alias Cache.Repo
  alias Cache.S3Transfer

  @doc """
  Enqueues a CAS artifact for upload to S3.

  Uses INSERT with ON CONFLICT DO NOTHING to avoid duplicate entries.
  This is a single atomic statement, avoiding SQLite contention under bursty load.
  """
  def enqueue_cas_upload(account_handle, project_handle, key) do
    enqueue(:upload, account_handle, project_handle, :cas, key)
  end

  @doc """
  Enqueues a CAS artifact for download from S3 to local disk.

  Uses INSERT with ON CONFLICT DO NOTHING to avoid duplicate entries.
  This is a single atomic statement, avoiding SQLite contention under bursty load.
  """
  def enqueue_cas_download(account_handle, project_handle, key) do
    enqueue(:download, account_handle, project_handle, :cas, key)
  end

  @doc """
  Enqueues a module cache artifact for upload to S3.

  Uses INSERT with ON CONFLICT DO NOTHING to avoid duplicate entries.
  This is a single atomic statement, avoiding SQLite contention under bursty load.
  """
  def enqueue_module_upload(account_handle, project_handle, key) do
    enqueue(:upload, account_handle, project_handle, :module, key)
  end

  @doc """
  Enqueues a module cache artifact for download from S3 to local disk.

  Uses INSERT with ON CONFLICT DO NOTHING to avoid duplicate entries.
  This is a single atomic statement, avoiding SQLite contention under bursty load.
  """
  def enqueue_module_download(account_handle, project_handle, key) do
    enqueue(:download, account_handle, project_handle, :module, key)
  end

  @doc """
  Returns a list of pending transfers for the given type, ordered by insertion time (FIFO).
  """
  def pending(type, limit) when type in [:upload, :download] do
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
    S3Transfer
    |> where([t], t.id == ^id)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Deletes multiple transfers by their IDs.
  """
  def delete_all(ids) when is_list(ids) do
    S3Transfer
    |> where([t], t.id in ^ids)
    |> Repo.delete_all()

    :ok
  end

  defp enqueue(type, account_handle, project_handle, artifact_type, key) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert(
      %S3Transfer{
        type: type,
        account_handle: account_handle,
        project_handle: project_handle,
        artifact_type: artifact_type,
        key: key,
        inserted_at: now
      },
      on_conflict: :nothing
    )
  end
end
