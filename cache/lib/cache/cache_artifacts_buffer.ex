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
    SQLiteBuffer.enqueue(__MODULE__, {:artifact_access, key, size_bytes, last_accessed_at})
  end

  def enqueue_deletes(keys) do
    SQLiteBuffer.enqueue(__MODULE__, {:artifact_delete, keys})
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
    %{artifact_accesses: %{}, artifact_deletes: MapSet.new()}
  end

  @impl true
  def handle_event(state, {:artifact_access, key, size_bytes, last_accessed_at}) do
    entry = %{key: key, size_bytes: size_bytes, last_accessed_at: last_accessed_at}
    artifact_accesses = Map.put(state.artifact_accesses, key, entry)
    artifact_deletes = MapSet.delete(state.artifact_deletes, key)
    %{state | artifact_accesses: artifact_accesses, artifact_deletes: artifact_deletes}
  end

  @impl true
  def handle_event(state, {:artifact_delete, keys}) do
    artifact_deletes = Enum.reduce(keys, state.artifact_deletes, &MapSet.put(&2, &1))
    artifact_accesses = Map.drop(state.artifact_accesses, keys)
    %{state | artifact_deletes: artifact_deletes, artifact_accesses: artifact_accesses}
  end

  @impl true
  def flush_batches(state, max_batch_size) do
    {accesses_batch, accesses_rest} = SQLiteBuffer.take_map_batch(state.artifact_accesses, max_batch_size)
    {deletes_batch, deletes_rest} = SQLiteBuffer.take_set_batch(state.artifact_deletes, max_batch_size)

    operations =
      Enum.reject(
        [
          if(map_size(accesses_batch) > 0, do: {:artifact_accesses, accesses_batch}),
          if(deletes_batch != [], do: {:artifact_deletes, deletes_batch})
        ],
        &is_nil/1
      )

    {operations, %{state | artifact_accesses: accesses_rest, artifact_deletes: deletes_rest}}
  end

  @impl true
  def queue_stats(state) do
    count = map_size(state.artifact_accesses) + MapSet.size(state.artifact_deletes)
    %{cas_artifacts: count, total: count}
  end

  @impl true
  def queue_empty?(state) do
    map_size(state.artifact_accesses) == 0 and MapSet.size(state.artifact_deletes) == 0
  end

  @impl true
  def write_batch(:artifact_accesses, entries) do
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
  def write_batch(:artifact_deletes, keys) do
    Repo.delete_all(from(a in CacheArtifact, where: a.key in ^keys))
  end
end
