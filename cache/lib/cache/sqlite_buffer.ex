defmodule Cache.SQLiteBuffer do
  @moduledoc """
  Generic SQLite buffer GenServer shared by per-table buffers.
  """

  use GenServer

  require Logger

  @default_flush_interval_ms 200
  @default_flush_timeout_ms 30_000
  @default_max_batch_size 1000
  @default_shutdown_ms 30_000

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)
    shutdown_ms = config_value(name, :shutdown_ms, @default_shutdown_ms)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      shutdown: shutdown_ms
    }
  end

  def flush(server) do
    GenServer.call(server, :flush, flush_timeout_ms(server))
  end

  def queue_stats(server) do
    GenServer.call(server, :queue_stats)
  end

  @doc false
  def reset(server) do
    GenServer.call(server, :reset)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    buffer_module = Keyword.fetch!(opts, :buffer_module)
    name = Keyword.fetch!(opts, :name)

    table =
      :ets.new(name, [:set, :public, :named_table, {:write_concurrency, true}])

    state = %{
      buffer_module: buffer_module,
      table: table,
      timer_ref: nil,
      flush_interval_ms: config_value(buffer_module, :flush_interval_ms, @default_flush_interval_ms),
      flush_timeout_ms: config_value(buffer_module, :flush_timeout_ms, @default_flush_timeout_ms),
      max_batch_size: config_value(buffer_module, :max_batch_size, @default_max_batch_size)
    }

    {:ok, ensure_flush_timer(state)}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    state = cancel_flush_timer(state)
    state = flush_state(state, :drain)
    state = ensure_flush_timer(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:queue_stats, _from, state) do
    {:reply, build_queue_stats(state), state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    state = cancel_flush_timer(state)
    :ets.delete_all_objects(state.table)
    state = ensure_flush_timer(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:flush, state) do
    state = %{state | timer_ref: nil}
    state = flush_state(state, :batch)
    state = ensure_flush_timer(state)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    buffer_name = state.buffer_module.buffer_name()
    Logger.notice("Flushing #{buffer_name} buffer before shutdown...")
    _ = flush_state(state, :drain)
    :ok
  end

  defp flush_state(state, mode) do
    operations = state.buffer_module.flush_entries(state.table, state.max_batch_size)
    state = Enum.reduce(operations, state, &execute_operation/2)

    if mode == :drain and not state.buffer_module.queue_empty?(state.table) do
      flush_state(state, mode)
    else
      state
    end
  end

  defp execute_operation({operation, entries}, state) do
    batch_size = batch_size(entries)
    buffer_name = state.buffer_module.buffer_name()

    Logger.notice("Flushing #{batch_size} row(s) from #{buffer_name} (#{operation})")

    {duration_ms, _} =
      :timer.tc(fn ->
        state.buffer_module.write_batch(operation, entries)
      end)

    emit_flush_metrics(buffer_name, operation, duration_ms, batch_size)
    state
  end

  defp batch_size(entries) when is_map(entries), do: map_size(entries)
  defp batch_size(entries) when is_list(entries), do: length(entries)
  defp batch_size(_entries), do: 0

  defp ensure_flush_timer(state) do
    if state.timer_ref == nil do
      ref = Process.send_after(self(), :flush, state.flush_interval_ms)
      %{state | timer_ref: ref}
    else
      state
    end
  end

  defp cancel_flush_timer(state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref, info: false)

      receive do
        :flush -> :ok
      after
        0 -> :ok
      end
    end

    %{state | timer_ref: nil}
  end

  defp build_queue_stats(state) do
    state.buffer_module.queue_stats(state.table)
  end

  defp emit_flush_metrics(buffer_name, operation, duration_microseconds, batch_size) do
    :telemetry.execute(
      [:cache, :sqlite_buffer, :flush],
      %{duration_ms: duration_microseconds / 1000, batch_size: batch_size},
      %{operation: operation, buffer: buffer_name}
    )
  end

  defp config_value(buffer_module, key, default) do
    global =
      :cache
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(key, default)

    :cache
    |> Application.get_env(buffer_module, [])
    |> Keyword.get(key, global)
  end

  defp flush_timeout_ms(server) do
    config_value(server, :flush_timeout_ms, @default_flush_timeout_ms)
  end

  @doc """
  Returns the size of an ETS table, returning 0 if the table doesn't exist.
  """
  def table_size(table) do
    case :ets.info(table, :size) do
      :undefined -> 0
      size -> size
    end
  end
end
