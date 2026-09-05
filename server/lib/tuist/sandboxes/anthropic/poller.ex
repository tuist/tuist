defmodule Tuist.Sandboxes.Anthropic.Poller do
  @moduledoc """
  One long-polling loop per enabled agent environment.

  Every iteration blocks on the work queue for up to 999ms. A session
  item is acknowledged right away (the queue's unacknowledged lease is a
  few seconds, shorter than a VM resume) and handed to
  `Tuist.Sandboxes.Router.dispatch/2` on a supervised task so the loop
  keeps polling. Anything that is not a session is force-stopped. Errors
  back the loop off exponentially up to 30s. The environment row is
  re-read every 30s so a rotated key or a disabled environment takes
  effect without a restart.
  """
  use GenServer, restart: :transient

  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Anthropic.Client
  alias Tuist.Sandboxes.Router

  require Logger

  @registry Tuist.Sandboxes.Anthropic.PollerRegistry
  @task_supervisor Tuist.Sandboxes.Anthropic.TaskSupervisor
  @block_ms 999
  @idle_delay_ms 250
  @min_backoff_ms 1_000
  @max_backoff_ms 30_000
  @refresh_interval to_timeout(second: 30)

  def start_link(opts) do
    agent_environment_id = Keyword.fetch!(opts, :agent_environment_id)
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, via(agent_environment_id)))
  end

  def via(agent_environment_id), do: {:via, Registry, {@registry, agent_environment_id}}

  def whereis(agent_environment_id) do
    case Registry.lookup(@registry, agent_environment_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  def running_agent_environment_ids do
    Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def worker_id, do: "tuist-#{node()}"

  @impl GenServer
  def init(opts) do
    agent_environment_id = Keyword.fetch!(opts, :agent_environment_id)

    case Sandboxes.get_agent_environment_by_id(agent_environment_id) do
      {:ok, %AgentEnvironment{enabled: true} = agent_environment} ->
        Logger.info("sandboxes: work poller started",
          agent_environment_id: agent_environment.id,
          anthropic_environment_id: agent_environment.anthropic_environment_id
        )

        Process.send_after(self(), :refresh, Keyword.get(opts, :refresh_interval, @refresh_interval))

        state = %{
          agent_environment: agent_environment,
          worker_id: Keyword.get(opts, :worker_id, worker_id()),
          backoff_ms: @min_backoff_ms,
          idle_delay_ms: Keyword.get(opts, :idle_delay_ms, @idle_delay_ms),
          refresh_interval: Keyword.get(opts, :refresh_interval, @refresh_interval)
        }

        {:ok, state, {:continue, :poll}}

      _ ->
        :ignore
    end
  end

  @impl GenServer
  def handle_continue(:poll, state), do: {:noreply, poll(state)}

  @impl GenServer
  def handle_info(:poll, state), do: {:noreply, poll(state)}

  def handle_info(:refresh, state) do
    case Sandboxes.get_agent_environment_by_id(state.agent_environment.id) do
      {:ok, %AgentEnvironment{enabled: true} = agent_environment} ->
        Process.send_after(self(), :refresh, state.refresh_interval)
        {:noreply, %{state | agent_environment: agent_environment}}

      _ ->
        Logger.info("sandboxes: work poller stopping, environment removed or disabled",
          agent_environment_id: state.agent_environment.id
        )

        {:stop, :normal, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp poll(%{agent_environment: agent_environment} = state) do
    case Client.poll(
           agent_environment.anthropic_environment_id,
           agent_environment.environment_key,
           state.worker_id,
           @block_ms
         ) do
      {:ok, :none} ->
        Process.send_after(self(), :poll, state.idle_delay_ms)
        %{state | backoff_ms: @min_backoff_ms}

      {:ok, item} ->
        handle_item(item, agent_environment)
        send(self(), :poll)
        %{state | backoff_ms: @min_backoff_ms}

      {:error, reason} ->
        Logger.warning("sandboxes: work queue poll failed",
          agent_environment_id: agent_environment.id,
          anthropic_environment_id: agent_environment.anthropic_environment_id,
          reason: inspect(reason),
          backoff_ms: state.backoff_ms
        )

        Process.send_after(self(), :poll, state.backoff_ms)
        %{state | backoff_ms: min(state.backoff_ms * 2, @max_backoff_ms)}
    end
  end

  defp handle_item(%{"id" => work_id, "data" => %{"type" => "session"}} = item, agent_environment) do
    case Client.ack(agent_environment.anthropic_environment_id, agent_environment.environment_key, work_id) do
      {:ok, _acknowledged} ->
        {:ok, _pid} = Task.Supervisor.start_child(@task_supervisor, fn -> Router.dispatch(agent_environment, item) end)
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: failed to acknowledge work item",
          agent_environment_id: agent_environment.id,
          work_id: work_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp handle_item(%{"id" => work_id} = item, agent_environment) do
    Logger.warning("sandboxes: stopping unsupported work item",
      agent_environment_id: agent_environment.id,
      work_id: work_id,
      data_type: get_in(item, ["data", "type"])
    )

    case Client.stop(agent_environment.anthropic_environment_id, agent_environment.environment_key, work_id, true) do
      {:ok, _stopped} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: failed to stop unsupported work item",
          agent_environment_id: agent_environment.id,
          work_id: work_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp handle_item(item, agent_environment) do
    Logger.warning("sandboxes: ignoring malformed work item",
      agent_environment_id: agent_environment.id,
      work_item: inspect(Map.delete(item, "secret"))
    )

    :ok
  end
end
