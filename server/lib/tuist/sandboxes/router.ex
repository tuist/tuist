defmodule Tuist.Sandboxes.Router do
  @moduledoc """
  Routes an acknowledged Anthropic work item to the sandbox of its
  session: finds or creates the sandbox, resumes it when paused, records
  the residency and starts `sbx-worker` inside the VM with the session's
  credentials. Any failure releases the work item with a forced stop so
  Anthropic re-queues it on the session's next event.
  """

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Anthropic.Client
  alias Tuist.Sandboxes.Sandbox

  require Logger

  def dispatch(%AgentEnvironment{} = agent_environment, %{"id" => work_id, "data" => %{"id" => session_id}} = item)
      when is_binary(work_id) and is_binary(session_id) do
    with {:ok, sandbox} <- find_or_create_sandbox(agent_environment, session_id),
         {:ok, sandbox} <- Sandboxes.ensure_running(sandbox),
         {:ok, sandbox} <- Sandboxes.begin_residency(sandbox, work_id),
         {:ok, _data} <- start_worker(sandbox, worker_env(agent_environment, item, session_id)) do
      Logger.info("sandboxes: worker started",
        sandbox_id: sandbox.id,
        node: sandbox.node_name,
        agent_environment_id: agent_environment.id,
        session_id: session_id,
        work_id: work_id
      )

      :ok
    else
      {:error, reason} ->
        Logger.error("sandboxes: failed to route work item",
          agent_environment_id: agent_environment.id,
          session_id: session_id,
          work_id: work_id,
          reason: inspect(reason)
        )

        release(agent_environment, work_id)
        {:error, reason}
    end
  end

  def dispatch(%AgentEnvironment{} = agent_environment, %{"id" => work_id}) when is_binary(work_id) do
    Logger.error("sandboxes: work item has no session", agent_environment_id: agent_environment.id, work_id: work_id)
    release(agent_environment, work_id)
    {:error, :malformed_work_item}
  end

  defp find_or_create_sandbox(agent_environment, session_id) do
    case Sandboxes.get_sandbox_for_session(agent_environment.id, session_id) do
      %Sandbox{state: state} = sandbox when state in [:running, :paused, :creating] ->
        {:ok, sandbox}

      # A sandbox that died or was deleted from under us cannot be
      # resumed; drop what is left of it and start the session afresh.
      %Sandbox{} = sandbox ->
        with {:ok, _deleted} <- Sandboxes.delete(sandbox) do
          create_sandbox(agent_environment, session_id)
        end

      nil ->
        create_sandbox(agent_environment, session_id)
    end
  end

  defp create_sandbox(agent_environment, session_id) do
    with {:ok, account} <- Accounts.get_account_by_id(agent_environment.account_id) do
      Sandboxes.create_sandbox(account, %{
        agent_environment_id: agent_environment.id,
        anthropic_session_id: session_id,
        template: agent_environment.template,
        vcpus: agent_environment.vcpus,
        memory_mb: agent_environment.memory_mb,
        workspace_gb: agent_environment.workspace_gb
      })
    end
  end

  defp start_worker(sandbox, env) do
    case Sandboxes.start_worker(sandbox, env) do
      {:ok, _data} = ok ->
        ok

      {:error, reason} ->
        _ = Sandboxes.end_residency(sandbox)
        {:error, reason}
    end
  end

  defp release(agent_environment, work_id) do
    case Client.stop(agent_environment.anthropic_environment_id, agent_environment.environment_key, work_id, true) do
      {:ok, _stopped} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: failed to release work item",
          agent_environment_id: agent_environment.id,
          work_id: work_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp worker_env(agent_environment, item, session_id) do
    env = %{
      "ANTHROPIC_SESSION_ID" => session_id,
      "ANTHROPIC_WORK_ID" => item["id"],
      "ANTHROPIC_ENVIRONMENT_ID" => agent_environment.anthropic_environment_id,
      "ANTHROPIC_ENVIRONMENT_KEY" => agent_environment.environment_key,
      "ANTHROPIC_WORK_SECRET" => item["secret"] || "",
      "SBX_MAX_IDLE" => "#{agent_environment.max_idle_seconds}s"
    }

    case Environment.anthropic_api_url_override() do
      nil -> env
      base_url -> Map.put(env, "ANTHROPIC_BASE_URL", base_url)
    end
  end
end
