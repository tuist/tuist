defmodule Cache.SQLiteBuffer do
  @moduledoc """
  Generic SQLite buffer GenServer shared by per-table buffers.
  """

  use GenServer

  require Logger

  @default_flush_interval_ms 200
  @default_flush_timeout_ms 30_000
  @default_max_batch_size 1000
  @default_retry_max_attempts 5
  @default_retry_base_delay_ms 50
  @default_retry_max_delay_ms 2000
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
       flush_interval_ms:
         config_value(buffer_module, :flush_interval_ms, @default_flush_interval_ms),
       flush_timeout_ms:
         config_value(buffer_module, :flush_timeout_ms, @default_flush_timeout_ms),
       max_batch_size: config_value(buffer_module, :max_batch_size, @default_max_batch_size),
       retry_max_attempts:
         config_value(buffer_module, :retry_max_attempts, @default_retry_max_attempts),
       retry_base_delay_ms:
         config_value(buffer_module, :retry_base_delay_ms, @default_retry_base_delay_ms),
       retry_max_delay_ms:
         config_value(buffer_module, :retry_max_delay_ms, @default_retry_max_delay_ms)
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

    {duration_ms, _} =
      :timer.tc(fn ->
        with_retry(
          fn -> state.buffer_module.write_batch(operation, entries) end,
          operation,
          buffer_name,
          state
        )
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
      send(self(), :flush)
    end

    state
  end

  defp build_queue_stats(state) do
    state.buffer_module.queue_stats(state.buffer_state) |> ensure_total()
  end

  defp ensure_total(stats) do
    if Map.has_key?(stats, :total) do
      stats
    else
      total =
        stats
        |> Enum.reject(fn {key, _value} -> key == :total end)
        |> Enum.reduce(0, fn {_key, value}, acc -> acc + value end)

      Map.put(stats, :total, total)
    end
  end

  defp should_flush_now?(stats, max_batch_size) do
    group_counts = Map.delete(stats, :total)

    if map_size(group_counts) == 0 do
      Map.get(stats, :total, 0) >= max_batch_size
    else
      Enum.any?(group_counts, fn {_key, value} -> value >= max_batch_size end)
    end
  end

  defp with_retry(fun, operation, buffer_name, state) do
    do_with_retry(fun, operation, buffer_name, 0, state)
  end

  defp do_with_retry(fun, operation, buffer_name, attempt, state) do
    fun.()
  rescue
    error ->
      if busy_error?(error) and attempt < state.retry_max_attempts do
        :telemetry.execute(
          [:cache, :sqlite_writer, :retry],
          %{count: 1},
          %{operation: operation, attempt: attempt + 1, buffer: buffer_name}
        )

        Process.sleep(backoff_ms(state, attempt))
        do_with_retry(fun, operation, buffer_name, attempt + 1, state)
      else
        Logger.warning(
          "SQLite buffer #{buffer_name} #{operation} failed: #{Exception.message(error)}"
        )

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

  defp emit_flush_metrics(buffer_name, operation, duration_microseconds, batch_size) do
    :telemetry.execute(
      [:cache, :sqlite_writer, :flush],
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
end
