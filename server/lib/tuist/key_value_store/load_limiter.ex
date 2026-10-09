defmodule Tuist.KeyValueStore.LoadLimiter do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  def child_spec(opts) do
    %{id: Keyword.fetch!(opts, :name), start: {__MODULE__, :start_link, [opts]}}
  end

  def run(name, key, loader, timeout \\ :infinity) do
    if pid = Process.whereis(name) do
      GenServer.call(pid, {:run, key, loader, [self() | Process.get(:"$callers", [])]}, timeout)
    else
      {:error, :unavailable}
    end
  catch
    :exit, {:timeout, _call} -> {:error, :timeout}
    :exit, reason -> {:error, {:exit, reason}}
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       loads: %{},
       queue: :queue.new(),
       running: 0,
       max_concurrency: Keyword.get(opts, :max_concurrency, 2),
       max_pending_loads: Keyword.get(opts, :max_pending_loads, 40),
       max_waiters: Keyword.get(opts, :max_waiters, 128),
       queue_timeout: Keyword.get(opts, :queue_timeout, to_timeout(second: 3)),
       load_timeout: Keyword.get(opts, :load_timeout, to_timeout(second: 10)),
       on_error: Keyword.get(opts, :on_error, fn _reason -> :ok end)
     }}
  end

  @impl true
  def handle_call({:run, key, loader, callers}, from, state) do
    case state.loads[key] do
      nil when map_size(state.loads) >= state.max_pending_loads ->
        {:reply, {:error, :overloaded}, state}

      nil ->
        id = make_ref()
        timer = Process.send_after(self(), {:queue_timeout, key, id}, state.queue_timeout)

        load = %{
          id: id,
          loader: loader,
          callers: callers,
          waiters: [from],
          timer: timer,
          worker: nil,
          monitor: nil,
          timed_out: false
        }

        state = %{state | loads: Map.put(state.loads, key, load), queue: :queue.in(key, state.queue)}
        {:noreply, start_available(state)}

      %{timed_out: true} ->
        {:reply, {:error, :overloaded}, state}

      %{waiters: waiters} when length(waiters) >= state.max_waiters ->
        {:reply, {:error, :overloaded}, state}

      load ->
        {:noreply, %{state | loads: Map.put(state.loads, key, %{load | waiters: [from | load.waiters]})}}
    end
  end

  @impl true
  def handle_info({:loaded, key, id, result}, state) do
    case state.loads[key] do
      %{id: ^id} = load ->
        Process.demonitor(load.monitor, [:flush])
        cancel_timer(load)
        reply(load.waiters, result)
        {:noreply, finish(state, key)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:queue_timeout, key, id}, state) do
    case state.loads[key] do
      %{id: ^id, worker: nil} = load ->
        reply(load.waiters, {:error, :overloaded})
        state = %{state | loads: Map.delete(state.loads, key), queue: :queue.delete(key, state.queue)}
        {:noreply, start_available(state)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:load_timeout, key, id}, state) do
    case state.loads[key] do
      %{id: ^id} = load ->
        reply(load.waiters, {:error, :timeout})
        # A killed caller need not cancel remote database work. Keep the slot
        # until completion, including the loader's eventual cache write.
        load = %{load | timed_out: true, waiters: [], timer: nil}
        {:noreply, %{state | loads: Map.put(state.loads, key, load)}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _worker, reason}, state) do
    case Enum.find(state.loads, fn {_key, load} -> load.monitor == monitor end) do
      {key, load} ->
        cancel_timer(load)
        reply(load.waiters, {:error, {:exit, reason}})
        {:noreply, finish(state, key)}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, _worker, _reason}, state), do: {:noreply, state}

  defp start_available(%{running: running, max_concurrency: limit} = state) when running >= limit, do: state

  defp start_available(state) do
    case :queue.out(state.queue) do
      {{:value, key}, queue} ->
        load = Map.fetch!(state.loads, key)
        cancel_timer(load)
        timer = Process.send_after(self(), {:load_timeout, key, load.id}, state.load_timeout)
        parent = self()
        on_error = state.on_error

        {worker, monitor} =
          :erlang.spawn_opt(
            fn ->
              Process.put(:"$callers", load.callers)
              send(parent, {:loaded, key, load.id, run_loader(load.loader, on_error)})
            end,
            [:link, :monitor]
          )

        load = %{load | worker: worker, monitor: monitor, timer: timer}
        start_available(%{state | loads: Map.put(state.loads, key, load), queue: queue, running: state.running + 1})

      {:empty, _queue} ->
        state
    end
  end

  defp run_loader(loader, on_error) do
    {:ok, loader.()}
  rescue
    exception ->
      reason = {:exception, exception, __STACKTRACE__}
      on_error.(reason)
      {:error, reason}
  catch
    kind, value ->
      reason = {kind, value, __STACKTRACE__}
      on_error.(reason)
      {:error, reason}
  end

  defp finish(state, key), do: start_available(%{state | loads: Map.delete(state.loads, key), running: state.running - 1})
  defp cancel_timer(%{timer: nil}), do: :ok
  defp cancel_timer(%{timer: timer}), do: Process.cancel_timer(timer)
  defp reply(waiters, result), do: Enum.each(waiters, &GenServer.reply(&1, result))
end
