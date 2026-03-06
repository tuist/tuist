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
  @insert_chunk_size 200
  @default_batch_size 1000
  @default_max_duration_ms 300_000
  @batch_sleep_ms 10
  @nil_cursor_time ~U[0001-01-01 00:00:00Z]

  @doc """
  Deletes expired entries and returns CAS hashes grouped by account/project scope.

  The return shape is `{grouped_hashes, deleted_count, status}` where
  `grouped_hashes` is `%{{account_handle, project_handle} => [cas_hash, ...]}`
  and `status` is `:complete` or `:time_limit_reached`.
  """
  def delete_expired(max_age_days \\ 30, opts \\ []) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)
    max_duration_ms = Keyword.get(opts, :max_duration_ms, @default_max_duration_ms)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    started_at_ms = System.monotonic_time(:millisecond)

    delete_expired_batches(cutoff, batch_size, max_duration_ms, started_at_ms)
  end

  @doc """
  Replaces all CAS hash references for the given entries.
  Deletes existing hashes and re-inserts based on current `json_payload`.
  """
  def replace_entry_hashes([]), do: :ok

  def replace_entry_hashes(entries) when is_list(entries) do
    entry_chunks = Enum.chunk_every(entries, @id_chunk_size)

    {:ok, _} =
      Repo.transaction(fn ->
        Enum.each(entry_chunks, fn entries_chunk ->
          ids_chunk = entries_chunk |> Enum.map(& &1.id) |> Enum.uniq()

          {_, _} = Repo.delete_all(from(h in KeyValueEntryHash, where: h.key_value_entry_id in ^ids_chunk))

          entries_chunk
          |> Enum.flat_map(&entry_hash_rows/1)
          |> Enum.chunk_every(@insert_chunk_size)
          |> Enum.each(fn rows_chunk ->
            {_, _} =
              Repo.insert_all(KeyValueEntryHash, rows_chunk,
                on_conflict: :nothing,
                conflict_target: [:key_value_entry_id, :cas_hash]
              )
          end)
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

  defp delete_expired_batches(cutoff, batch_size, max_duration_ms, started_at_ms) do
    do_delete_expired_batches(cutoff, batch_size, max_duration_ms, started_at_ms, nil, %{}, 0)
  end

  defp do_delete_expired_batches(cutoff, batch_size, max_duration_ms, started_at_ms, cursor, hash_sets_acc, count_acc) do
    if time_limit_reached?(started_at_ms, max_duration_ms) do
      {to_sorted_hash_lists(hash_sets_acc), count_acc, :time_limit_reached}
    else
      case expired_batch(cutoff, batch_size, cursor) do
        [] ->
          {to_sorted_hash_lists(hash_sets_acc), count_acc, :complete}

        batch ->
          ids_to_delete = Enum.map(batch, &elem(&1, 0))

          {batch_hash_sets, batch_deleted_count} = delete_expired_entries(ids_to_delete, cutoff)

          :timer.sleep(@batch_sleep_ms)

          do_delete_expired_batches(
            cutoff,
            batch_size,
            max_duration_ms,
            started_at_ms,
            batch_cursor(batch),
            merge_grouped_hash_sets(hash_sets_acc, batch_hash_sets),
            count_acc + batch_deleted_count
          )
      end
    end
  end

  defp expired_batch(cutoff, batch_size, cursor) do
    base_query =
      from(e in KeyValueEntry,
        where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff,
        order_by: [asc: fragment("coalesce(?, ?)", e.last_accessed_at, ^@nil_cursor_time), asc: e.id],
        limit: ^batch_size,
        select: {e.id, e.last_accessed_at}
      )

    query =
      case cursor do
        nil ->
          base_query

        {cursor_time, cursor_id} ->
          from(e in base_query,
            where:
              fragment("coalesce(?, ?)", e.last_accessed_at, ^@nil_cursor_time) > ^cursor_time or
                (fragment("coalesce(?, ?)", e.last_accessed_at, ^@nil_cursor_time) == ^cursor_time and
                   e.id > ^cursor_id)
          )
      end

    Repo.all(query)
  end

  defp batch_cursor(batch) do
    {id, last_accessed_at} = List.last(batch)
    {last_accessed_at || @nil_cursor_time, id}
  end

  defp time_limit_reached?(started_at_ms, max_duration_ms) do
    System.monotonic_time(:millisecond) - started_at_ms >= max_duration_ms
  end

  defp delete_expired_entries(ids_to_delete, cutoff) do
    {grouped_hash_sets, deleted_count} =
      ids_to_delete
      |> Enum.chunk_every(@id_chunk_size)
      |> Enum.reduce({%{}, 0}, fn ids_chunk, {hash_sets_acc, count_acc} ->
        {chunk_hash_sets, chunk_count} = delete_chunk(ids_chunk, cutoff)
        {merge_grouped_hash_sets(hash_sets_acc, chunk_hash_sets), count_acc + chunk_count}
      end)

    {grouped_hash_sets, deleted_count}
  end

  defp delete_chunk(ids_chunk, cutoff) do
    {:ok, {grouped_hash_sets, deleted_count}} =
      Repo.transaction(fn ->
        verified_ids =
          Repo.all(
            from(e in KeyValueEntry,
              where: e.id in ^ids_chunk,
              where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff,
              select: e.id
            )
          )

        grouped_hash_sets = hash_references_for_entries(verified_ids)

        {deleted_count, _} =
          Repo.delete_all(
            from(e in KeyValueEntry,
              where: e.id in ^verified_ids,
              where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff
            )
          )

        {grouped_hash_sets, deleted_count}
      end)

    {grouped_hash_sets, deleted_count}
  end

  defp hash_references_for_entries([]), do: %{}

  defp hash_references_for_entries(entry_ids) do
    from(h in KeyValueEntryHash,
      where: h.key_value_entry_id in ^entry_ids,
      select: {h.account_handle, h.project_handle, h.cas_hash}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {account_handle, project_handle, cas_hash}, acc ->
      scope = {account_handle, project_handle}
      Map.update(acc, scope, MapSet.new([cas_hash]), &MapSet.put(&1, cas_hash))
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
      |> Enum.uniq()
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
