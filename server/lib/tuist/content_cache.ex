defmodule Tuist.ContentCache do
  @moduledoc false

  use GenServer

  @default_max_concurrency 4
  @default_load_timeout to_timeout(minute: 1)

  defmodule LoadError do
    @moduledoc false
    defexception [:message]
  end

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)
    %{id: name, start: {__MODULE__, :start_link, [opts]}}
  end

  def get(name, key, loader) when is_atom(name) and is_function(loader, 0) do
    if pid = Process.whereis(name) do
      pid
      |> GenServer.call({:get, key, loader}, :infinity)
      |> unwrap()
    else
      loader.()
    end
  end

  def reload(name) when is_atom(name) do
    if pid = Process.whereis(name) do
      GenServer.call(pid, :reload)
    end

    :ok
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    load_timeout = Keyword.get(opts, :load_timeout, @default_load_timeout)

    true = is_integer(max_concurrency) and max_concurrency > 0
    true = is_integer(load_timeout) and load_timeout > 0

    {:ok,
     %{
       generation: 0,
       load_timeout: load_timeout,
       loads: %{},
       max_concurrency: max_concurrency,
       queue: :queue.new(),
       running: 0,
       values: %{}
     }}
  end

  @impl true
  def handle_call({:get, key, loader}, from, state) do
    case Map.fetch(state.values, key) do
      {:ok, value} ->
        {:reply, {:ok, value}, state}

      :error ->
        state = enqueue_load(state, key, loader, from)
        {:noreply, start_available_loads(state)}
    end
  end

  def handle_call(:reload, _from, state) do
    state =
      state
      |> restart_pending_loads()
      |> start_available_loads()

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:content_cache_loaded, key, generation, id, worker, result}, state) do
    case Map.get(state.loads, key) do
      %{generation: ^generation, id: ^id, worker: ^worker} = load ->
        cancel_load_monitoring(load)
        reply_waiters(load.waiters, result)

        values =
          case result do
            {:ok, value} -> Map.put(state.values, key, value)
            _ -> state.values
          end

        state = %{state | loads: Map.delete(state.loads, key), running: state.running - 1, values: values}
        {:noreply, start_available_loads(state)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:content_cache_timeout, key, generation, id}, state) do
    case Map.get(state.loads, key) do
      %{generation: ^generation, id: ^id} = load ->
        stop_worker(load)
        reply_waiters(load.waiters, {:error, :timeout})

        running = if load.worker, do: state.running - 1, else: state.running
        state = %{state | loads: Map.delete(state.loads, key), running: running}
        {:noreply, start_available_loads(state)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _worker, reason}, state) do
    case Enum.find(state.loads, fn {_key, load} -> load.monitor == monitor end) do
      {key, load} ->
        cancel_timeout(load)
        reply_waiters(load.waiters, {:error, {:exit, reason}})

        state = %{state | loads: Map.delete(state.loads, key), running: state.running - 1}
        {:noreply, start_available_loads(state)}

      nil ->
        {:noreply, state}
    end
  end

  # Worker monitors report failures; links only ensure workers stop with the cache.
  def handle_info({:EXIT, _worker, _reason}, state) do
    {:noreply, state}
  end

  defp enqueue_load(state, key, loader, from) do
    case Map.get(state.loads, key) do
      nil ->
        id = make_ref()

        timeout =
          Process.send_after(self(), {:content_cache_timeout, key, state.generation, id}, state.load_timeout)

        load = %{
          generation: state.generation,
          id: id,
          loader: loader,
          monitor: nil,
          timeout: timeout,
          waiters: [from],
          worker: nil
        }

        %{state | loads: Map.put(state.loads, key, load), queue: :queue.in(key, state.queue)}

      load ->
        %{state | loads: Map.put(state.loads, key, %{load | waiters: [from | load.waiters]})}
    end
  end

  defp start_available_loads(%{running: running, max_concurrency: max_concurrency} = state)
       when running >= max_concurrency do
    state
  end

  defp start_available_loads(state) do
    case :queue.out(state.queue) do
      {{:value, key}, queue} ->
        state = %{state | queue: queue}

        case Map.get(state.loads, key) do
          %{worker: nil} = load ->
            parent = self()

            {worker, monitor} =
              :erlang.spawn_opt(
                fn ->
                  result = run_loader(load.loader)
                  send(parent, {:content_cache_loaded, key, load.generation, load.id, self(), result})
                end,
                [:link, :monitor]
              )

            load = %{load | monitor: monitor, worker: worker}
            state = %{state | loads: Map.put(state.loads, key, load), running: state.running + 1}
            start_available_loads(state)

          _ ->
            start_available_loads(state)
        end

      {:empty, _queue} ->
        state
    end
  end

  defp run_loader(loader) do
    {:ok, loader.()}
  rescue
    error -> {:error, {:exception, error, __STACKTRACE__}}
  catch
    kind, reason -> {:error, {kind, reason, __STACKTRACE__}}
  end

  defp restart_pending_loads(state) do
    Enum.each(state.loads, fn {_key, load} ->
      cancel_load_monitoring(load)

      if load.worker do
        Process.exit(load.worker, :kill)
      end
    end)

    generation = state.generation + 1

    {loads, queue} =
      Enum.reduce(state.loads, {%{}, :queue.new()}, fn {key, load}, {loads, queue} ->
        id = make_ref()
        timeout = Process.send_after(self(), {:content_cache_timeout, key, generation, id}, state.load_timeout)

        load = %{load | generation: generation, id: id, monitor: nil, timeout: timeout, worker: nil}
        {Map.put(loads, key, load), :queue.in(key, queue)}
      end)

    %{state | generation: generation, loads: loads, queue: queue, running: 0, values: %{}}
  end

  defp stop_worker(load) do
    if load.monitor do
      Process.demonitor(load.monitor, [:flush])
    end

    if load.worker do
      Process.exit(load.worker, :kill)
    end
  end

  defp cancel_load_monitoring(load) do
    cancel_timeout(load)

    if load.monitor do
      Process.demonitor(load.monitor, [:flush])
    end
  end

  defp cancel_timeout(load) do
    if load.timeout do
      Process.cancel_timer(load.timeout)
    end
  end

  defp reply_waiters(waiters, result) do
    Enum.each(waiters, &GenServer.reply(&1, result))
  end

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, {:exception, error, stack}}), do: reraise(error, stack)
  defp unwrap({:error, :timeout}), do: raise(LoadError, "Content cache load timed out")
  defp unwrap({:error, {:exit, reason}}), do: raise(LoadError, "Content cache loader exited: #{inspect(reason)}")
  defp unwrap({:error, {kind, reason, stack}}), do: raise(LoadError, load_error_message(kind, reason, stack))

  defp load_error_message(kind, reason, stack) do
    "Content cache load failed with #{kind}: #{Exception.format_banner(kind, reason, stack)}"
  end
end
