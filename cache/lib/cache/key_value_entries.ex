defmodule Cache.KeyValueEntries do
  @moduledoc """
  Context module for key-value entry management, eviction, and distributed-mode helpers.
  """

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.State
  alias Cache.KeyValueEntry
  alias Cache.KeyValuePendingReplicationEntry
  alias Cache.KeyValueRepo
  alias Cache.SQLiteHelpers

  @id_chunk_size 500
  @project_delete_batch_size @id_chunk_size
  @replication_token_clear_chunk_size 250
  @default_batch_size 1000
  @default_max_duration_ms 300_000
  @batch_sleep_ms 10
  @poller_watermark "poller_watermark"
  @pending_remote_batch "pending_remote_batch"
  @remote_apply_conflict_fields [
    :json_payload,
    :last_accessed_at,
    :source_node,
    :source_updated_at,
    :replication_enqueued_at,
    :updated_at
  ]

  @doc """
  Deletes expired entries and returns `{deleted_count, status}`.
  """
  def delete_expired(max_age_days \\ 30, opts \\ []) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)
    max_duration_ms = Keyword.get(opts, :max_duration_ms, @default_max_duration_ms)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    on_deleted_keys = Keyword.get(opts, :on_deleted_keys)
    deadline_ms = System.monotonic_time(:millisecond) + max(max_duration_ms, 0)

    delete_expired_loop(cutoff, batch_size, deadline_ms, on_deleted_keys)
  end

  @doc """
  Deletes one batch of the oldest expired entries and returns `{deleted_count, status}`.
  """
  def delete_one_expired_batch(max_age_days, opts \\ []) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    max_duration_ms = Keyword.get(opts, :max_duration_ms, @default_max_duration_ms)
    on_deleted_keys = Keyword.get(opts, :on_deleted_keys)
    deadline_ms = System.monotonic_time(:millisecond) + max(max_duration_ms, 0)
    timeout = Config.key_value_maintenance_busy_timeout_ms()

    if time_limit_reached?(deadline_ms) do
      {0, :time_limit_reached}
    else
      case candidate_batch_result(cutoff, batch_size, nil) do
        {:error, :busy} ->
          {0, :busy}

        [] ->
          {0, :complete}

        batch ->
          ids_to_delete = Enum.map(batch, &elem(&1, 0))
          {count, status} = delete_expired_entries_with_timeout(ids_to_delete, cutoff, on_deleted_keys, timeout)

          if status == :complete and count > 0 do
            :timer.sleep(@batch_sleep_ms)
          end

          {count, status}
      end
    end
  end

  def list_pending_replication(limit \\ Config.distributed_kv_ship_batch_size()) do
    query =
      KeyValuePendingReplicationEntry
      |> order_by([entry], asc: entry.replication_enqueued_at, asc: entry.key)
      |> limit(^limit)
      |> select([entry], %{
        key: entry.key,
        json_payload: entry.json_payload,
        source_node: entry.source_node,
        last_accessed_at: entry.last_accessed_at,
        source_updated_at: entry.source_updated_at,
        replication_enqueued_at: entry.replication_enqueued_at
      })

    SQLiteHelpers.with_repo_busy_timeout(KeyValueRepo, 0, fn ->
      KeyValueRepo.all(query, timeout: Config.key_value_read_busy_timeout_ms())
    end)
  end

  def sync_pending_replication_entries([]), do: :ok

  def sync_pending_replication_entries(rows) when is_list(rows) do
    {pending_rows, cleared_keys} =
      Enum.reduce(rows, {[], []}, fn row, {pending_rows, cleared_keys} ->
        if is_nil(Map.get(row, :replication_enqueued_at)) do
          {pending_rows, [row.key | cleared_keys]}
        else
          {[pending_replication_row(row) | pending_rows], cleared_keys}
        end
      end)

    delete_pending_replication_entries(Enum.uniq(cleared_keys))

    if pending_rows != [] do
      Cache.KeyValueWriteRepo.insert_all(KeyValuePendingReplicationEntry, pending_rows,
        conflict_target: :key,
        on_conflict:
          {:replace, [:json_payload, :source_node, :source_updated_at, :last_accessed_at, :replication_enqueued_at]}
      )
    end

    :ok
  end

  def delete_pending_replication_entries([]), do: 0

  def delete_pending_replication_entries(keys) when is_list(keys) do
    {count, _} =
      Cache.KeyValueWriteRepo.delete_all(from(entry in KeyValuePendingReplicationEntry, where: entry.key in ^keys))

    count
  end

  def clear_replication_token(key, token) when is_binary(key) do
    {count, _} =
      Cache.KeyValueWriteRepo.update_all(
        from(entry in KeyValueEntry,
          where: entry.key == ^key,
          where: entry.replication_enqueued_at == ^token
        ),
        set: [replication_enqueued_at: nil]
      )

    Cache.KeyValueWriteRepo.delete_all(
      from(entry in KeyValuePendingReplicationEntry,
        where: entry.key == ^key,
        where: entry.replication_enqueued_at == ^token
      )
    )

    count
  end

  def clear_replication_tokens(entries) when is_list(entries) do
    entries
    |> Enum.flat_map(fn entry ->
      case replication_token_ref(entry) do
        nil -> []
        ref -> [ref]
      end
    end)
    |> Enum.chunk_every(@replication_token_clear_chunk_size)
    |> Enum.reduce(0, fn refs, count_acc ->
      clear_pending_replication_chunk(refs)
      count_acc + clear_replication_token_chunk(refs)
    end)
  end

  def distributed_watermark do
    case KeyValueRepo.get(State, @poller_watermark) do
      nil -> nil
      %State{} = state -> %{watermark_updated_at: state.watermark_updated_at, watermark_key: state.watermark_key}
    end
  end

  def put_distributed_watermark(watermark_updated_at, watermark_key) do
    put_replication_state!(@poller_watermark, watermark_updated_at, watermark_key)

    :ok
  end

  def commit_remote_batch(nil), do: :ok

  def commit_remote_batch(last_processed_row) do
    {:ok, :ok} =
      Cache.KeyValueWriteRepo.transaction(
        fn ->
          put_replication_state!(
            @poller_watermark,
            last_processed_row.updated_at,
            last_processed_row.key
          )

          delete_replication_state!(@pending_remote_batch)
          :ok
        end,
        mode: :immediate
      )

    :ok
  end

  def apply_remote_batch(rows) when is_list(rows) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    {alive_rows, deleted_rows} = Enum.split_with(rows, &is_nil(&1.deleted_at))
    tombstone_keys = Enum.map(deleted_rows, & &1.key)
    signature = remote_batch_signature(rows)

    case load_pending_remote_batch(signature) do
      nil ->
        apply_remote_batch_transaction(rows, alive_rows, tombstone_keys, now, signature)

      result ->
        {:ok, result}
    end
  rescue
    error ->
      if SQLiteHelpers.contention_error?(error) do
        {:error, :busy}
      else
        reraise error, __STACKTRACE__
      end
  end

  def materialize_remote_entry(attrs) when is_map(attrs) do
    with {:ok, result} <- materialize_remote_entries([attrs]) do
      cond do
        result.inserted_count == 1 -> {:ok, :inserted}
        result.payload_updated_count == 1 -> {:ok, :payload_updated}
        true -> {:ok, :access_updated}
      end
    end
  end

  def materialize_remote_entries(rows) when is_list(rows) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    case Cache.KeyValueWriteRepo.transaction(
           fn ->
             local_entries_by_key = fetch_local_entries_by_key(Enum.map(rows, & &1.key))
             {upsert_rows, stats} = build_remote_upsert_rows(rows, local_entries_by_key, now)
             upsert_remote_rows(upsert_rows)

             %{
               inserted_count: stats.inserted_count,
               payload_updated_count: stats.payload_updated_count,
               access_updated_count: stats.access_updated_count,
               invalidate_keys: stats.invalidate_keys
             }
           end,
           mode: :immediate
         ) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      if SQLiteHelpers.contention_error?(error) do
        {:error, :busy}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp apply_remote_batch_transaction(rows, alive_rows, tombstone_keys, now, signature) do
    case Cache.KeyValueWriteRepo.transaction(
           fn ->
             local_entries_by_key = fetch_local_entries_by_key(Enum.map(rows, & &1.key))

             {upsert_rows, stats} = build_remote_upsert_rows(alive_rows, local_entries_by_key, now)
             upsert_remote_rows(upsert_rows)

             result = %{
               processed_count: length(rows),
               inserted_count: stats.inserted_count,
               payload_updated_count: stats.payload_updated_count,
               access_updated_count: stats.access_updated_count,
               deleted_count: delete_tombstoned_rows(tombstone_keys),
               last_processed_row: List.last(rows),
               invalidate_keys: stats.invalidate_keys ++ tombstone_keys,
               mark_lineage_keys: Enum.map(alive_rows, & &1.key),
               clear_lineage_keys: tombstone_keys
             }

             put_pending_remote_batch!(signature, result)
             result
           end,
           mode: :immediate
         ) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_pending_remote_batch(signature) do
    case KeyValueRepo.get(State, @pending_remote_batch) do
      nil ->
        nil

      %State{watermark_key: watermark_key} ->
        case decode_replication_state_payload!(watermark_key) do
          %{signature: ^signature, result: result} ->
            result

          %{result: _result} ->
            delete_replication_state!(@pending_remote_batch)
            nil
        end
    end
  end

  defp put_pending_remote_batch!(signature, result) do
    payload = encode_replication_state_payload!(%{signature: signature, result: result})
    put_replication_state!(@pending_remote_batch, result.last_processed_row.updated_at, payload)
  end

  defp put_replication_state!(name, watermark_updated_at, watermark_key) do
    attrs = %{name: name, watermark_updated_at: watermark_updated_at, watermark_key: watermark_key}

    %State{name: name}
    |> State.changeset(attrs)
    |> Cache.KeyValueWriteRepo.insert!(
      on_conflict: [set: [watermark_updated_at: watermark_updated_at, watermark_key: watermark_key]],
      conflict_target: :name
    )
  end

  defp delete_replication_state!(name) do
    Cache.KeyValueWriteRepo.delete_all(from(state in State, where: state.name == ^name))
    :ok
  end

  defp encode_replication_state_payload!(payload) do
    payload
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  defp decode_replication_state_payload!(payload) do
    payload
    |> Base.decode64!()
    |> :erlang.binary_to_term([:safe])
  end

  defp remote_batch_signature(rows) do
    Enum.map(rows, fn row ->
      %{
        key: row.key,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        source_updated_at: row.source_updated_at,
        last_accessed_at: row.last_accessed_at,
        source_node: row.source_node,
        json_payload_hash: remote_row_payload_hash(row.json_payload)
      }
    end)
  end

  defp remote_row_payload_hash(nil), do: nil
  defp remote_row_payload_hash(payload) when is_binary(payload), do: :crypto.hash(:sha256, payload)

  defp fetch_local_entries_by_key([]), do: %{}

  defp fetch_local_entries_by_key(keys) do
    KeyValueEntry
    |> where([entry], entry.key in ^keys)
    |> Cache.KeyValueWriteRepo.all()
    |> Map.new(&{&1.key, &1})
  end

  defp build_remote_upsert_rows(rows, local_entries_by_key, now) do
    rows
    |> Enum.reduce({[], empty_remote_batch_stats()}, fn row, {row_maps, stats} ->
      attrs =
        row
        |> Map.take([:key, :json_payload, :last_accessed_at, :source_updated_at, :source_node])
        |> remote_materialization_attrs(now)

      persisted_attrs = persisted_remote_attrs(attrs)

      case Map.get(local_entries_by_key, row.key) do
        nil ->
          {[persisted_attrs | row_maps], record_remote_batch_status(stats, row.key, :inserted)}

        local_entry ->
          merged_attrs = merge_remote_into_local(local_entry, attrs)
          status = merged_remote_status(local_entry, merged_attrs)
          upsert_row = build_remote_upsert_row(local_entry, merged_attrs, persisted_attrs)

          {[upsert_row | row_maps], record_remote_batch_status(stats, row.key, status)}
      end
    end)
    |> then(fn {row_maps, stats} ->
      {Enum.reverse(row_maps), %{stats | invalidate_keys: Enum.reverse(stats.invalidate_keys)}}
    end)
  end

  defp empty_remote_batch_stats do
    %{
      inserted_count: 0,
      payload_updated_count: 0,
      access_updated_count: 0,
      invalidate_keys: []
    }
  end

  defp record_remote_batch_status(stats, key, :inserted) do
    %{
      stats
      | inserted_count: stats.inserted_count + 1,
        invalidate_keys: [key | stats.invalidate_keys]
    }
  end

  defp record_remote_batch_status(stats, key, :payload_updated) do
    %{
      stats
      | payload_updated_count: stats.payload_updated_count + 1,
        invalidate_keys: [key | stats.invalidate_keys]
    }
  end

  defp record_remote_batch_status(stats, _key, :access_updated) do
    %{stats | access_updated_count: stats.access_updated_count + 1}
  end

  defp build_remote_upsert_row(local_entry, merged_attrs, persisted_attrs) do
    persisted_attrs
    |> Map.put(:inserted_at, local_entry.inserted_at)
    |> Map.put(:json_payload, Map.get(merged_attrs, :json_payload, local_entry.json_payload))
    |> Map.put(:last_accessed_at, Map.get(merged_attrs, :last_accessed_at, local_entry.last_accessed_at))
    |> Map.put(:source_node, Map.get(merged_attrs, :source_node, local_entry.source_node))
    |> Map.put(:source_updated_at, Map.get(merged_attrs, :source_updated_at, local_entry.source_updated_at))
    |> Map.put(
      :replication_enqueued_at,
      Map.get(merged_attrs, :replication_enqueued_at, local_entry.replication_enqueued_at)
    )
  end

  defp merged_remote_status(local_entry, merged_attrs) do
    case merged_attrs do
      %{json_payload: json_payload, source_updated_at: source_updated_at}
      when json_payload != local_entry.json_payload or source_updated_at != local_entry.source_updated_at ->
        :payload_updated

      _ ->
        :access_updated
    end
  end

  defp upsert_remote_rows([]), do: :ok

  defp upsert_remote_rows(rows) do
    Cache.KeyValueWriteRepo.insert_all(KeyValueEntry, rows,
      conflict_target: :key,
      on_conflict: {:replace, @remote_apply_conflict_fields}
    )

    sync_pending_replication_entries(rows)

    :ok
  end

  defp delete_tombstoned_rows([]), do: 0

  defp delete_tombstoned_rows(keys) do
    {count, _} =
      Cache.KeyValueWriteRepo.delete_all(
        from(entry in KeyValueEntry,
          where: entry.key in ^keys,
          where: is_nil(entry.replication_enqueued_at)
        )
      )

    delete_pending_replication_entries(keys)

    count
  end

  defp remote_materialization_attrs(attrs, now) do
    Map.merge(
      %{
        inserted_at: now,
        updated_at: now,
        replication_enqueued_at: nil
      },
      attrs
    )
  end

  defp persisted_remote_attrs(attrs) do
    Map.take(attrs, [
      :key,
      :json_payload,
      :last_accessed_at,
      :source_node,
      :source_updated_at,
      :replication_enqueued_at,
      :inserted_at,
      :updated_at
    ])
  end

  def delete_local_entry_if_before_or_equal(key, cutoff) when is_binary(key) do
    {count, _} =
      Cache.KeyValueWriteRepo.delete_all(
        from(entry in KeyValueEntry,
          where: entry.key == ^key,
          where: entry.source_updated_at <= ^cutoff
        )
      )

    if count > 0 do
      delete_pending_replication_entries([key])
    end

    count
  end

  @doc """
  Deletes project entries with `source_updated_at` at or before the given cutoff.

  Returns `{deleted_keys, total_count}`. When `on_deleted_keys` is provided, deleted keys
  are streamed to the callback per batch and the returned key list is always empty.

  Options:
    * `:include_pending` — include rows with pending replication tokens (default: `false`)
    * `:on_deleted_keys` — streaming callback receiving each batch of deleted keys.
      When set, keys are not accumulated in the return value (the returned key list is `[]`).
    * `:after_delete_batch` — validation callback invoked after each batch with the deleted keys.
      Return `{:error, reason}` to abort further deletion. Keys are still accumulated in the return value.
  """
  def delete_project_entries_before(account_handle, project_handle, cutoff, opts \\ []) do
    include_pending = Keyword.get(opts, :include_pending, false)
    on_deleted_keys = Keyword.get(opts, :on_deleted_keys)
    after_delete_batch = Keyword.get(opts, :after_delete_batch)
    collect_deleted_keys? = is_nil(on_deleted_keys)
    {prefix, prefix_upper_bound} = project_key_bounds(account_handle, project_handle)

    state = %{
      on_deleted_keys: on_deleted_keys,
      after_delete_batch: after_delete_batch,
      collect_deleted_keys?: collect_deleted_keys?,
      deleted_keys_acc: [],
      count_acc: 0
    }

    case delete_project_entries_before_loop(
           prefix,
           prefix_upper_bound,
           cutoff,
           include_pending,
           nil,
           state
         ) do
      {:ok, final_state} -> {Enum.reverse(final_state.deleted_keys_acc), final_state.count_acc}
      {:error, reason} -> {:error, reason}
    end
  end

  def estimated_size_bytes do
    db_path = SQLiteHelpers.db_path(KeyValueRepo)

    SQLiteHelpers.file_size(db_path) + SQLiteHelpers.wal_file_size(db_path)
  end

  def entry_count do
    KeyValueRepo.aggregate(KeyValueEntry, :count)
  end

  defp delete_expired_loop(cutoff, batch_size, deadline_ms, on_deleted_keys, cursor \\ nil, count_acc \\ 0) do
    if time_limit_reached?(deadline_ms) do
      {count_acc, :time_limit_reached}
    else
      timeout = Config.key_value_maintenance_busy_timeout_ms()

      case candidate_batch_result(cutoff, batch_size, cursor) do
        {:error, :busy} ->
          {count_acc, :busy}

        [] ->
          {count_acc, :complete}

        rows ->
          ids_to_delete = Enum.map(rows, &elem(&1, 0))
          {batch_count, status} = delete_expired_entries_with_timeout(ids_to_delete, cutoff, on_deleted_keys, timeout)

          continue_delete_expired_loop(
            cutoff,
            batch_size,
            deadline_ms,
            on_deleted_keys,
            rows,
            count_acc,
            batch_count,
            status
          )
      end
    end
  end

  defp continue_delete_expired_loop(
         _cutoff,
         _batch_size,
         _deadline_ms,
         _on_deleted_keys,
         _rows,
         count_acc,
         batch_count,
         :busy
       ) do
    {count_acc + batch_count, :busy}
  end

  defp continue_delete_expired_loop(
         cutoff,
         batch_size,
         deadline_ms,
         on_deleted_keys,
         rows,
         count_acc,
         batch_count,
         :complete
       ) do
    if batch_count > 0 do
      :timer.sleep(@batch_sleep_ms)
    end

    delete_expired_loop(cutoff, batch_size, deadline_ms, on_deleted_keys, batch_cursor(rows), count_acc + batch_count)
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
      nulls ++ non_null_candidates(cutoff, remaining, nil)
    end
  end

  defp candidate_batch_result(cutoff, batch_size, cursor) do
    candidate_batch(cutoff, batch_size, cursor)
  rescue
    error ->
      if SQLiteHelpers.contention_error?(error) do
        {:error, :busy}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp null_candidates(limit, after_id) do
    query =
      from(entry in KeyValueEntry,
        where: is_nil(entry.last_accessed_at),
        order_by: [asc: entry.id],
        limit: ^limit,
        select: {entry.id, entry.last_accessed_at}
      )

    query = apply_evictable_filter(query, false)

    query = if after_id, do: from(entry in query, where: entry.id > ^after_id), else: query

    KeyValueRepo.all(query)
  end

  defp non_null_candidates(cutoff, limit, cursor) do
    base =
      from(entry in KeyValueEntry,
        where: not is_nil(entry.last_accessed_at) and entry.last_accessed_at < ^cutoff,
        order_by: [asc: entry.last_accessed_at, asc: entry.id],
        limit: ^limit,
        select: {entry.id, entry.last_accessed_at}
      )

    base = apply_evictable_filter(base, false)

    query =
      case cursor do
        nil ->
          base

        {cursor_time, cursor_id} ->
          from(entry in base,
            where:
              entry.last_accessed_at > ^cursor_time or
                (entry.last_accessed_at == ^cursor_time and entry.id > ^cursor_id)
          )
      end

    KeyValueRepo.all(query)
  end

  defp delete_expired_entries(ids_to_delete, cutoff, on_deleted_keys) do
    ids_to_delete
    |> Enum.chunk_every(@id_chunk_size)
    |> Enum.reduce_while({0, :complete}, fn ids_chunk, {count_acc, _status} ->
      try do
        {deleted_count, deleted_keys} = delete_chunk(ids_chunk, cutoff)

        :ok = stream_deleted_keys(on_deleted_keys, deleted_keys)

        {:cont, {count_acc + deleted_count, :complete}}
      rescue
        error ->
          if SQLiteHelpers.contention_error?(error) do
            {:halt, {count_acc, :busy}}
          else
            reraise error, __STACKTRACE__
          end
      end
    end)
  end

  defp delete_chunk(ids_chunk, cutoff) do
    {:ok, {deleted_count, deleted_keys}} =
      Cache.KeyValueWriteRepo.transaction(fn ->
        verified_entries =
          KeyValueEntry
          |> where([entry], entry.id in ^ids_chunk)
          |> where([entry], is_nil(entry.last_accessed_at) or entry.last_accessed_at < ^cutoff)
          |> apply_evictable_filter(false)
          |> select([entry], {entry.id, entry.key})
          |> Cache.KeyValueWriteRepo.all()

        verified_ids = Enum.map(verified_entries, &elem(&1, 0))
        verified_keys = Enum.map(verified_entries, &elem(&1, 1))

        {deleted_count, _} =
          KeyValueEntry
          |> where([entry], entry.id in ^verified_ids)
          |> where([entry], is_nil(entry.last_accessed_at) or entry.last_accessed_at < ^cutoff)
          |> apply_evictable_filter(false)
          |> Cache.KeyValueWriteRepo.delete_all()

        delete_pending_replication_entries(verified_keys)

        {deleted_count, verified_keys}
      end)

    {deleted_count, deleted_keys}
  end

  defp delete_expired_entries_with_timeout(ids_to_delete, cutoff, on_deleted_keys, timeout) do
    SQLiteHelpers.with_repo_busy_timeout(Cache.KeyValueWriteRepo, timeout, fn ->
      delete_expired_entries(ids_to_delete, cutoff, on_deleted_keys)
    end)
  rescue
    error ->
      if SQLiteHelpers.contention_error?(error) do
        {0, :busy}
      else
        reraise error, __STACKTRACE__
      end
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

  defp prefix_project_entries_query(prefix, prefix_upper_bound, cutoff, include_pending) do
    KeyValueEntry
    |> where([entry], entry.key >= ^prefix)
    |> where([entry], entry.key < ^prefix_upper_bound)
    |> where([entry], is_nil(entry.source_updated_at) or entry.source_updated_at <= ^cutoff)
    |> apply_evictable_filter(include_pending)
  end

  defp delete_project_entries_before_loop(prefix, prefix_upper_bound, cutoff, include_pending, cursor, state) do
    # The SELECT and DELETE share a single immediate transaction, so no concurrent
    # writer can modify matching rows between the two statements. This guarantees
    # that `candidate_keys` is exactly the set of deleted keys.
    {:ok, {candidate_keys, deleted_count}} =
      Cache.KeyValueWriteRepo.transaction(
        fn ->
          candidate_keys = project_candidate_keys_batch(prefix, prefix_upper_bound, cutoff, include_pending, cursor)

          case candidate_keys do
            [] ->
              {[], 0}

            _ ->
              deleted_count = delete_project_candidate_keys_batch(candidate_keys, cutoff, include_pending)
              {candidate_keys, deleted_count}
          end
        end,
        mode: :immediate
      )

    case candidate_keys do
      [] ->
        {:ok, state}

      _ ->
        with :ok <- stream_deleted_keys(state.on_deleted_keys, candidate_keys),
             :ok <- validate_batch_continuation(state.after_delete_batch, candidate_keys) do
          next_deleted_keys_acc =
            if state.collect_deleted_keys? do
              Enum.reverse(candidate_keys, state.deleted_keys_acc)
            else
              state.deleted_keys_acc
            end

          next_state = %{
            state
            | deleted_keys_acc: next_deleted_keys_acc,
              count_acc: state.count_acc + deleted_count
          }

          delete_project_entries_before_loop(
            prefix,
            prefix_upper_bound,
            cutoff,
            include_pending,
            List.last(candidate_keys),
            next_state
          )
        end
    end
  end

  defp stream_deleted_keys(nil, _keys), do: :ok

  defp stream_deleted_keys(fun, keys) when is_function(fun, 1) do
    :ok = fun.(keys)
    :ok
  end

  defp validate_batch_continuation(nil, _keys), do: :ok

  defp validate_batch_continuation(fun, keys) when is_function(fun, 1) do
    case fun.(keys) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}

      other ->
        raise ArgumentError,
              "after_delete_batch callback must return :ok or {:error, reason}, got: #{inspect(other)}"
    end
  end

  defp project_candidate_keys_batch(prefix, prefix_upper_bound, cutoff, include_pending, cursor) do
    query =
      prefix
      |> prefix_project_entries_query(prefix_upper_bound, cutoff, include_pending)
      |> order_by([entry], asc: entry.key)
      |> limit(^@project_delete_batch_size)
      |> select([entry], entry.key)

    query = if cursor, do: from(entry in query, where: entry.key > ^cursor), else: query

    Cache.KeyValueWriteRepo.all(query)
  end

  defp delete_project_candidate_keys_batch(candidate_keys, cutoff, include_pending) do
    {count, _} =
      KeyValueEntry
      |> where([entry], entry.key in ^candidate_keys)
      |> where([entry], is_nil(entry.source_updated_at) or entry.source_updated_at <= ^cutoff)
      |> apply_evictable_filter(include_pending)
      |> Cache.KeyValueWriteRepo.delete_all()

    delete_pending_replication_entries(candidate_keys)

    count
  end

  defp project_key_bounds(account_handle, project_handle) do
    prefix = "keyvalue:#{account_handle}:#{project_handle}:"
    {prefix, next_lexicographic_string(prefix)}
  end

  defp next_lexicographic_string(value) do
    value
    |> String.to_charlist()
    |> Enum.reverse()
    |> increment_reversed_codepoints()
    |> Enum.reverse()
    |> List.to_string()
  end

  defp increment_reversed_codepoints([codepoint | rest]) when codepoint < 0x10FFFF, do: [codepoint + 1 | rest]
  defp increment_reversed_codepoints([_codepoint | rest]), do: increment_reversed_codepoints(rest)

  defp increment_reversed_codepoints([]) do
    raise ArgumentError, "value has no lexicographic successor"
  end

  defp apply_evictable_filter(query, include_pending) do
    if Config.distributed_kv_enabled?() and not include_pending do
      from(entry in query, where: is_nil(entry.replication_enqueued_at))
    else
      query
    end
  end

  defp replication_token_ref(%{replication_enqueued_at: nil}), do: nil

  defp replication_token_ref(%{id: id, replication_enqueued_at: token, last_accessed_at: last_accessed_at})
       when not is_nil(id) do
    {:id, id, token, last_accessed_at}
  end

  defp replication_token_ref(%{key: key, replication_enqueued_at: token, last_accessed_at: last_accessed_at})
       when is_binary(key) do
    {:key, key, token, last_accessed_at}
  end

  defp clear_replication_token_chunk([]), do: 0

  defp clear_replication_token_chunk(refs) do
    predicate =
      Enum.reduce(refs, dynamic(false), fn ref, dynamic ->
        replication_token_predicate(ref, dynamic)
      end)

    {count, _} =
      Cache.KeyValueWriteRepo.update_all(
        from(entry in KeyValueEntry, where: ^predicate),
        set: [replication_enqueued_at: nil]
      )

    count
  end

  defp clear_pending_replication_chunk(refs) do
    keys_to_clear =
      Enum.flat_map(refs, fn
        {:key, key, token, last_accessed_at} ->
          [{key, token, last_accessed_at}]

        _ ->
          []
      end)

    case keys_to_clear do
      [] ->
        0

      _ ->
        predicate =
          Enum.reduce(keys_to_clear, dynamic(false), fn {key, token, last_accessed_at}, dynamic ->
            dynamic(
              [entry],
              ^dynamic or
                (entry.key == ^key and entry.replication_enqueued_at == ^token and
                   entry.last_accessed_at == ^last_accessed_at)
            )
          end)

        {count, _} =
          Cache.KeyValueWriteRepo.delete_all(from(entry in KeyValuePendingReplicationEntry, where: ^predicate))

        count
    end
  end

  defp replication_token_predicate({:id, id, token, last_accessed_at}, dynamic) do
    dynamic(
      [entry],
      ^dynamic or
        (entry.id == ^id and entry.replication_enqueued_at == ^token and
           entry.last_accessed_at == ^last_accessed_at)
    )
  end

  defp replication_token_predicate({:key, key, token, last_accessed_at}, dynamic) do
    dynamic(
      [entry],
      ^dynamic or
        (entry.key == ^key and entry.replication_enqueued_at == ^token and
           entry.last_accessed_at == ^last_accessed_at)
    )
  end

  defp pending_replication_row(row) do
    Map.take(row, [
      :key,
      :json_payload,
      :source_node,
      :source_updated_at,
      :last_accessed_at,
      :replication_enqueued_at
    ])
  end

  defp merge_remote_into_local(local_entry, remote_attrs) do
    local_wins? =
      not is_nil(local_entry.replication_enqueued_at) and
        compare_source_versions(
          local_entry.source_updated_at,
          local_entry.source_node,
          remote_attrs.source_updated_at,
          Map.get(remote_attrs, :source_node)
        ) == :gt

    if local_wins? do
      %{last_accessed_at: max_datetime(local_entry.last_accessed_at, remote_attrs.last_accessed_at)}
    else
      %{
        json_payload: remote_attrs.json_payload,
        source_node: remote_attrs.source_node,
        source_updated_at: remote_attrs.source_updated_at,
        last_accessed_at: max_datetime(local_entry.last_accessed_at, remote_attrs.last_accessed_at),
        replication_enqueued_at: remote_winner_replication_token(local_entry.replication_enqueued_at, remote_attrs)
      }
    end
  end

  defp remote_winner_replication_token(nil, _remote_attrs), do: nil

  defp remote_winner_replication_token(token, %{source_updated_at: nil}), do: token

  defp remote_winner_replication_token(token, %{source_updated_at: remote_source_updated_at}) do
    if DateTime.after?(token, remote_source_updated_at), do: token
  end

  defp compare_source_versions(nil, _left_node, nil, _right_node), do: :eq
  defp compare_source_versions(nil, _left_node, _right_time, _right_node), do: :lt
  defp compare_source_versions(_left_time, _left_node, nil, _right_node), do: :gt

  defp compare_source_versions(left_time, left_node, right_time, right_node) do
    case DateTime.compare(left_time, right_time) do
      :eq -> compare_node_names(left_node || "", right_node || "")
      other -> other
    end
  end

  defp compare_node_names(left, right) when left > right, do: :gt
  defp compare_node_names(left, right) when left < right, do: :lt
  defp compare_node_names(_left, _right), do: :eq

  defp max_datetime(nil, right), do: right
  defp max_datetime(left, nil), do: left
  defp max_datetime(left, right), do: if(DateTime.before?(left, right), do: right, else: left)
end
