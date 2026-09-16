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

  def enqueue_access(key, size_bytes, last_accessed_at, name \\ __MODULE__) do
    entry = %{key: key, size_bytes: size_bytes, last_accessed_at: last_accessed_at}
    true = :ets.insert(name, {key, {:access, entry}})
    :ok
  end

  # Queued under its own entry rather than merged into the key's access entry.
  # Each enqueue is then a single insert that reads nothing, so an access can
  # never overwrite a digest recorded between reading the queue and writing to it.
  def enqueue_content_sha256(key, size_bytes, last_accessed_at, content_sha256, name \\ __MODULE__) do
    entry = %{key: key, size_bytes: size_bytes, last_accessed_at: last_accessed_at, content_sha256: content_sha256}
    true = :ets.insert(name, {{:content_sha256, key}, {:content_sha256, entry}})
    :ok
  end

  @doc """
  The content digest queued for `key` and not flushed yet: `{:set, digest}` (where
  `nil` clears it), or `:keep` when nothing queued changes the stored value.
  """
  def pending_content_sha256(key, name \\ __MODULE__) do
    with :ok <- table_exists(name),
         [{_entry_key, {:content_sha256, %{content_sha256: content_sha256}}}] <-
           :ets.lookup(name, {:content_sha256, key}) do
      {:set, content_sha256}
    else
      _ -> :keep
    end
  end

  def enqueue_delete(key, name \\ __MODULE__) do
    true = :ets.insert(name, {key, :delete})
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

  defp table_exists(name) do
    if :ets.whereis(name) == :undefined, do: :missing, else: :ok
  end

  @impl true
  def buffer_name, do: :cache_artifacts

  @impl true
  def flush_entries(table, max_batch_size) do
    access_spec = [{{:"$1", {:access, :"$2"}}, [], [:"$_"]}]
    content_sha256_spec = [{{:"$1", {:content_sha256, :"$2"}}, [], [:"$_"]}]
    delete_spec = [{{:"$1", :delete}, [], [:"$_"]}]

    accesses = take_entries(table, access_spec, max_batch_size, fn {key, {:access, entry}} -> {key, entry} end)

    content_sha256s =
      take_entries(table, content_sha256_spec, max_batch_size, fn {_entry_key, {:content_sha256, entry}} ->
        {entry.key, entry}
      end)

    deletes = take_entries(table, delete_spec, max_batch_size, fn {key, :delete} -> key end)

    # Deletes go last, so an artifact evicted after its digest was queued ends
    # the flush without a row.
    Enum.reject(
      [
        if(accesses != [], do: {:artifact_accesses, Map.new(accesses)}),
        if(content_sha256s != [], do: {:artifact_content_sha256s, Map.new(content_sha256s)}),
        if(deletes != [], do: {:artifact_deletes, deletes})
      ],
      &is_nil/1
    )
  end

  defp take_entries(table, spec, max_batch_size, to_entry) do
    case :ets.select(table, spec, max_batch_size) do
      {entries, _continuation} ->
        Enum.each(entries, &:ets.delete_object(table, &1))
        Enum.map(entries, to_entry)

      :"$end_of_table" ->
        []
    end
  end

  @impl true
  def queue_stats(table) do
    count = SQLiteBuffer.table_size(table)
    %{cache_artifacts: count, total: count}
  end

  @impl true
  def queue_empty?(table), do: SQLiteBuffer.table_size(table) == 0

  @impl true
  def write_batch(:artifact_accesses, entries) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    rows = Enum.map(entries, fn {_key, entry} -> access_row(entry, now) end)

    Repo.insert_all(CacheArtifact, rows,
      conflict_target: :key,
      on_conflict: {:replace, [:size_bytes, :last_accessed_at, :updated_at]}
    )
  end

  @impl true
  def write_batch(:artifact_content_sha256s, entries) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      Enum.map(entries, fn {_key, entry} ->
        entry |> access_row(now) |> Map.put(:content_sha256, entry.content_sha256)
      end)

    Repo.insert_all(CacheArtifact, rows,
      conflict_target: :key,
      on_conflict: {:replace, [:content_sha256, :updated_at]}
    )
  end

  @impl true
  def write_batch(:artifact_deletes, keys) do
    Repo.delete_all(from(a in CacheArtifact, where: a.key in ^keys))
  end

  defp access_row(entry, now) do
    %{
      key: entry.key,
      size_bytes: entry.size_bytes,
      last_accessed_at: entry.last_accessed_at,
      inserted_at: now,
      updated_at: now
    }
  end
end
