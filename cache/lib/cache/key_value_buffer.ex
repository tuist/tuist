defmodule Cache.KeyValueBuffer do
  @moduledoc false

  @behaviour Cache.SQLiteBufferable

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
    true = :ets.insert(__MODULE__, {key, %{key: key, json_payload: json_payload}})
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
    match_spec = [{{:"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}]

    case :ets.select(table, match_spec, max_batch_size) do
      {entries, _continuation} ->
        Enum.each(entries, &:ets.delete_object(table, &1))
        [{:key_values, Map.new(entries)}]

      :"$end_of_table" ->
        []
    end
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

    rows =
      Enum.map(entries, fn {_key, entry} ->
        %{
          key: entry.key,
          json_payload: entry.json_payload,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(KeyValueEntry, rows,
      conflict_target: :key,
      on_conflict: {:replace, [:json_payload, :updated_at]}
    )
  end
end
