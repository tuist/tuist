defmodule Tuist.Sandboxes.Anthropic.Manager do
  @moduledoc """
  Keeps one `Tuist.Sandboxes.Anthropic.Poller` running per enabled agent
  environment. Reconciles on start and every 30s: environments without a
  poller get one, pollers whose environment was deleted or disabled are
  stopped. Pollers also stop themselves on their own refresh, so this is
  the slow path that catches rows changed on another node.
  """
  use GenServer

  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Anthropic.Poller

  require Logger

  @poller_supervisor Tuist.Sandboxes.Anthropic.PollerSupervisor
  @interval to_timeout(second: 30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def reconcile(server \\ __MODULE__), do: GenServer.call(server, :reconcile)

  @impl GenServer
  def init(opts) do
    send(self(), :reconcile)
    {:ok, %{interval: Keyword.get(opts, :interval, @interval)}}
  end

  @impl GenServer
  def handle_info(:reconcile, state) do
    do_reconcile()
    Process.send_after(self(), :reconcile, state.interval)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def handle_call(:reconcile, _from, state) do
    do_reconcile()
    {:reply, :ok, state}
  end

  defp do_reconcile do
    enabled = MapSet.new(Sandboxes.list_enabled_agent_environments(), & &1.id)
    running = MapSet.new(Poller.running_agent_environment_ids())

    enabled |> MapSet.difference(running) |> Enum.each(&start_poller/1)
    running |> MapSet.difference(enabled) |> Enum.each(&stop_poller/1)
  rescue
    error ->
      Logger.error("sandboxes: poller reconciliation failed", reason: Exception.message(error))
  end

  defp start_poller(agent_environment_id) do
    case DynamicSupervisor.start_child(@poller_supervisor, {Poller, agent_environment_id: agent_environment_id}) do
      {:ok, _pid} ->
        :ok

      :ignore ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error("sandboxes: failed to start work poller",
          agent_environment_id: agent_environment_id,
          reason: inspect(reason)
        )
    end
  end

  defp stop_poller(agent_environment_id) do
    case Poller.whereis(agent_environment_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(@poller_supervisor, pid)
    end
  end
end
