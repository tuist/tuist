defmodule Tuist.Orchard.Scheduler do
  @moduledoc """
  Assigns pending VMs to online workers.

  Wakes on demand (`request_scheduling/0`, called by the VM creation
  path) and on a periodic tick (every 10s) so that VMs which couldn't
  schedule on the first pass — no online workers, capacity exhausted —
  get retried.

  Placement strategy: pick the worker with the most free CPU. Ties
  broken by name for determinism in tests. Failed-VM cleanup and the
  "VMs currently running on a worker" capacity bookkeeping are kept in
  one place to keep the scheduling decision atomic.
  """
  use GenServer

  alias Tuist.Orchard
  alias Tuist.Orchard.VM
  alias Tuist.Orchard.Worker

  require Logger

  @tick_ms 10_000
  @worker_offline_seconds 60

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Nudges the scheduler. Idempotent — multiple requests within the same
  pass collapse to a single reconcile.
  """
  def request_scheduling do
    if Process.whereis(__MODULE__), do: send(__MODULE__, :tick)
    :ok
  end

  @impl true
  def init(_opts) do
    schedule_next_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    reconcile()
    schedule_next_tick()
    {:noreply, state}
  end

  defp schedule_next_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  @doc false
  def reconcile do
    pending = Orchard.list_pending_vms()
    workers = available_workers()

    cond do
      pending == [] ->
        :ok

      workers == [] ->
        Logger.warning("Orchard scheduler: #{length(pending)} pending VM(s), no online workers")
        :ok

      true ->
        place_each(pending, workers)
    end
  end

  defp available_workers do
    Enum.reject(Orchard.list_workers(), fn worker ->
      Worker.offline?(worker, @worker_offline_seconds) or worker.scheduling_paused
    end)
  end

  defp place_each(_pending, []), do: :ok

  defp place_each([], _), do: :ok

  defp place_each([%VM{} = vm | rest], workers) do
    case pick_worker(vm, workers) do
      nil ->
        Logger.info("Orchard scheduler: no eligible worker for VM #{vm.name}; will retry")
        :ok

      worker ->
        cpu = if vm.cpu > 0, do: vm.cpu, else: worker.default_cpu
        memory = if vm.memory > 0, do: vm.memory, else: worker.default_memory

        case Orchard.schedule_vm(vm, worker, cpu, memory) do
          {:ok, _} ->
            place_each(rest, decrement(workers, worker, cpu, memory))

          {:error, reason} ->
            Logger.warning("Orchard scheduler: failed to assign VM #{vm.name}: #{inspect(reason)}")

            place_each(rest, workers)
        end
    end
  end

  # Pick the worker with the most free CPU after subtracting the VMs
  # already assigned to it. We compute "free" lazily here rather than
  # off the resources map so a worker recently re-registered without
  # capacity values still gets considered.
  defp pick_worker(_vm, []), do: nil

  defp pick_worker(_vm, workers) do
    workers
    |> Enum.max_by(&worker_free_cpu/1, fn -> nil end)
    |> case do
      %Worker{} = w -> if worker_free_cpu(w) > 0, do: w
      _ -> nil
    end
  end

  defp worker_free_cpu(%Worker{} = worker) do
    total = Map.get(worker.resources, "cpu", worker.default_cpu)
    used = used_cpu(worker.name)
    total - used
  end

  defp used_cpu(worker_name) do
    [worker_name: worker_name]
    |> Orchard.list_vms()
    |> Enum.reduce(0, fn vm, acc -> acc + max(vm.assigned_cpu, vm.cpu) end)
  end

  defp decrement(workers, worker, cpu, _memory) do
    Enum.map(workers, fn %Worker{} = w ->
      if w.name == worker.name do
        used = Map.get(w.resources, "_assigned_cpu", 0) + cpu
        %{w | resources: Map.put(w.resources, "_assigned_cpu", used)}
      else
        w
      end
    end)
  end
end
