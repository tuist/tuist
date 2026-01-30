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
    SQLiteBuffer.enqueue(
      __MODULE__,
      {:s3_insert, type, account_handle, project_handle, artifact_type, key}
    )
  end

  def enqueue_deletes(ids) do
    SQLiteBuffer.enqueue(__MODULE__, {:s3_delete, ids})
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
  def init_state do
    %{s3_inserts: %{}, s3_deletes: MapSet.new()}
  end

  @impl true
  def handle_event(state, {:s3_insert, type, account_handle, project_handle, artifact_type, key}) do
    entry = %{
      id: UUIDv7.generate(),
      type: type,
      account_handle: account_handle,
      project_handle: project_handle,
      artifact_type: artifact_type,
      key: key,
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    key_tuple = {type, key}
    %{state | s3_inserts: Map.put(state.s3_inserts, key_tuple, entry)}
  end

  @impl true
  def handle_event(state, {:s3_delete, ids}) do
    s3_deletes = Enum.reduce(ids, state.s3_deletes, &MapSet.put(&2, &1))
    %{state | s3_deletes: s3_deletes}
  end

  @impl true
  def flush_batches(state, max_batch_size) do
    {inserts_batch, inserts_rest} = SQLiteBuffer.take_map_batch(state.s3_inserts, max_batch_size)
    {deletes_batch, deletes_rest} = SQLiteBuffer.take_set_batch(state.s3_deletes, max_batch_size)

    operations =
      Enum.reject(
        [
          if(map_size(inserts_batch) > 0, do: {:s3_inserts, inserts_batch}),
          if(deletes_batch != [], do: {:s3_deletes, deletes_batch})
        ],
        &is_nil/1
      )

    {operations, %{state | s3_inserts: inserts_rest, s3_deletes: deletes_rest}}
  end

  @impl true
  def queue_stats(state) do
    count = map_size(state.s3_inserts) + MapSet.size(state.s3_deletes)
    %{s3_transfers: count, total: count}
  end

  @impl true
  def queue_empty?(state) do
    map_size(state.s3_inserts) == 0 and MapSet.size(state.s3_deletes) == 0
  end

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
