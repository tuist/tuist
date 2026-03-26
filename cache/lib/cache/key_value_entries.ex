defmodule Cache.KeyValueEntries do
  @moduledoc """
  Context module for key-value entry management and eviction.
  """

  import Ecto.Query

  alias Cache.Config
  alias Cache.KeyValueEntry
  alias Cache.KeyValueEntryHash
  alias Cache.KeyValueRepo
  alias Cache.SQLiteHelpers

  @id_chunk_size 500
  @hash_chunk_size 500
  @insert_chunk_size 200
  @default_batch_size 1000
  @default_max_duration_ms 300_000
  @batch_sleep_ms 10

  @doc """
  Deletes expired entries and returns CAS hashes grouped by account/project scope.

  The return shape is `{grouped_hashes, deleted_count, status}` where
  `grouped_hashes` is `%{{account_handle, project_handle} => [cas_hash, ...]}`
  and `status` is `:complete`, `:time_limit_reached`, or `:busy`.
  """
  def delete_expired(max_age_days \\ 30, opts \\ []) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)
    max_duration_ms = Keyword.get(opts, :max_duration_ms, @default_max_duration_ms)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    deadline_ms = System.monotonic_time(:millisecond) + max(max_duration_ms, 0)

    delete_expired_loop(cutoff, batch_size, deadline_ms)
  end

  @doc """
  Deletes one batch of the oldest expired entries and returns CAS hashes
  grouped by account/project scope.

  Entries with NULL `last_accessed_at` are evicted first, followed by the
  oldest non-NULL entries that exceed the given age threshold.

  Returns `{grouped_hashes, deleted_count, status}` where
  `grouped_hashes` is `%{{account_handle, project_handle} => [cas_hash, ...]}`
  and `status` is `:complete`, `:time_limit_reached`, or `:busy`.
  """
  def delete_one_expired_batch(max_age_days, opts \\ []) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    max_duration_ms = Keyword.get(opts, :max_duration_ms, @default_max_duration_ms)
    deadline_ms = System.monotonic_time(:millisecond) + max(max_duration_ms, 0)
    timeout = Config.key_value_maintenance_busy_timeout_ms()

    SQLiteHelpers.with_repo_busy_timeout(KeyValueRepo, timeout, fn ->
      if time_limit_reached?(deadline_ms) do
        {%{}, 0, :time_limit_reached}
      else
        case candidate_batch(cutoff, batch_size, nil) do
          [] ->
            {%{}, 0, :complete}

          batch ->
            ids_to_delete = Enum.map(batch, &elem(&1, 0))
            {hash_sets, count, status} = delete_expired_entries(ids_to_delete, cutoff)
            :timer.sleep(@batch_sleep_ms)
            {to_sorted_hash_lists(hash_sets), count, status}
        end
      end
    end)
  rescue
    error ->
      if SQLiteHelpers.busy_error?(error) do
        {%{}, 0, :busy}
      else
        reraise error, __STACKTRACE__
      end
  end

  @doc """
  Replaces all CAS hash references for the given entries.
  Deletes existing hashes and re-inserts based on current `json_payload`.
  """
  def replace_entry_hashes([]), do: :ok

  def replace_entry_hashes(entries) when is_list(entries) do
    entry_chunks = Enum.chunk_every(entries, @id_chunk_size)

    {:ok, _} =
      KeyValueRepo.transaction(fn ->
        Enum.each(entry_chunks, fn entries_chunk ->
          ids_chunk = entries_chunk |> Enum.map(& &1.id) |> Enum.uniq()

          {_, _} = KeyValueRepo.delete_all(from(h in KeyValueEntryHash, where: h.key_value_entry_id in ^ids_chunk))

          entries_chunk
          |> Enum.flat_map(&entry_hash_rows/1)
          |> Enum.chunk_every(@insert_chunk_size)
          |> Enum.each(fn rows_chunk ->
            {_, _} =
              KeyValueRepo.insert_all(KeyValueEntryHash, rows_chunk,
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
        KeyValueRepo.all(
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

  defp delete_expired_loop(cutoff, batch_size, deadline_ms, cursor \\ nil, hash_sets_acc \\ %{}, count_acc \\ 0) do
    if time_limit_reached?(deadline_ms) do
      {to_sorted_hash_lists(hash_sets_acc), count_acc, :time_limit_reached}
    else
      timeout = Config.key_value_maintenance_busy_timeout_ms()

      result =
        try do
          SQLiteHelpers.with_repo_busy_timeout(KeyValueRepo, timeout, fn ->
            delete_candidate_batch(cutoff, batch_size, cursor)
          end)
        rescue
          error ->
            if SQLiteHelpers.busy_error?(error), do: :busy, else: reraise(error, __STACKTRACE__)
        end

      case result do
        :empty ->
          {to_sorted_hash_lists(hash_sets_acc), count_acc, :complete}

        :busy ->
          {to_sorted_hash_lists(hash_sets_acc), count_acc, :busy}

        {:ok, batch_hashes, batch_count, new_cursor} ->
          merged = merge_grouped_hash_sets(hash_sets_acc, batch_hashes)
          total = count_acc + batch_count
          :timer.sleep(@batch_sleep_ms)
          delete_expired_loop(cutoff, batch_size, deadline_ms, new_cursor, merged, total)
      end
    end
  end

  # Queries candidates for eviction, handling NULL last_accessed_at entries
  # separately from non-NULL entries so the (last_accessed_at, id) index
  # can be used for the non-NULL path.
  defp delete_candidate_batch(cutoff, batch_size, cursor) do
    case candidate_batch(cutoff, batch_size, cursor) do
      [] ->
        :empty

      rows ->
        ids = Enum.map(rows, &elem(&1, 0))
        {batch_hashes, batch_count, status} = delete_expired_entries(ids, cutoff)

        case status do
          :busy -> :busy
          :complete -> {:ok, batch_hashes, batch_count, batch_cursor(rows)}
        end
    end
  end

  defp candidate_batch(cutoff, batch_size, {:time_cursor, cursor_time, cursor_id}) do
    non_null_candidates(cutoff, batch_size, {cursor_time, cursor_id})
  end

  defp candidate_batch(cutoff, batch_size, cursor) do
    null_cursor_id =
      case cursor do
        {:null_cursor, id} -> id
        nil -> nil
      end

    nulls = null_candidates(batch_size, null_cursor_id)
    null_count = length(nulls)

    if null_count >= batch_size do
      nulls
    else
      remaining = batch_size - null_count
      non_nulls = non_null_candidates(cutoff, remaining, nil)
      nulls ++ non_nulls
    end
  end

  defp null_candidates(limit, after_id) do
    query =
      from(e in KeyValueEntry,
        where: is_nil(e.last_accessed_at),
        order_by: [asc: e.id],
        limit: ^limit,
        select: {e.id, e.last_accessed_at}
      )

    query = if after_id, do: from(e in query, where: e.id > ^after_id), else: query

    KeyValueRepo.all(query)
  end

  defp non_null_candidates(cutoff, limit, cursor) do
    base =
      from(e in KeyValueEntry,
        where: not is_nil(e.last_accessed_at) and e.last_accessed_at < ^cutoff,
        order_by: [asc: e.last_accessed_at, asc: e.id],
        limit: ^limit,
        select: {e.id, e.last_accessed_at}
      )

    query =
      case cursor do
        nil ->
          base

        {cursor_time, cursor_id} ->
          from(e in base,
            where:
              e.last_accessed_at > ^cursor_time or
                (e.last_accessed_at == ^cursor_time and e.id > ^cursor_id)
          )
      end

    KeyValueRepo.all(query)
  end

  defp batch_cursor(batch) do
    {id, last_accessed_at} = List.last(batch)

    case last_accessed_at do
      nil -> {:null_cursor, id}
      time -> {:time_cursor, time, id}
    end
  end

  defp time_limit_reached?(deadline_ms) do
    System.monotonic_time(:millisecond) >= deadline_ms
  end

  defp delete_expired_entries(ids_to_delete, cutoff) do
    ids_to_delete
    |> Enum.chunk_every(@id_chunk_size)
    |> Enum.reduce_while({%{}, 0, :complete}, fn ids_chunk, {hash_sets_acc, count_acc, _status} ->
      try do
        {chunk_hash_sets, chunk_count} = delete_chunk(ids_chunk, cutoff)

        {:cont, {merge_grouped_hash_sets(hash_sets_acc, chunk_hash_sets), count_acc + chunk_count, :complete}}
      rescue
        error ->
          if SQLiteHelpers.busy_error?(error) do
            {:halt, {hash_sets_acc, count_acc, :busy}}
          else
            reraise error, __STACKTRACE__
          end
      end
    end)
  end

  defp delete_chunk(ids_chunk, cutoff) do
    {:ok, result} =
      KeyValueRepo.transaction(fn ->
        verified_ids =
          KeyValueRepo.all(
            from(e in KeyValueEntry,
              where: e.id in ^ids_chunk,
              where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff,
              select: e.id
            )
          )

        grouped_hash_sets = hash_references_for_entries(verified_ids)

        {deleted_count, _} =
          KeyValueRepo.delete_all(
            from(e in KeyValueEntry,
              where: e.id in ^verified_ids,
              where: is_nil(e.last_accessed_at) or e.last_accessed_at < ^cutoff
            )
          )

        {grouped_hash_sets, deleted_count}
      end)

    result
  end

  defp hash_references_for_entries([]), do: %{}

  defp hash_references_for_entries(entry_ids) do
    from(h in KeyValueEntryHash,
      where: h.key_value_entry_id in ^entry_ids,
      select: {h.account_handle, h.project_handle, h.cas_hash}
    )
    |> KeyValueRepo.all()
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
         {:ok, %{"entries" => entries}} when is_list(entries) <- JSON.decode(entry.json_payload) do
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
