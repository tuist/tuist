defmodule Cache.CASArtifacts do
  @moduledoc """
  Persists CAS artifact metadata to support eviction decisions.
  """

  import Ecto.Query

  alias Cache.CASArtifact
  alias Cache.Disk
  alias Cache.Repo

  @default_batch_size 500

  @doc """
  Returns the oldest artifacts up to `limit`, ordered by last access time.
  """

  def oldest(limit \\ @default_batch_size) do
    CASArtifact
    |> order_by([a], asc: a.last_accessed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Deletes the metadata entry for a given key.
  """

  def delete_by_key(key) do
    key |> by_key_query() |> Repo.delete_all()
    :ok
  end

  @doc """
  Deletes metadata entries for multiple keys in a single query.
  """

  def delete_by_keys(keys) when is_list(keys) do
    Repo.delete_all(from(a in CASArtifact, where: a.key in ^keys))
    :ok
  end

  @doc """
  Tracks access to a CAS artifact by updating its metadata in the database.

  Creates or updates a CASArtifact record with the current file size and access time.
  Uses upsert logic to handle conflicts on the key field.
  """
  def track_artifact_access(key) do
    size_bytes = file_size_for(key)

    attrs = %{
      key: key,
      size_bytes: size_bytes,
      last_accessed_at: DateTime.utc_now()
    }

    changeset = CASArtifact.changeset(%CASArtifact{}, attrs)

    case Repo.insert(changeset,
           conflict_target: :key,
           on_conflict: {:replace, [:size_bytes, :last_accessed_at, :updated_at]}
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
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

  defp by_key_query(key) do
    from(a in CASArtifact, where: a.key == ^key)
  end
end
