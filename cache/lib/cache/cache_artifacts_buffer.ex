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
    entry = %{key: key, size_bytes: size_bytes, last_accessed_at: last_accessed_at}
    true = :ets.insert(__MODULE__, {key, {:access, entry}})
    :ok
  end

  def enqueue_deletes(keys) do
    Enum.each(keys, fn key ->
      true = :ets.insert(__MODULE__, {key, :delete})
    end)

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
  def buffer_name, do: :cas_artifacts

  @impl true
  def flush_entries(table, max_batch_size) do
    access_spec = [{{:"$1", {:access, :"$2"}}, [], [:"$_"]}]
    delete_spec = [{{:"$1", :delete}, [], [:"$_"]}]

    accesses =
      case :ets.select(table, access_spec, max_batch_size) do
        {entries, _continuation} ->
          Enum.each(entries, &:ets.delete_object(table, &1))
          Enum.map(entries, fn {key, {:access, entry}} -> {key, entry} end)

        :"$end_of_table" ->
          []
      end

    deletes =
      case :ets.select(table, delete_spec, max_batch_size) do
        {entries, _continuation} ->
          Enum.each(entries, &:ets.delete_object(table, &1))
          Enum.map(entries, fn {key, :delete} -> key end)

        :"$end_of_table" ->
          []
      end

    operations =
      Enum.reject(
        [
          if(accesses != [], do: {:artifact_accesses, Map.new(accesses)}),
          if(deletes != [], do: {:artifact_deletes, deletes})
        ],
        &is_nil/1
      )

    operations
  end

  @impl true
  def queue_stats(table) do
    count = SQLiteBuffer.table_size(table)
    %{cas_artifacts: count, total: count}
  end

  @impl true
  def queue_empty?(table), do: SQLiteBuffer.table_size(table) == 0

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
