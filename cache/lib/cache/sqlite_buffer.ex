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

  def enqueue(server, event) do
    GenServer.call(server, {:enqueue, event})
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

    {:ok,
     %{
       buffer_module: buffer_module,
       buffer_state: buffer_module.init_state(),
       timer_ref: nil,
       flush_interval_ms: config_value(buffer_module, :flush_interval_ms, @default_flush_interval_ms),
       flush_timeout_ms: config_value(buffer_module, :flush_timeout_ms, @default_flush_timeout_ms),
       max_batch_size: config_value(buffer_module, :max_batch_size, @default_max_batch_size)
     }}
  end

  @impl true
  def handle_call({:enqueue, event}, _from, state) do
    buffer_state = state.buffer_module.handle_event(state.buffer_state, event)
    state = %{state | buffer_state: buffer_state}
    state = ensure_flush_timer(state)
    state = maybe_request_flush(state)
    {:reply, :ok, state}
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
    {:reply, :ok, %{state | buffer_state: state.buffer_module.init_state()}}
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
    {batches, buffer_state} =
      state.buffer_module.flush_batches(state.buffer_state, state.max_batch_size)

    state = %{state | buffer_state: buffer_state}
    state = Enum.reduce(batches, state, &execute_operation/2)

    if mode == :drain and not state.buffer_module.queue_empty?(state.buffer_state) do
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
    if state.timer_ref == nil and not state.buffer_module.queue_empty?(state.buffer_state) do
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
    stats = build_queue_stats(state)

    if should_flush_now?(stats, state.max_batch_size) do
      buffer_name = state.buffer_module.buffer_name()
      Logger.notice("#{buffer_name} buffer full, flushing to SQLite")
      send(self(), :flush)
    end

    state
  end

  defp build_queue_stats(state) do
    state.buffer_module.queue_stats(state.buffer_state)
  end

  defp should_flush_now?(stats, max_batch_size) do
    stats.total >= max_batch_size
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

  @doc false
  def take_map_batch(queue, max_batch_size) do
    {batch_list, rest_list} = Enum.split(queue, max_batch_size)
    {Map.new(batch_list), Map.new(rest_list)}
  end

  @doc false
  def take_set_batch(queue, max_batch_size) do
    items = MapSet.to_list(queue)
    {batch_list, rest_list} = Enum.split(items, max_batch_size)
    {batch_list, MapSet.new(rest_list)}
  end
end
