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
    SQLiteBuffer.enqueue(__MODULE__, {:key_value, key, json_payload})
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
  def init_state, do: %{entries: %{}}

  @impl true
  def handle_event(state, {:key_value, key, json_payload}) do
    entries = Map.put(state.entries, key, %{key: key, json_payload: json_payload})
    %{state | entries: entries}
  end

  @impl true
  def flush_batches(state, max_batch_size) do
    {batch, rest} = SQLiteBuffer.take_map_batch(state.entries, max_batch_size)

    operations =
      if map_size(batch) == 0 do
        []
      else
        [{:key_values, batch}]
      end

    {operations, %{state | entries: rest}}
  end

  @impl true
  def queue_stats(state) do
    count = map_size(state.entries)
    %{key_values: count, total: count}
  end

  @impl true
  def queue_empty?(state), do: map_size(state.entries) == 0

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
