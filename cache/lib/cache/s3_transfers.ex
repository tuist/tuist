defmodule Cache.S3Transfers do
  @moduledoc """
  Context module for managing the S3 transfer queue.

  Provides functions to enqueue uploads and downloads, retrieve
  pending transfers for batch processing, and delete completed transfers.
  """

  import Ecto.Query

  alias Cache.Repo
  alias Cache.S3
  alias Cache.S3Transfer
  alias Cache.S3TransfersBuffer

  @doc """
  Enqueues an Xcode compilation cache (CAS) artifact for upload to S3.

  Entries are queued and flushed in batches to reduce SQLite contention.
  """
  def enqueue_xcode_upload(account_handle, project_handle, key) do
    enqueue(:upload, account_handle, project_handle, :xcode_cache, key)
  end

  @doc """
  Enqueues an Xcode compilation cache (CAS) artifact for download from S3 to local disk.

  Entries are queued and flushed in batches to reduce SQLite contention.
  """
  def enqueue_xcode_download(account_handle, project_handle, key) do
    enqueue(:download, account_handle, project_handle, :xcode_cache, key)
  end

  @doc """
  Enqueues a module cache artifact for upload to S3.

  Entries are queued and flushed in batches to reduce SQLite contention.
  """
  def enqueue_module_upload(account_handle, project_handle, key) do
    enqueue(:upload, account_handle, project_handle, :xcode_module, key)
  end

  @doc """
  Enqueues a module cache artifact for download from S3 to local disk.

  Entries are queued and flushed in batches to reduce SQLite contention.
  """
  def enqueue_module_download(account_handle, project_handle, key) do
    enqueue(:download, account_handle, project_handle, :xcode_module, key)
  end

  @doc """
  Enqueues a Gradle build cache artifact for upload to S3.

  Uses INSERT with ON CONFLICT DO NOTHING to avoid duplicate entries.
  This is a single atomic statement, avoiding SQLite contention under bursty load.
  """
  def enqueue_gradle_upload(account_handle, project_handle, key) do
    enqueue(:upload, account_handle, project_handle, :gradle, key)
  end

  @doc """
  Enqueues a Gradle build cache artifact for download from S3 to local disk.

  Uses INSERT with ON CONFLICT DO NOTHING to avoid duplicate entries.
  This is a single atomic statement, avoiding SQLite contention under bursty load.
  """
  def enqueue_gradle_download(account_handle, project_handle, key) do
    enqueue(:download, account_handle, project_handle, :gradle, key)
  end

  @registry_sentinel_handle "registry"

  @doc """
  Enqueues a registry artifact for upload to S3.

  Registry artifacts have no account/project context, so sentinel values are used.
  Uses INSERT with ON CONFLICT DO NOTHING to avoid duplicate entries.
  """
  def enqueue_registry_upload(key) do
    enqueue(:upload, @registry_sentinel_handle, @registry_sentinel_handle, :registry, key)
  end

  @doc """
  Enqueues a registry artifact for download from S3 to local disk.

  Registry artifacts have no account/project context, so sentinel values are used.
  Uses INSERT with ON CONFLICT DO NOTHING to avoid duplicate entries.
  """
  def enqueue_registry_download(key) do
    enqueue(:download, @registry_sentinel_handle, @registry_sentinel_handle, :registry, key)
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
    S3TransfersBuffer.enqueue_delete(id)
  end

  @doc """
  Deletes multiple transfers by their IDs.
  """
  def delete_all(ids) when is_list(ids) do
    Enum.each(ids, &S3TransfersBuffer.enqueue_delete/1)
  end

  @doc """
  Asynchronously checks S3 and enqueues an artifact upload only when missing.
  """
  def enqueue_upload_if_missing(account_handle, project_handle, artifact_type, key) do
    Task.start(fn ->
      if !S3.exists?(key, type: storage_type(artifact_type)) do
        enqueue(:upload, account_handle, project_handle, artifact_type, key)
      end
    end)

    :ok
  end

  defp enqueue(type, account_handle, project_handle, artifact_type, key) do
    S3TransfersBuffer.enqueue(type, account_handle, project_handle, artifact_type, key)
  end

  defp storage_type(:xcode_cache), do: :xcode_cache
  defp storage_type(:cas), do: :xcode_cache
  defp storage_type(:registry), do: :registry
  defp storage_type(_artifact_type), do: :cache
end
