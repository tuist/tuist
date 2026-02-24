defmodule Cache.KeyValueEntries do
  @moduledoc """
  Context module for key-value entry management and eviction.
  """

  import Ecto.Query

  alias Cache.KeyValueEntry
  alias Cache.KeyValueEntryHash
  alias Cache.Repo

  @id_chunk_size 500
  @hash_chunk_size 500
  @insert_chunk_size 1_000
  @delete_limit 10_000

  @doc """
  Deletes expired entries and returns CAS hashes grouped by account/project scope.

  The return shape is `{grouped_hashes, deleted_count}` where `grouped_hashes`
  is `%{{account_handle, project_handle} => [cas_hash, ...]}`.
  """
  def delete_expired(max_age_days \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)

    ids_to_delete =
      Repo.all(
        from(e in KeyValueEntry,
          where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff,
          order_by: e.id,
          limit: @delete_limit,
          select: e.id
        )
      )

    case ids_to_delete do
      [] ->
        {%{}, 0}

      ids_to_delete ->
        delete_expired_entries(ids_to_delete, cutoff)
    end
  end

  @doc """
  Replaces all CAS hash references for the given entries.
  Deletes existing hashes and re-inserts based on current `json_payload`.
  """
  def replace_entry_hashes([]), do: :ok

  def replace_entry_hashes(entries) when is_list(entries) do
    ids = Enum.map(entries, & &1.id)
    rows = Enum.flat_map(entries, &entry_hash_rows/1)

    {:ok, _} =
      Repo.transaction(fn ->
        ids
        |> Enum.chunk_every(@id_chunk_size)
        |> Enum.each(fn ids_chunk ->
          {_, _} = Repo.delete_all(from(h in KeyValueEntryHash, where: h.key_value_entry_id in ^ids_chunk))
        end)

        rows
        |> Enum.chunk_every(@insert_chunk_size)
        |> Enum.each(fn rows_chunk ->
          {_, _} =
            Repo.insert_all(KeyValueEntryHash, rows_chunk,
              on_conflict: :nothing,
              conflict_target: [:key_value_entry_id, :cas_hash]
            )
        end)
      end)

    :ok
  end

  @doc """
  Returns hashes from the input list that are not referenced by any
  key-value entry for the given account and project.
  """
  def unreferenced_hashes([], _account_handle, _project_handle), do: []

  def unreferenced_hashes(hashes, account_handle, project_handle) when is_list(hashes) do
    referenced =
      hashes
      |> Enum.chunk_every(@hash_chunk_size)
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

  defp delete_expired_entries(ids_to_delete, cutoff) do
    {grouped_hash_sets, deleted_count} =
      ids_to_delete
      |> Enum.chunk_every(@id_chunk_size)
      |> Enum.reduce({%{}, 0}, fn ids_chunk, {grouped_hash_sets_acc, deleted_count_acc} ->
        hash_rows_by_entry_id = hash_rows_by_entry_id(ids_chunk)

        {deleted_count, deleted_ids} =
          Repo.delete_all(
            from(e in KeyValueEntry,
              where: e.id in ^ids_chunk,
              where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff,
              select: e.id
            )
          )

        deleted_ids = deleted_ids || ids_chunk
        grouped_hash_sets = grouped_hash_sets(hash_rows_by_entry_id, deleted_ids)

        {merge_grouped_hash_sets(grouped_hash_sets_acc, grouped_hash_sets), deleted_count_acc + deleted_count}
      end)

    {to_sorted_hash_lists(grouped_hash_sets), deleted_count}
  end

  defp hash_rows_by_entry_id([]), do: %{}

  defp hash_rows_by_entry_id(entry_ids) do
    from(h in KeyValueEntryHash,
      where: h.key_value_entry_id in ^entry_ids,
      select: {h.key_value_entry_id, h.account_handle, h.project_handle, h.cas_hash}
    )
    |> Repo.all()
    |> Enum.group_by(fn {entry_id, _account_handle, _project_handle, _cas_hash} -> entry_id end)
  end

  defp grouped_hash_sets(_hash_rows_by_entry_id, []), do: %{}

  defp grouped_hash_sets(hash_rows_by_entry_id, deleted_ids) do
    deleted_id_set = MapSet.new(deleted_ids)

    hash_rows_by_entry_id
    |> Enum.flat_map(fn {entry_id, rows} ->
      if MapSet.member?(deleted_id_set, entry_id) do
        Enum.map(rows, fn {_entry_id, account_handle, project_handle, cas_hash} ->
          {account_handle, project_handle, cas_hash}
        end)
      else
        []
      end
    end)
    |> Enum.reduce(%{}, fn {account_handle, project_handle, cas_hash}, acc ->
      scope = {account_handle, project_handle}

      Map.update(acc, scope, MapSet.new([cas_hash]), fn hashes ->
        MapSet.put(hashes, cas_hash)
      end)
    end)
  end

  defp merge_grouped_hash_sets(left, right) do
    Map.merge(left, right, fn _scope, left_hashes, right_hashes ->
      MapSet.union(left_hashes, right_hashes)
    end)
  end

  defp to_sorted_hash_lists(grouped_hash_sets) do
    Map.new(grouped_hash_sets, fn {scope, hashes} ->
      {scope, hashes |> MapSet.to_list() |> Enum.sort()}
    end)
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
