defmodule Tuist.Sandboxes.ClaudeCodeRunners do
  @moduledoc """
  Starts the Claude Code runner of one cloud session in the session's sandbox.

  A `:claude_code` agent environment's orchestrator hands each spawn request
  (a session with no runner) to `spawn/2`. The answer comes before the VM boots,
  so the orchestrator's hook stays inside its timeout: a session whose sandbox
  already holds a residency has its runner on the way (`:running`); one that
  fits is `:accepted`, and its sandbox is created or resumed and `sbx-worker`
  started with the work order on a supervised task; one that does not fit is
  refused with `:no_capacity` and re-requested by the orchestrator after
  backoff. A work order the task fails to start is re-requested by Anthropic
  once the orchestrator's lease runs out.

  The session's sandbox runs the environment's platform. The runner exits
  after the session has been idle for the environment's `max_idle_seconds`,
  which ends the residency and pauses the sandbox; the session's next message
  resumes the same sandbox, checkout included.
  """
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Anthropic.Supervisor, as: AnthropicSupervisor
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Router
  alias Tuist.Sandboxes.Sandbox

  require Logger

  def spawn(%AgentEnvironment{kind: :claude_code} = agent_environment, %{session_id: session_id} = order) do
    agent_environment = Repo.preload(agent_environment, :account)

    if agent_environment.enabled and FeatureFlags.sandboxes_enabled?(agent_environment.account) do
      case Sandboxes.get_sandbox_for_session(agent_environment.id, session_id) do
        %Sandbox{residency_work_id: work_id} when is_binary(work_id) ->
          {:ok, :running}

        %Sandbox{platform: :darwin, state: :error} ->
          {:error, :sandbox_recovery_required}

        _sandbox ->
          admit(agent_environment, order)
      end
    else
      {:error, :disabled}
    end
  end

  defp admit(agent_environment, order) do
    if Capacity.admissible?(agent_environment, order.session_id) do
      {:ok, _pid} =
        Task.Supervisor.start_child(AnthropicSupervisor.task_supervisor(), fn ->
          start_runner(agent_environment, order)
        end)

      {:ok, :accepted}
    else
      {:error, :no_capacity}
    end
  end

  @doc false
  def start_runner(agent_environment, %{order_id: order_id, session_id: session_id, work_order: work_order}) do
    # A macOS guest accepts only [A-Za-z0-9_-]{1,255} as a work id, and an
    # order id may hold dots and be 255 characters long. A hash stays stable
    # across re-requests of the same order.
    work_id = "claude-code-" <> (:sha256 |> :crypto.hash(order_id) |> Base.encode16(case: :lower) |> binary_part(0, 32))

    # A re-request while an earlier one still boots the VM finds the lock taken.
    result =
      Sandboxes.with_sandbox_lock(
        "claude-code:#{agent_environment.id}:#{session_id}",
        fn ->
          with {:ok, sandbox, created?} <- Router.find_or_create_sandbox(agent_environment, session_id),
               {:ok, sandbox} <- Sandboxes.prepare_residency(sandbox, work_id, created: created?),
               {:ok, _data} <- Router.start_worker(sandbox, worker_env(agent_environment, sandbox, work_id, work_order)) do
            {:ok, sandbox}
          end
        end,
        wait: false
      )

    case result do
      {:ok, sandbox} ->
        Logger.info("sandboxes: claude code runner started",
          sandbox_id: sandbox.id,
          node: sandbox.node_name,
          agent_environment_id: agent_environment.id,
          session_id: session_id
        )

      {:error, reason} ->
        Logger.warning("sandboxes: claude code runner not started",
          agent_environment_id: agent_environment.id,
          session_id: session_id,
          reason: inspect(reason)
        )
    end

    result
  end

  # A macOS host refuses a worker without ANTHROPIC_WORK_ID: it records the id
  # as the sandbox's worker so a retried start cannot run a second one.
  defp worker_env(agent_environment, sandbox, work_id, work_order) do
    env = %{
      "ANTHROPIC_WORK_ID" => work_id,
      "SBX_CLAUDE_CODE_WORK_ORDER" => work_order,
      "SBX_CLAUDE_CODE_RELEASE_IDLE_MIN" => to_string(max(div(agent_environment.max_idle_seconds + 59, 60), 1))
    }

    if sandbox.platform == :darwin, do: Map.put(env, "SBX_WORKDIR", Sandboxes.workspace(sandbox)), else: env
  end
end
