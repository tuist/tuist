defmodule Cache.S3TransfersBuffer do
  @moduledoc false

  @behaviour Cache.SQLiteBufferable

  import Ecto.Query

  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.SQLiteBuffer

  def start_link(opts) do
    SQLiteBuffer.start_link(Keyword.merge(opts, name: __MODULE__, buffer_module: __MODULE__))
  end

  def child_spec(opts) do
    SQLiteBuffer.child_spec(Keyword.merge(opts, name: __MODULE__, buffer_module: __MODULE__))
  end

  def enqueue(type, account_handle, project_handle, artifact_type, key) do
    entry = %{
      id: UUIDv7.generate(),
      type: type,
      account_handle: account_handle,
      project_handle: project_handle,
      artifact_type: artifact_type,
      key: key,
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    true = :ets.insert(__MODULE__, {{:insert, type, key}, entry})
    :ok
  end

  def enqueue_delete(id) do
    true = :ets.insert(__MODULE__, {{:delete, id}, :delete})
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
  def buffer_name, do: :s3_transfers

  @impl true
  def flush_entries(table, max_batch_size) do
    insert_spec = [{{{:insert, :"$1", :"$2"}, :"$3"}, [], [:"$_"]}]
    delete_spec = [{{{:delete, :"$1"}, :delete}, [], [:"$_"]}]

    inserts =
      case :ets.select(table, insert_spec, max_batch_size) do
        {entries, _continuation} ->
          Enum.each(entries, &:ets.delete_object(table, &1))
          entries

        :"$end_of_table" ->
          []
      end

    deletes =
      case :ets.select(table, delete_spec, max_batch_size) do
        {entries, _continuation} ->
          Enum.each(entries, &:ets.delete_object(table, &1))
          Enum.map(entries, fn {{:delete, id}, :delete} -> id end)

        :"$end_of_table" ->
          []
      end

    operations =
      Enum.reject(
        [
          if(inserts != [], do: {:s3_inserts, Map.new(inserts)}),
          if(deletes != [], do: {:s3_deletes, deletes})
        ],
        &is_nil/1
      )

    operations
  end

  @impl true
  def queue_stats(table) do
    count = SQLiteBuffer.table_size(table)
    %{s3_transfers: count, total: count}
  end

  @impl true
  def queue_empty?(table), do: SQLiteBuffer.table_size(table) == 0

  @impl true
  def write_batch(:s3_inserts, entries) do
    rows =
      Enum.map(entries, fn {_key, entry} ->
        %{
          id: entry.id,
          type: entry.type,
          account_handle: entry.account_handle,
          project_handle: entry.project_handle,
          artifact_type: entry.artifact_type,
          key: entry.key,
          inserted_at: entry.inserted_at
        }
      end)

    Repo.insert_all(S3Transfer, rows,
      conflict_target: [:type, :key],
      on_conflict: :nothing
    )
  end

  @impl true
  def write_batch(:s3_deletes, ids) do
    Repo.delete_all(from(t in S3Transfer, where: t.id in ^ids))
  end
end
