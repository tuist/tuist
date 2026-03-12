defmodule Cache.KeyValueEntries do
  @moduledoc """
  Context module for key-value entry management, eviction, and distributed-mode helpers.
  """

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.Logic
  alias Cache.DistributedKV.State
  alias Cache.KeyValueEntry
  alias Cache.KeyValueRepo
  alias Cache.SQLiteHelpers

  @id_chunk_size 500
  @default_batch_size 1000
  @default_max_duration_ms 300_000
  @batch_sleep_ms 10
  @poller_watermark "poller_watermark"

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
    attrs = %{name: @poller_watermark, updated_at_value: updated_at_value, key_value: key_value}

    _result =
      %State{name: @poller_watermark}
      |> State.changeset(attrs)
      |> KeyValueRepo.insert(
        on_conflict: [set: [updated_at_value: updated_at_value, key_value: key_value]],
        conflict_target: :name
      )

    :ok
  end

  def materialize_remote_entry(attrs) when is_map(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    attrs =
      Map.merge(
        %{
          inserted_at: now,
          updated_at: now,
          replication_enqueued_at: nil
        },
        attrs
      )

    persisted_attrs =
      Map.take(attrs, [
        :key,
        :json_payload,
        :last_accessed_at,
        :source_updated_at,
        :replication_enqueued_at,
        :inserted_at,
        :updated_at
      ])

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
    query =
      from(entry in KeyValueEntry,
        where: like(entry.key, ^"keyvalue:#{account_handle}:#{project_handle}:%"),
        where: is_nil(entry.replication_enqueued_at),
        where: is_nil(entry.source_updated_at) or entry.source_updated_at <= ^cutoff,
        select: entry.key
      )

    keys = KeyValueRepo.all(query)

    {count, _} =
      KeyValueRepo.delete_all(
        from(entry in KeyValueEntry,
          where: entry.key in ^keys
        )
      )

    {keys, count}
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
        Logic.compare_source_versions(
          local_entry.source_updated_at,
          local_entry.source_updated_at && Config.distributed_kv_node_name(),
          remote_attrs.source_updated_at,
          Map.get(remote_attrs, :source_node)
        ) == :gt

    if local_wins? do
      %{last_accessed_at: Logic.max_datetime(local_entry.last_accessed_at, remote_attrs.last_accessed_at)}
    else
      %{
        json_payload: remote_attrs.json_payload,
        source_updated_at: remote_attrs.source_updated_at,
        last_accessed_at: Logic.max_datetime(local_entry.last_accessed_at, remote_attrs.last_accessed_at),
        replication_enqueued_at: local_entry.replication_enqueued_at
      }
    end
  end
end
