defmodule Cache.KeyValueBuffer do
  @moduledoc false

  @behaviour Cache.SQLiteBufferable

  import Ecto.Query

  alias Cache.Config
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValuePendingReplicationEntry
  alias Cache.KeyValueWriteRepo
  alias Cache.SQLiteBuffer

  @query_chunk_size 500

  def start_link(opts) do
    SQLiteBuffer.start_link(Keyword.merge(opts, name: __MODULE__, buffer_module: __MODULE__))
  end

  def child_spec(opts) do
    SQLiteBuffer.child_spec(Keyword.merge(opts, name: __MODULE__, buffer_module: __MODULE__))
  end

  def enqueue(key, json_payload, name \\ __MODULE__) do
    entry = %{key: key, json_payload: json_payload}
    true = :ets.insert(name, {key, {:write, entry}})
    :ok
  end

  def enqueue_access(key, name \\ __MODULE__) do
    entry = %{key: key}
    _inserted? = :ets.insert_new(name, {key, {:access, entry}})
    :ok
  end

  def flush do
    SQLiteBuffer.flush(__MODULE__)
  end

  def queue_stats do
    SQLiteBuffer.queue_stats(__MODULE__)
  end

  @doc false
  def reset do
    SQLiteBuffer.reset(__MODULE__)
  end

  @impl true
  def buffer_name, do: :key_values

  @impl true
  def flush_entries(table, max_batch_size) do
    write_spec = [{{:"$1", {:write, :"$2"}}, [], [:"$_"]}]
    access_spec = [{{:"$1", {:access, :"$2"}}, [], [:"$_"]}]

    writes =
      case :ets.select(table, write_spec, max_batch_size) do
        {entries, _continuation} ->
          entries

        :"$end_of_table" ->
          []
      end

    accesses =
      case :ets.select(table, access_spec, max_batch_size) do
        {entries, _continuation} ->
          entries

        :"$end_of_table" ->
          []
      end

    Enum.reject(
      [
        if(writes != [],
          do: {:key_values, Map.new(Enum.map(writes, fn {key, {:write, entry}} -> {key, entry} end)), writes}
        ),
        if(accesses != [],
          do:
            {:key_value_accesses, Map.new(Enum.map(accesses, fn {key, {:access, entry}} -> {key, entry} end)), accesses}
        )
      ],
      &is_nil/1
    )
  end

  @impl true
  def queue_stats(table) do
    count = SQLiteBuffer.table_size(table)
    %{key_values: count, total: count}
  end

  @impl true
  def queue_empty?(table), do: SQLiteBuffer.table_size(table) == 0

  @impl true
  def write_batch(:key_values, entries) do
    now = DateTime.utc_now()
    now_truncated = DateTime.truncate(now, :second)
    distributed? = Config.distributed_kv_enabled?()

    rows =
      Enum.map(entries, fn {_key, entry} ->
        %{
          key: entry.key,
          json_payload: entry.json_payload,
          source_node: if(distributed?, do: Config.distributed_kv_node_name()),
          last_accessed_at: now,
          inserted_at: now_truncated,
          updated_at: now_truncated,
          source_updated_at: if(distributed?, do: now)
        }
      end)

    rows
    |> Enum.chunk_every(@query_chunk_size)
    |> Enum.each(fn rows_chunk ->
      if distributed? do
        {:ok, :ok} =
          KeyValueWriteRepo.transaction(fn ->
            insert_key_value_rows(rows_chunk)
            KeyValueEntries.sync_pending_replication_entries(add_replication_tokens(rows_chunk, now))
            :ok
          end)
      else
        insert_key_value_rows(rows_chunk)
        KeyValueEntries.delete_pending_replication_entries(Enum.map(rows_chunk, & &1.key))
      end
    end)
  end

  @impl true
  def write_batch(:key_value_accesses, entries) do
    now = DateTime.utc_now()
    now_truncated = DateTime.truncate(now, :second)
    keys = Enum.map(entries, fn {_key, entry} -> entry.key end)
    distributed? = Config.distributed_kv_enabled?()

    keys
    |> Enum.chunk_every(@query_chunk_size)
    |> Enum.each(fn keys_chunk ->
      if distributed? do
        {:ok, :ok} =
          KeyValueWriteRepo.transaction(fn ->
            KeyValueWriteRepo.update_all(
              from(entry in KeyValueEntry,
                where: entry.key in ^keys_chunk,
                update: [set: [last_accessed_at: ^now, updated_at: ^now_truncated]]
              ),
              []
            )

            queue_rows =
              KeyValueWriteRepo.all(
                from(entry in KeyValueEntry,
                  left_join: pending in KeyValuePendingReplicationEntry,
                  on: pending.key == entry.key,
                  where: entry.key in ^keys_chunk,
                  where: not is_nil(entry.source_updated_at),
                  select: %{
                    key: entry.key,
                    json_payload: entry.json_payload,
                    source_node: entry.source_node,
                    source_updated_at: entry.source_updated_at,
                    last_accessed_at: entry.last_accessed_at,
                    replication_enqueued_at:
                      type(fragment("COALESCE(?, ?)", pending.replication_enqueued_at, ^now), :utc_datetime_usec)
                  }
                )
              )

            KeyValueEntries.sync_pending_replication_entries(queue_rows)
            :ok
          end)
      else
        KeyValueWriteRepo.update_all(from(entry in KeyValueEntry, where: entry.key in ^keys_chunk),
          set: [last_accessed_at: now, updated_at: now_truncated]
        )
      end
    end)
  end

  defp insert_key_value_rows(rows) do
    KeyValueWriteRepo.insert_all(KeyValueEntry, rows,
      conflict_target: :key,
      on_conflict: {:replace, [:json_payload, :source_node, :last_accessed_at, :updated_at, :source_updated_at]}
    )
  end

  defp add_replication_tokens(rows, token) do
    Enum.map(rows, &Map.put(&1, :replication_enqueued_at, token))
  end
end
