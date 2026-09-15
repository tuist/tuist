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

  # Entries collapse per key until the flush, so a plain access queued behind a
  # completion inherits the digest that completion recorded instead of
  # replacing the entry that carries it.
  def enqueue_access(key, size_bytes, last_accessed_at, name \\ __MODULE__) do
    insert_access(name, key, size_bytes, last_accessed_at, pending_content_sha256(key, name))
  end

  def enqueue_access_with_content_sha256(key, size_bytes, last_accessed_at, content_sha256, name \\ __MODULE__) do
    insert_access(name, key, size_bytes, last_accessed_at, {:set, content_sha256})
  end

  @doc """
  The content digest a queued entry decides for `key`: `{:set, digest}` (where
  `nil` clears it), or `:keep` when nothing queued changes the stored value.
  """
  def pending_content_sha256(key, name \\ __MODULE__) do
    with :ok <- table_exists(name),
         [{^key, {:access, %{content_sha256: {:set, _} = pending}}}] <- :ets.lookup(name, key) do
      pending
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

  defp insert_access(name, key, size_bytes, last_accessed_at, content_sha256) do
    entry = %{
      key: key,
      size_bytes: size_bytes,
      last_accessed_at: last_accessed_at,
      content_sha256: content_sha256
    }

    true = :ets.insert(name, {key, {:access, entry}})
    :ok
  end

  defp table_exists(name) do
    if :ets.whereis(name) == :undefined, do: :missing, else: :ok
  end

  @impl true
  def buffer_name, do: :cache_artifacts

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
    %{cache_artifacts: count, total: count}
  end

  @impl true
  def queue_empty?(table), do: SQLiteBuffer.table_size(table) == 0

  @impl true
  def write_batch(:artifact_accesses, entries) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {with_digest, without_digest} =
      entries
      |> Enum.map(fn {_key, entry} -> entry end)
      |> Enum.split_with(&match?(%{content_sha256: {:set, _}}, &1))

    insert_accesses(without_digest, now, false)
    insert_accesses(with_digest, now, true)
  end

  @impl true
  def write_batch(:artifact_deletes, keys) do
    Repo.delete_all(from(a in CacheArtifact, where: a.key in ^keys))
  end

  defp insert_accesses([], _now, _records_digest), do: {0, nil}

  defp insert_accesses(entries, now, records_digest) do
    rows = Enum.map(entries, &access_row(&1, now, records_digest))

    replaced =
      if records_digest,
        do: [:size_bytes, :last_accessed_at, :content_sha256, :updated_at],
        else: [:size_bytes, :last_accessed_at, :updated_at]

    Repo.insert_all(CacheArtifact, rows, conflict_target: :key, on_conflict: {:replace, replaced})
  end

  defp access_row(entry, now, false) do
    %{
      key: entry.key,
      size_bytes: entry.size_bytes,
      last_accessed_at: entry.last_accessed_at,
      inserted_at: now,
      updated_at: now
    }
  end

  defp access_row(%{content_sha256: {:set, content_sha256}} = entry, now, true) do
    entry
    |> access_row(now, false)
    |> Map.put(:content_sha256, content_sha256)
  end
end
