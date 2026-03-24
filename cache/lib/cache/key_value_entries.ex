defmodule Cache.KeyValueEntries do
  @moduledoc """
  Context module for key-value entry management, eviction, and distributed-mode helpers.
  """

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.State
  alias Cache.KeyValueEntry
  alias Cache.KeyValueRepo
  alias Cache.SQLiteHelpers

  @id_chunk_size 500
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
  Deletes expired entries and returns `{grouped_hashes, deleted_count, status}`.

  The grouped hashes value is always empty because KV eviction no longer drives artifact cleanup.
  """
  def delete_expired(max_age_days \\ 30, opts \\ []) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)
    max_duration_ms = Keyword.get(opts, :max_duration_ms, @default_max_duration_ms)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    deadline_ms = System.monotonic_time(:millisecond) + max(max_duration_ms, 0)

    delete_expired_loop(cutoff, batch_size, deadline_ms)
  end

  @doc """
  Deletes one batch of the oldest expired entries and returns `{grouped_hashes, deleted_count, status}`.
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
            {count, status} = delete_expired_entries(ids_to_delete, cutoff)
            :timer.sleep(@batch_sleep_ms)
            {%{}, count, status}
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

  def list_pending_replication(limit \\ Config.distributed_kv_ship_batch_size()) do
    KeyValueEntry
    |> where([entry], not is_nil(entry.replication_enqueued_at))
    |> order_by([entry], asc: entry.replication_enqueued_at, asc: entry.id)
    |> limit(^limit)
    |> KeyValueRepo.all()
  end

  def clear_replication_token(key, token) when is_binary(key) do
    {count, _} =
      KeyValueRepo.update_all(
        from(entry in KeyValueEntry,
          where: entry.key == ^key,
          where: entry.replication_enqueued_at == ^token
        ),
        set: [replication_enqueued_at: nil]
      )

    count
  end

  def distributed_watermark do
    KeyValueRepo.get(State, @poller_watermark)
  end

  def put_distributed_watermark(updated_at_value, key_value) do
    put_replication_state!(@poller_watermark, updated_at_value, key_value)

    :ok
  end

  def commit_remote_batch(nil), do: :ok

  def commit_remote_batch(last_processed_row) do
    {:ok, :ok} =
      KeyValueRepo.transaction(
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
      if SQLiteHelpers.busy_error?(error) do
        {:error, :busy}
      else
        reraise error, __STACKTRACE__
      end
  end

  def materialize_remote_entry(attrs) when is_map(attrs) do
    attrs = remote_materialization_attrs(attrs)
    persisted_attrs = persisted_remote_attrs(attrs)

    {:ok, status} =
      KeyValueRepo.transaction(fn ->
        case KeyValueRepo.get_by(KeyValueEntry, key: attrs.key) do
          nil ->
            KeyValueRepo.insert!(struct(KeyValueEntry, persisted_attrs))
            :inserted

          local_entry ->
            merged = merge_remote_into_local(local_entry, attrs)

            local_entry
            |> KeyValueEntry.changeset(merged)
            |> KeyValueRepo.update!()

            case merged do
              %{json_payload: json_payload, source_updated_at: source_updated_at}
              when json_payload != local_entry.json_payload or source_updated_at != local_entry.source_updated_at ->
                :payload_updated

              _ ->
                :access_updated
            end
        end
      end)

    status
  end

  def delete_local_entry_if_not_pending(key) when is_binary(key) do
    {count, _} =
      KeyValueRepo.delete_all(
        from(entry in KeyValueEntry,
          where: entry.key == ^key,
          where: is_nil(entry.replication_enqueued_at)
        )
      )

    count
  end

  defp apply_remote_batch_transaction(rows, alive_rows, tombstone_keys, now, signature) do
    case KeyValueRepo.transaction(
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
  rescue
    error ->
      if SQLiteHelpers.busy_error?(error) do
        {:error, :busy}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp load_pending_remote_batch(signature) do
    case KeyValueRepo.get(State, @pending_remote_batch) do
      nil ->
        nil

      %State{key_value: key_value} ->
        %{signature: pending_signature, result: result} = decode_replication_state_payload!(key_value)

        case pending_signature do
          ^signature ->
            result

          _ ->
            :ok = delete_replication_state!(@pending_remote_batch)
            nil
        end
    end
  end

  defp put_pending_remote_batch!(signature, result) do
    payload = encode_replication_state_payload!(%{signature: signature, result: result})
    put_replication_state!(@pending_remote_batch, result.last_processed_row.updated_at, payload)
  end

  defp put_replication_state!(name, updated_at_value, key_value) do
    attrs = %{name: name, updated_at_value: updated_at_value, key_value: key_value}

    %State{name: name}
    |> State.changeset(attrs)
    |> KeyValueRepo.insert!(
      on_conflict: [set: [updated_at_value: updated_at_value, key_value: key_value]],
      conflict_target: :name
    )
  end

  defp delete_replication_state!(name) do
    KeyValueRepo.delete_all(from(state in State, where: state.name == ^name))
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
  defp remote_row_payload_hash(payload), do: :crypto.hash(:sha256, payload)

  defp fetch_local_entries_by_key([]), do: %{}

  defp fetch_local_entries_by_key(keys) do
    KeyValueEntry
    |> where([entry], entry.key in ^keys)
    |> KeyValueRepo.all()
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
    KeyValueRepo.insert_all(KeyValueEntry, rows,
      conflict_target: :key,
      on_conflict: {:replace, @remote_apply_conflict_fields}
    )

    :ok
  end

  defp delete_tombstoned_rows([]), do: 0

  defp delete_tombstoned_rows(keys) do
    {count, _} =
      KeyValueRepo.delete_all(
        from(entry in KeyValueEntry,
          where: entry.key in ^keys,
          where: is_nil(entry.replication_enqueued_at)
        )
      )

    count
  end

  defp remote_materialization_attrs(attrs, now \\ DateTime.truncate(DateTime.utc_now(), :second)) do
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
      KeyValueRepo.delete_all(
        from(entry in KeyValueEntry,
          where: entry.key == ^key,
          where: entry.source_updated_at <= ^cutoff
        )
      )

    count
  end

  def delete_project_entries_before(account_handle, project_handle, cutoff) do
    {prefix, prefix_upper_bound} = project_key_bounds(account_handle, project_handle)

    query = prefix_project_entries_query(prefix, prefix_upper_bound, cutoff)

    {:ok, {deleted_keys, count}} =
      KeyValueRepo.transaction(fn ->
        candidate_keys =
          query
          |> select([entry], entry.key)
          |> KeyValueRepo.all()

        count = delete_project_candidate_keys(candidate_keys, cutoff)
        remaining_key_set = candidate_keys |> existing_project_keys() |> MapSet.new()
        deleted_keys = Enum.reject(candidate_keys, &MapSet.member?(remaining_key_set, &1))
        {deleted_keys, count}
      end)

    {deleted_keys, count}
  end

  def estimated_size_bytes do
    KeyValueRepo.one(from(entry in KeyValueEntry, select: sum(fragment("length(?)", entry.json_payload)))) || 0
  end

  def entry_count do
    KeyValueRepo.aggregate(KeyValueEntry, :count)
  end

  def parse_scope(key), do: KeyValueEntry.scope_from_key(key)

  defp delete_expired_loop(cutoff, batch_size, deadline_ms, cursor \\ nil, count_acc \\ 0) do
    if time_limit_reached?(deadline_ms) do
      {%{}, count_acc, :time_limit_reached}
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
          {%{}, count_acc, :complete}

        :busy ->
          {%{}, count_acc, :busy}

        {:ok, batch_count, new_cursor} ->
          :timer.sleep(@batch_sleep_ms)
          delete_expired_loop(cutoff, batch_size, deadline_ms, new_cursor, count_acc + batch_count)
      end
    end
  end

  defp delete_candidate_batch(cutoff, batch_size, cursor) do
    case candidate_batch(cutoff, batch_size, cursor) do
      [] ->
        :empty

      rows ->
        ids = Enum.map(rows, &elem(&1, 0))
        {batch_count, status} = delete_expired_entries(ids, cutoff)

        case status do
          :busy -> :busy
          :complete -> {:ok, batch_count, batch_cursor(rows)}
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
      nulls ++ non_null_candidates(cutoff, remaining, nil)
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

    query = apply_evictable_filter(query)

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

    base = apply_evictable_filter(base)

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

  defp delete_expired_entries(ids_to_delete, cutoff) do
    ids_to_delete
    |> Enum.chunk_every(@id_chunk_size)
    |> Enum.reduce_while({0, :complete}, fn ids_chunk, {count_acc, _status} ->
      try do
        deleted_count = delete_chunk(ids_chunk, cutoff)
        {:cont, {count_acc + deleted_count, :complete}}
      rescue
        error ->
          if SQLiteHelpers.busy_error?(error) do
            {:halt, {count_acc, :busy}}
          else
            reraise error, __STACKTRACE__
          end
      end
    end)
  end

  defp delete_chunk(ids_chunk, cutoff) do
    {:ok, deleted_count} =
      KeyValueRepo.transaction(fn ->
        verified_ids =
          KeyValueEntry
          |> where([entry], entry.id in ^ids_chunk)
          |> where([entry], is_nil(entry.last_accessed_at) or entry.last_accessed_at < ^cutoff)
          |> apply_evictable_filter()
          |> select([entry], entry.id)
          |> KeyValueRepo.all()

        {deleted_count, _} =
          KeyValueEntry
          |> where([entry], entry.id in ^verified_ids)
          |> where([entry], is_nil(entry.last_accessed_at) or entry.last_accessed_at < ^cutoff)
          |> apply_evictable_filter()
          |> KeyValueRepo.delete_all()

        deleted_count
      end)

    deleted_count
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

  defp prefix_project_entries_query(prefix, prefix_upper_bound, cutoff) do
    KeyValueEntry
    |> where([entry], entry.key >= ^prefix)
    |> where([entry], entry.key < ^prefix_upper_bound)
    |> where([entry], is_nil(entry.source_updated_at) or entry.source_updated_at <= ^cutoff)
    |> apply_evictable_filter()
  end

  defp delete_project_candidate_keys([], _cutoff), do: 0

  defp delete_project_candidate_keys(candidate_keys, cutoff) do
    candidate_keys
    |> Enum.chunk_every(@id_chunk_size)
    |> Enum.reduce(0, fn keys_chunk, count_acc ->
      {chunk_count, _} =
        KeyValueEntry
        |> where([entry], entry.key in ^keys_chunk)
        |> where([entry], is_nil(entry.source_updated_at) or entry.source_updated_at <= ^cutoff)
        |> apply_evictable_filter()
        |> KeyValueRepo.delete_all()

      count_acc + chunk_count
    end)
  end

  defp existing_project_keys([]), do: []

  defp existing_project_keys(candidate_keys) do
    candidate_keys
    |> Enum.chunk_every(@id_chunk_size)
    |> Enum.flat_map(fn keys_chunk ->
      KeyValueEntry
      |> where([entry], entry.key in ^keys_chunk)
      |> select([entry], entry.key)
      |> KeyValueRepo.all()
    end)
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

  defp apply_evictable_filter(query) do
    if Config.distributed_kv_enabled?() do
      from(entry in query, where: is_nil(entry.replication_enqueued_at))
    else
      query
    end
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
        replication_enqueued_at: local_entry.replication_enqueued_at
      }
    end
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
