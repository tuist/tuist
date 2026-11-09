defmodule Tuist.Sandboxes.Workers.DispatchWorkItemWorker do
  @moduledoc """
  Holds an acknowledged Managed Agents work item that no node had room for
  and hands it to `Tuist.Sandboxes.Router.dispatch/2` once
  `Tuist.Sandboxes.Capacity.admissible?/2` lets it through, checking every
  few seconds. Snoozing does not use up attempts.

  The poller acknowledges such an item instead of leaving it queued because
  Anthropic's queue offers an unacknowledged item only three times, five
  seconds apart, and then stops: the item stays `queued`, cannot be
  acknowledged any more, and a new message on the session does not bring it
  back, so the turn hangs. An acknowledged item waits in `starting` for its
  worker. Past the deadline the item is force-stopped, which lets the
  session's next message queue it again.

  The work item's secret is stored Vault-encrypted in the job's arguments.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:work_id], states: [:available, :scheduled, :executing], period: :infinity]

  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Anthropic.Client
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Router

  require Logger

  @check_seconds 5
  @max_wait_ms to_timeout(minute: 30)

  @doc "The job holding `item` (a polled session work item, secret included) until a node has room."
  def new_for(%AgentEnvironment{id: agent_environment_id}, %{"id" => work_id, "secret" => secret} = item) do
    {:ok, ciphertext} = Tuist.Vault.encrypt(secret || "")

    new(%{
      agent_environment_id: agent_environment_id,
      work_id: work_id,
      item: Map.delete(item, "secret"),
      secret: Base.encode64(ciphertext),
      deadline_ms: System.system_time(:millisecond) + @max_wait_ms
    })
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"agent_environment_id" => agent_environment_id, "item" => item} = args}) do
    with {:ok, %AgentEnvironment{enabled: true} = agent_environment} <-
           Sandboxes.get_agent_environment_by_id(agent_environment_id),
         {:ok, ciphertext} <- Base.decode64(args["secret"]),
         {:ok, secret} <- Tuist.Vault.decrypt(ciphertext) do
      dispatch_or_wait(agent_environment, Map.put(item, "secret", secret), args["deadline_ms"])
    else
      _ -> :ok
    end
  end

  defp dispatch_or_wait(agent_environment, %{"id" => work_id, "data" => %{"id" => session_id}} = item, deadline_ms) do
    cond do
      Capacity.admissible?(Router.session_environment(agent_environment, item), session_id) ->
        _ = Router.dispatch(agent_environment, item)
        :ok

      System.system_time(:millisecond) < deadline_ms ->
        {:snooze, @check_seconds}

      true ->
        Logger.warning("sandboxes: no node had room for a work item before its deadline; releasing it",
          agent_environment_id: agent_environment.id,
          work_id: work_id,
          session_id: session_id
        )

        _ = Client.stop(agent_environment.anthropic_environment_id, agent_environment.environment_key, work_id, true)
        :ok
    end
  end
end
