defmodule Cache.CacheArtifacts do
  @moduledoc """
  Persists cache artifact metadata to support eviction decisions.
  """

  import Ecto.Query

  alias Cache.CacheArtifact
  alias Cache.Disk
  alias Cache.Repo
  alias Cache.SQLiteWriter

  @default_batch_size 500

  @doc """
  Returns the oldest artifacts up to `limit`, ordered by last access time.
  """

  def oldest(limit \\ @default_batch_size) do
    _ = SQLiteWriter.flush(:cas_artifacts)

    CacheArtifact
    |> order_by([a], asc: a.last_accessed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Deletes the metadata entry for a given key.
  """

  def delete_by_key(key) do
    _ = SQLiteWriter.enqueue_cas_deletes([key])
    _ = SQLiteWriter.flush(:cas_artifacts)
    :ok
  end

  @doc """
  Deletes metadata entries for multiple keys in a single query.
  """

  def delete_by_keys(keys) when is_list(keys) do
    _ = SQLiteWriter.enqueue_cas_deletes(keys)
    _ = SQLiteWriter.flush(:cas_artifacts)
    :ok
  end

  @doc """
  Tracks access to a cache artifact by updating its metadata in the database.

  Creates or updates a CacheArtifact record with the current file size and access time.
  Uses upsert logic to handle conflicts on the key field.
  """
  def track_artifact_access(key) do
    size_bytes = file_size_for(key)
    last_accessed_at = DateTime.utc_now()

    _ = SQLiteWriter.enqueue_cas_access(key, size_bytes, last_accessed_at)
    :ok
  end

  defp file_size_for(key) do
    key
    |> Disk.artifact_path()
    |> File.stat()
    |> case do
      {:ok, %File.Stat{size: size}} -> size
      _ -> nil
    end
  end

end
