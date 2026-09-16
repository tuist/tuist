defmodule Cache.CacheArtifacts do
  @moduledoc """
  Persists cache artifact metadata to support eviction decisions.
  """

  import Ecto.Query

  alias Cache.CacheArtifact
  alias Cache.CacheArtifactsBuffer
  alias Cache.Disk
  alias Cache.Repo

  @default_batch_size 500

  @doc """
  Returns the oldest artifacts up to `limit`, ordered by last access time.
  """

  def oldest(limit \\ @default_batch_size) do
    CacheArtifact
    |> order_by([a], asc: a.last_accessed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Deletes the metadata entry for a given key.
  """

  def delete_by_key(key) do
    Repo.delete_all(from(a in CacheArtifact, where: a.key == ^key))
    :ok
  end

  @doc """
  Deletes metadata entries for multiple keys in a single query.
  """

  def delete_by_keys(keys) when is_list(keys) do
    Repo.delete_all(from(a in CacheArtifact, where: a.key in ^keys))
    :ok
  end

  @doc """
  Returns the subset of keys that exist in the cache_artifacts table.
  """

  def existing_keys([]), do: []

  def existing_keys(keys) when is_list(keys) do
    keys
    |> Enum.chunk_every(@default_batch_size)
    |> Enum.flat_map(fn chunk ->
      CacheArtifact
      |> where([a], a.key in ^chunk)
      |> select([a], a.key)
      |> Repo.all()
    end)
  end

  @doc """
  Tracks access to a cache artifact by updating its metadata in the database.

  Creates or updates a CacheArtifact record with the current file size and access time.
  Uses upsert logic to handle conflicts on the key field. The artifact's content
  digest is left as it is.
  """
  def track_artifact_access(key) do
    size_bytes = file_size_for(key)
    last_accessed_at = DateTime.utc_now()

    :ok = CacheArtifactsBuffer.enqueue_access(key, size_bytes, last_accessed_at)
    :ok
  end

  @doc """
  Tracks an access that also records the artifact's content digest: the
  lowercase hex SHA-256 its uploader declared and a multipart completion
  verified, or the one its object-storage copy carries.

  `nil` clears the digest, because the bytes now on disk were published without
  one and an older digest would describe a different object.
  """
  def record_content_sha256(key, content_sha256) do
    size_bytes = file_size_for(key)
    last_accessed_at = DateTime.utc_now()

    :ok = CacheArtifactsBuffer.enqueue_access(key, size_bytes, last_accessed_at)
    :ok = CacheArtifactsBuffer.enqueue_content_sha256(key, size_bytes, last_accessed_at, content_sha256)
    :ok
  end

  @doc """
  Returns the content digest recorded for `key`, or `nil` when the artifact has
  none. A digest queued by a completion that has not been flushed yet wins over
  the database, so a download right after an upload already carries it.

  A flush takes entries off the queue just before it writes them, so a read
  landing in between sees neither and returns `nil`. That response then goes out
  without a digest, which the client treats as unverified rather than damaged.
  """
  def content_sha256(key) do
    case CacheArtifactsBuffer.pending_content_sha256(key) do
      {:set, content_sha256} ->
        content_sha256

      :keep ->
        Repo.one(from(a in CacheArtifact, where: a.key == ^key, select: a.content_sha256))
    end
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
