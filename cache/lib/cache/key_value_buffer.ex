defmodule Cache.KeyValueBuffer do
  @moduledoc false

  @behaviour Cache.SQLiteBufferable

  import Ecto.Query

  alias Cache.KeyValueEntry
  alias Cache.Repo
  alias Cache.SQLiteBuffer

  def start_link(opts) do
    SQLiteBuffer.start_link(Keyword.merge(opts, name: __MODULE__, buffer_module: __MODULE__))
  end

  def child_spec(opts) do
    SQLiteBuffer.child_spec(Keyword.merge(opts, name: __MODULE__, buffer_module: __MODULE__))
  end

  def enqueue(key, json_payload) do
    entry = %{key: key, json_payload: json_payload}
    true = :ets.insert(__MODULE__, {key, {:write, entry}})
    :ok
  end

  def enqueue_access(key) do
    entry = %{key: key}
    _inserted? = :ets.insert_new(__MODULE__, {key, {:access, entry}})
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
          Enum.each(entries, &:ets.delete_object(table, &1))
          Enum.map(entries, fn {key, {:write, entry}} -> {key, entry} end)

        :"$end_of_table" ->
          []
      end

    accesses =
      case :ets.select(table, access_spec, max_batch_size) do
        {entries, _continuation} ->
          Enum.each(entries, &:ets.delete_object(table, &1))
          Enum.map(entries, fn {key, {:access, entry}} -> {key, entry} end)

        :"$end_of_table" ->
          []
      end

    Enum.reject(
      [
        if(writes != [], do: {:key_values, Map.new(writes)}),
        if(accesses != [], do: {:key_value_accesses, Map.new(accesses)})
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
    now = DateTime.truncate(DateTime.utc_now(), :second)
    last_accessed_at = DateTime.utc_now()

    rows =
      Enum.map(entries, fn {_key, entry} ->
        %{
          key: entry.key,
          json_payload: entry.json_payload,
          last_accessed_at: last_accessed_at,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(KeyValueEntry, rows,
      conflict_target: :key,
      on_conflict: {:replace, [:json_payload, :last_accessed_at, :updated_at]}
    )
  end

  @impl true
  def write_batch(:key_value_accesses, entries) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    last_accessed_at = DateTime.utc_now()
    keys = Enum.map(entries, fn {_key, entry} -> entry.key end)

    Repo.update_all(
      from(e in KeyValueEntry, where: e.key in ^keys),
      set: [last_accessed_at: last_accessed_at, updated_at: now]
    )
  end
end
