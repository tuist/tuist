defmodule Cache.SQLiteWriter do
  @moduledoc """
  Serializes SQLite writes and flushes them in batches.
  """

  use GenServer

  require Ecto.Query
  require Logger

  alias Cache.CacheArtifact
  alias Cache.KeyValueEntry
  alias Cache.Repo
  alias Cache.S3Transfer

  @default_flush_interval_ms 200
  @default_flush_timeout_ms 30_000
  @default_max_batch_size 1000
  @default_retry_max_attempts 5
  @default_retry_base_delay_ms 50
  @default_retry_max_delay_ms 2000
  @default_shutdown_ms 30_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def child_spec(opts) do
    shutdown_ms = config_value(:shutdown_ms, @default_shutdown_ms)

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      shutdown: shutdown_ms
    }
  end

  def enqueue_key_value(key, json_payload) do
    GenServer.call(__MODULE__, {:enqueue, {:key_value, key, json_payload}})
  end

  def enqueue_cas_access(key, size_bytes, last_accessed_at) do
    GenServer.call(__MODULE__, {:enqueue, {:cas_access, key, size_bytes, last_accessed_at}})
  end

  def enqueue_cas_deletes(keys) when is_list(keys) do
    GenServer.call(__MODULE__, {:enqueue, {:cas_delete, keys}})
  end

  def enqueue_s3_transfer(type, account_handle, project_handle, artifact_type, key)
      when type in [:upload, :download] and artifact_type in [:cas, :module] do
    GenServer.call(
      __MODULE__,
      {:enqueue, {:s3_insert, type, account_handle, project_handle, artifact_type, key}}
    )
  end

  def enqueue_s3_transfer_deletes(ids) when is_list(ids) do
    GenServer.call(__MODULE__, {:enqueue, {:s3_delete, ids}})
  end

  def flush(scope \\ :all) do
    GenServer.call(__MODULE__, {:flush, scope}, flush_timeout_ms())
  end

  @doc false
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  def queue_stats do
    GenServer.call(__MODULE__, :queue_stats)
  end

  @impl true
  def init(:ok) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       key_values: %{},
       cas_accesses: %{},
       cas_deletes: MapSet.new(),
       s3_inserts: %{},
       s3_deletes: MapSet.new(),
       timer_ref: nil,
       flush_interval_ms: config_value(:flush_interval_ms, @default_flush_interval_ms),
       flush_timeout_ms: config_value(:flush_timeout_ms, @default_flush_timeout_ms),
       max_batch_size: config_value(:max_batch_size, @default_max_batch_size),
       retry_max_attempts: config_value(:retry_max_attempts, @default_retry_max_attempts),
       retry_base_delay_ms: config_value(:retry_base_delay_ms, @default_retry_base_delay_ms),
       retry_max_delay_ms: config_value(:retry_max_delay_ms, @default_retry_max_delay_ms)
     }}
  end

  @impl true
  def handle_call({:enqueue, operation}, _from, state) do
    state = enqueue_operation(state, operation)
    state = ensure_flush_timer(state)
    state = maybe_request_flush(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:flush, scope}, _from, state) do
    state = cancel_flush_timer(state)
    {state, result} = flush_state(state, scope, :drain)
    state = ensure_flush_timer(state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:queue_stats, _from, state) do
    {:reply, build_queue_stats(state), state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    state = cancel_flush_timer(state)

    {:reply, :ok,
     %{
       state
       | key_values: %{},
         cas_accesses: %{},
         cas_deletes: MapSet.new(),
         s3_inserts: %{},
         s3_deletes: MapSet.new()
     }}
  end

  @impl true
  def handle_info(:flush, state) do
    state = %{state | timer_ref: nil}
    {state, _result} = flush_state(state, :all, :batch)
    state = ensure_flush_timer(state)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    _ = flush_state(state, :all, :drain)
    :ok
  end

  defp enqueue_operation(state, {:key_value, key, json_payload}) do
    %{state | key_values: Map.put(state.key_values, key, %{key: key, json_payload: json_payload})}
  end

  defp enqueue_operation(state, {:cas_access, key, size_bytes, last_accessed_at}) do
    entry = %{key: key, size_bytes: size_bytes, last_accessed_at: last_accessed_at}
    cas_accesses = Map.put(state.cas_accesses, key, entry)
    cas_deletes = MapSet.delete(state.cas_deletes, key)
    %{state | cas_accesses: cas_accesses, cas_deletes: cas_deletes}
  end

  defp enqueue_operation(state, {:cas_delete, keys}) do
    cas_deletes = Enum.reduce(keys, state.cas_deletes, &MapSet.put(&2, &1))
    cas_accesses = Map.drop(state.cas_accesses, keys)
    %{state | cas_deletes: cas_deletes, cas_accesses: cas_accesses}
  end

  defp enqueue_operation(state, {:s3_insert, type, account_handle, project_handle, artifact_type, key}) do
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

  defp enqueue_operation(state, {:s3_delete, ids}) do
    s3_deletes = Enum.reduce(ids, state.s3_deletes, &MapSet.put(&2, &1))
    %{state | s3_deletes: s3_deletes}
  end

  defp flush_state(state, scope, mode) do
    {state, operations} = take_operations(state, scope, state.max_batch_size)
    state = Enum.reduce(operations, state, &execute_operation/2)

    state =
      if mode == :drain and queue_remaining?(state, scope) do
        flush_state(state, scope, mode) |> elem(0)
      else
        state
      end

    {state, :ok}
  end

  defp execute_operation({:key_values, entries}, state) do
    batch_size = map_size(entries)

    {duration_ms, _} =
      :timer.tc(fn ->
        with_retry(fn ->
          now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

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
        end, :key_values, state)
      end)

    emit_flush_metrics(:key_values, duration_ms, batch_size)
    state
  end

  defp execute_operation({:cas_accesses, entries}, state) do
    batch_size = map_size(entries)

    {duration_ms, _} =
      :timer.tc(fn ->
        with_retry(fn ->
          now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

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
        end, :cas_accesses, state)
      end)

    emit_flush_metrics(:cas_accesses, duration_ms, batch_size)
    state
  end

  defp execute_operation({:cas_deletes, keys}, state) do
    batch_size = length(keys)

    {duration_ms, _} =
      :timer.tc(fn ->
        with_retry(fn ->
          Repo.delete_all(Ecto.Query.from(a in CacheArtifact, where: a.key in ^keys))
        end, :cas_deletes, state)
      end)

    emit_flush_metrics(:cas_deletes, duration_ms, batch_size)
    state
  end

  defp execute_operation({:s3_inserts, entries}, state) do
    batch_size = map_size(entries)

    {duration_ms, _} =
      :timer.tc(fn ->
        with_retry(fn ->
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
        end, :s3_inserts, state)
      end)

    emit_flush_metrics(:s3_inserts, duration_ms, batch_size)
    state
  end

  defp execute_operation({:s3_deletes, ids}, state) do
    batch_size = length(ids)

    {duration_ms, _} =
      :timer.tc(fn ->
        with_retry(fn ->
          Repo.delete_all(Ecto.Query.from(t in S3Transfer, where: t.id in ^ids))
        end, :s3_deletes, state)
      end)

    emit_flush_metrics(:s3_deletes, duration_ms, batch_size)
    state
  end

  defp take_operations(state, scope, max_batch_size) do
    {key_values_batch, key_values_rest} = maybe_take_map_batch(state.key_values, scope, :key_values, max_batch_size)
    {cas_accesses_batch, cas_accesses_rest} =
      maybe_take_map_batch(state.cas_accesses, scope, :cas_artifacts, max_batch_size)

    {cas_deletes_batch, cas_deletes_rest} = maybe_take_set_batch(state.cas_deletes, scope, :cas_artifacts, max_batch_size)
    {s3_inserts_batch, s3_inserts_rest} = maybe_take_map_batch(state.s3_inserts, scope, :s3_transfers, max_batch_size)
    {s3_deletes_batch, s3_deletes_rest} = maybe_take_set_batch(state.s3_deletes, scope, :s3_transfers, max_batch_size)

    operations =
      []
      |> add_operation(:key_values, key_values_batch)
      |> add_operation(:cas_accesses, cas_accesses_batch)
      |> add_operation(:cas_deletes, cas_deletes_batch)
      |> add_operation(:s3_inserts, s3_inserts_batch)
      |> add_operation(:s3_deletes, s3_deletes_batch)

    {
      %{
        state
        | key_values: key_values_rest,
          cas_accesses: cas_accesses_rest,
          cas_deletes: cas_deletes_rest,
          s3_inserts: s3_inserts_rest,
          s3_deletes: s3_deletes_rest
      },
      operations
    }
  end

  defp maybe_take_map_batch(queue, :all, _group, max_batch_size), do: take_map_batch(queue, max_batch_size)

  defp maybe_take_map_batch(queue, scope, group, max_batch_size) do
    if scope == group do
      take_map_batch(queue, max_batch_size)
    else
      {%{}, queue}
    end
  end

  defp maybe_take_set_batch(queue, :all, _group, max_batch_size), do: take_set_batch(queue, max_batch_size)

  defp maybe_take_set_batch(queue, scope, group, max_batch_size) do
    if scope == group do
      take_set_batch(queue, max_batch_size)
    else
      {[], queue}
    end
  end

  defp take_map_batch(queue, max_batch_size) do
    if map_size(queue) <= max_batch_size do
      {queue, %{}}
    else
      {batch_list, rest_list} = Enum.split(queue, max_batch_size)
      {Map.new(batch_list), Map.new(rest_list)}
    end
  end

  defp take_set_batch(queue, max_batch_size) do
    items = MapSet.to_list(queue)
    {batch_list, rest_list} = Enum.split(items, max_batch_size)
    {batch_list, MapSet.new(rest_list)}
  end

  defp add_operation(operations, _operation, empty) when empty == %{} or empty == [], do: operations
  defp add_operation(operations, operation, entries), do: operations ++ [{operation, entries}]

  defp queue_remaining?(state, scope) do
    stats = build_queue_stats(state)

    case scope do
      :all -> stats.total > 0
      :key_values -> stats.key_values > 0
      :cas_artifacts -> stats.cas_artifacts > 0
      :s3_transfers -> stats.s3_transfers > 0
    end
  end

  defp build_queue_stats(state) do
    key_values = map_size(state.key_values)
    cas_artifacts = map_size(state.cas_accesses) + MapSet.size(state.cas_deletes)
    s3_transfers = map_size(state.s3_inserts) + MapSet.size(state.s3_deletes)

    %{
      key_values: key_values,
      cas_artifacts: cas_artifacts,
      s3_transfers: s3_transfers,
      total: key_values + cas_artifacts + s3_transfers
    }
  end

  defp ensure_flush_timer(state) do
    if state.timer_ref == nil and build_queue_stats(state).total > 0 do
      ref = Process.send_after(self(), :flush, state.flush_interval_ms)
      %{state | timer_ref: ref}
    else
      state
    end
  end

  defp cancel_flush_timer(state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    %{state | timer_ref: nil}
  end

  defp maybe_request_flush(state) do
    if should_flush_now?(state) do
      send(self(), :flush)
    end

    state
  end

  defp should_flush_now?(state) do
    max_batch_size = state.max_batch_size

    map_size(state.key_values) >= max_batch_size or
      map_size(state.cas_accesses) >= max_batch_size or
      MapSet.size(state.cas_deletes) >= max_batch_size or
      map_size(state.s3_inserts) >= max_batch_size or
      MapSet.size(state.s3_deletes) >= max_batch_size
  end

  defp with_retry(fun, operation, state) do
    do_with_retry(fun, operation, 0, state)
  end

  defp do_with_retry(fun, operation, attempt, state) do
    fun.()
  rescue
    error ->
      if busy_error?(error) and attempt < state.retry_max_attempts do
        :telemetry.execute(
          [:cache, :sqlite_writer, :retry],
          %{count: 1},
          %{operation: operation, attempt: attempt + 1}
        )

        Process.sleep(backoff_ms(state, attempt))
        do_with_retry(fun, operation, attempt + 1, state)
      else
        Logger.warning("SQLite writer #{operation} failed: #{Exception.message(error)}")
        :ok
      end
  end

  defp backoff_ms(state, attempt) do
    base = state.retry_base_delay_ms
    max_delay = state.retry_max_delay_ms
    delay = trunc(base * :math.pow(2, attempt))
    min(delay, max_delay)
  end

  defp busy_error?(%Exqlite.Error{} = error) do
    error.message
    |> to_string()
    |> String.downcase()
    |> String.contains?("busy")
  end

  defp busy_error?(%DBConnection.ConnectionError{} = error) do
    error.message
    |> to_string()
    |> String.downcase()
    |> String.contains?("busy")
  end

  defp busy_error?(_error), do: false

  defp emit_flush_metrics(operation, duration_microseconds, batch_size) do
    :telemetry.execute(
      [:cache, :sqlite_writer, :flush],
      %{duration_ms: duration_microseconds / 1000, batch_size: batch_size},
      %{operation: operation}
    )
  end

  defp config_value(key, default) do
    :cache
    |> Application.get_env(:sqlite_writer, [])
    |> Keyword.get(key, default)
  end

  defp flush_timeout_ms do
    config_value(:flush_timeout_ms, @default_flush_timeout_ms)
  end
end
