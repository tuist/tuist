defmodule Cache.CacheArtifactsBuffer do
  @moduledoc false

  @behaviour Cache.SQLiteBufferable

  import Ecto.Query

  alias Cache.CacheArtifact
  alias Cache.Repo
  alias Cache.SQLiteBuffer

  def start_link(opts) do
    SQLiteBuffer.start_link(Keyword.merge(opts, name: __MODULE__, buffer_module: __MODULE__))
  end

  def child_spec(opts) do
    SQLiteBuffer.child_spec(Keyword.merge(opts, name: __MODULE__, buffer_module: __MODULE__))
  end

  def enqueue_access(key, size_bytes, last_accessed_at) do
    SQLiteBuffer.enqueue(__MODULE__, {:cas_access, key, size_bytes, last_accessed_at})
  end

  def enqueue_deletes(keys) do
    SQLiteBuffer.enqueue(__MODULE__, {:cas_delete, keys})
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
  def buffer_name, do: :cas_artifacts

  @impl true
  def init_state do
    %{cas_accesses: %{}, cas_deletes: MapSet.new()}
  end

  @impl true
  def handle_event(state, {:cas_access, key, size_bytes, last_accessed_at}) do
    entry = %{key: key, size_bytes: size_bytes, last_accessed_at: last_accessed_at}
    cas_accesses = Map.put(state.cas_accesses, key, entry)
    cas_deletes = MapSet.delete(state.cas_deletes, key)
    %{state | cas_accesses: cas_accesses, cas_deletes: cas_deletes}
  end

  @impl true
  def handle_event(state, {:cas_delete, keys}) do
    cas_deletes = Enum.reduce(keys, state.cas_deletes, &MapSet.put(&2, &1))
    cas_accesses = Map.drop(state.cas_accesses, keys)
    %{state | cas_deletes: cas_deletes, cas_accesses: cas_accesses}
  end

  @impl true
  def flush_batches(state, max_batch_size) do
    {accesses_batch, accesses_rest} = SQLiteBuffer.take_map_batch(state.cas_accesses, max_batch_size)
    {deletes_batch, deletes_rest} = SQLiteBuffer.take_set_batch(state.cas_deletes, max_batch_size)

    operations =
      [
        if(map_size(accesses_batch) > 0, do: {:cas_accesses, accesses_batch}),
        if(deletes_batch != [], do: {:cas_deletes, deletes_batch})
      ]
      |> Enum.reject(&is_nil/1)

    {operations, %{state | cas_accesses: accesses_rest, cas_deletes: deletes_rest}}
  end

  @impl true
  def queue_stats(state) do
    count = map_size(state.cas_accesses) + MapSet.size(state.cas_deletes)
    %{cas_artifacts: count, total: count}
  end

  @impl true
  def queue_empty?(state) do
    map_size(state.cas_accesses) == 0 and MapSet.size(state.cas_deletes) == 0
  end

  @impl true
  def write_batch(:cas_accesses, entries) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      Enum.map(entries, fn {_key, entry} ->
        %{
          key: entry.key,
          size_bytes: entry.size_bytes,
          last_accessed_at: entry.last_accessed_at,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(CacheArtifact, rows,
      conflict_target: :key,
      on_conflict: {:replace, [:size_bytes, :last_accessed_at, :updated_at]}
    )
  end

  @impl true
  def write_batch(:cas_deletes, keys) do
    Repo.delete_all(from(a in CacheArtifact, where: a.key in ^keys))
  end
end
