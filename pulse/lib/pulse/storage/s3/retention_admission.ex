defmodule Pulse.Storage.S3.RetentionAdmission do
  @moduledoc "Node-wide retention DELETE admission: four monitored I/O slots and a bounded interval budget."
  use Pulse.Runtime.GenServer

  alias Pulse.ObjectStore
  alias Pulse.Runtime.GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(_opts), do: {:ok, %{slots: %{}, epoch: nil, used: 0}}

  def delete(config, key) do
    interval = Map.get(config, :retention_interval_ms, 30_000)
    epoch = div(System.monotonic_time(:millisecond), interval)
    limit = Map.get(config, :retention_delete_limit, 512)

    case GenServer.call(__MODULE__, {:reserve, epoch, limit}) do
      {:ok, ref} ->
        try do
          result = ObjectStore.delete_bounded(config, key)
          if result == {:error, :retention_overloaded}, do: GenServer.cast(__MODULE__, {:refund, epoch})
          result
        after
          GenServer.cast(__MODULE__, {:release, ref})
        end

      error ->
        error
    end
  end

  @impl true
  def handle_call({:reserve, epoch, limit}, {pid, _}, state) do
    state = if state.epoch == epoch, do: state, else: %{state | epoch: epoch, used: 0}

    if map_size(state.slots) >= 4 or state.used >= min(512, limit) do
      {:reply, {:error, :retention_budget_exhausted}, state}
    else
      ref = Process.monitor(pid)
      {:reply, {:ok, ref}, %{state | used: state.used + 1, slots: Map.put(state.slots, ref, pid)}}
    end
  end

  @impl true
  def handle_cast({:refund, epoch}, state) do
    {:noreply, if(state.epoch == epoch, do: %{state | used: max(0, state.used - 1)}, else: state)}
  end

  def handle_cast({:release, ref}, state) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | slots: Map.delete(state.slots, ref)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state),
    do: {:noreply, %{state | slots: Map.delete(state.slots, ref)}}
end
