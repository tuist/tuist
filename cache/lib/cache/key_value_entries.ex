defmodule Cache.KeyValueEntries do
  @moduledoc """
  Context module for key-value entry management and eviction.
  """

  import Ecto.Query

  alias Cache.KeyValueEntry
  alias Cache.KeyValueEntryHash
  alias Cache.Repo

  @id_chunk_size 500

  @doc """
  Deletes expired entries and returns them for downstream CAS cleanup.

  Uses a two-phase approach: SELECT expired entries first, then DELETE by ID
  with a re-check of the cutoff condition. An entry that gets accessed between
  the SELECT and the DELETE will survive the DELETE but still appear in the
  returned list — the CASCleanupWorker's reference check handles this safely.
  """
  def delete_expired(max_age_days \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)

    select_query =
      from(e in KeyValueEntry,
        where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff,
        order_by: e.id,
        limit: 10_000,
        select: struct(e, [:id, :key, :json_payload])
      )

    case Repo.all(select_query) do
      [] ->
        {[], 0}

      expired_entries ->
        ids_to_delete = Enum.map(expired_entries, & &1.id)

        delete_expired_entries(ids_to_delete, cutoff)

        deleted_ids = deleted_ids(ids_to_delete)
        delete_hashes_for_deleted_entries(deleted_ids)

        deleted_id_set = MapSet.new(deleted_ids)
        deleted_entries = Enum.filter(expired_entries, &MapSet.member?(deleted_id_set, &1.id))

        {deleted_entries, length(deleted_entries)}
    end
  end

  def replace_entry_hashes([]), do: :ok

  def replace_entry_hashes(entries) when is_list(entries) do
    ids = Enum.map(entries, & &1.id)

    Repo.delete_all(from(h in KeyValueEntryHash, where: h.key_value_entry_id in ^ids))

    rows = Enum.flat_map(entries, &entry_hash_rows/1)

    if rows != [] do
      Repo.insert_all(KeyValueEntryHash, rows,
        on_conflict: :nothing,
        conflict_target: [:key_value_entry_id, :cas_hash]
      )
    end

    :ok
  end

  def unreferenced_hashes([], _account_handle, _project_handle), do: []

  def unreferenced_hashes(hashes, account_handle, project_handle) when is_list(hashes) do
    referenced =
      hashes
      |> Enum.chunk_every(500)
      |> Enum.flat_map(fn chunk ->
        Repo.all(
          from(h in KeyValueEntryHash,
            where: h.account_handle == ^account_handle,
            where: h.project_handle == ^project_handle,
            where: h.cas_hash in ^chunk,
            select: h.cas_hash,
            distinct: true
          )
        )
      end)
      |> MapSet.new()

    Enum.reject(hashes, &MapSet.member?(referenced, &1))
  end

  defp delete_hashes_for_deleted_entries([]), do: :ok

  defp delete_hashes_for_deleted_entries(ids_to_delete) do
    ids_to_delete
    |> Enum.chunk_every(@id_chunk_size)
    |> Enum.each(fn ids_chunk ->
      Repo.delete_all(from(h in KeyValueEntryHash, where: h.key_value_entry_id in ^ids_chunk))
    end)

    :ok
  end

  defp delete_expired_entries(ids_to_delete, cutoff) do
    ids_to_delete
    |> Enum.chunk_every(@id_chunk_size)
    |> Enum.each(fn ids_chunk ->
      Repo.delete_all(
        from(e in KeyValueEntry,
          where: e.id in ^ids_chunk,
          where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff
        )
      )
    end)

    :ok
  end

  defp deleted_ids(ids_to_delete) do
    existing_ids =
      ids_to_delete
      |> Enum.chunk_every(@id_chunk_size)
      |> Enum.flat_map(fn ids_chunk ->
        Repo.all(
          from(e in KeyValueEntry,
            where: e.id in ^ids_chunk,
            select: e.id
          )
        )
      end)
      |> MapSet.new()

    Enum.reject(ids_to_delete, &MapSet.member?(existing_ids, &1))
  end

  defp entry_hash_rows(entry) do
    with {account_handle, project_handle} <- parse_scope(entry.key),
         {:ok, %{"entries" => entries}} when is_list(entries) <- Jason.decode(entry.json_payload) do
      entries
      |> Enum.map(&Map.get(&1, "value"))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()
      |> Enum.map(fn cas_hash ->
        %{
          key_value_entry_id: entry.id,
          account_handle: account_handle,
          project_handle: project_handle,
          cas_hash: cas_hash
        }
      end)
    else
      _ ->
        []
    end
  end

  defp parse_scope(key) do
    case String.split(key, ":", parts: 4) do
      ["keyvalue", account_handle, project_handle, _cas_id] ->
        {account_handle, project_handle}

      _ ->
        :skip
    end
  end
end
