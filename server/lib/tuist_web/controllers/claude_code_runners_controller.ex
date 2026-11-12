defmodule TuistWeb.ClaudeCodeRunnersController do
  @moduledoc """
  Receives the spawn requests of Claude Code orchestrator workloads. The
  caller is identified by its projected ServiceAccount token, which names the
  agent environment (`Tuist.Sandboxes.ClaudeCodeRuntime`); nothing in the body
  can pick another environment. Answers map to the orchestrator hook's exit
  codes: 202/204 submitted, 429/503 retry, 400/403/422 block the session.
  """
  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Repo
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.ClaudeCodeRunners
  alias Tuist.Sandboxes.ClaudeCodeRuntime

  def spawn(conn, params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{namespace: namespace, name: name}} <- Client.create_claude_code_provider_token_review(token),
         true <- namespace == Environment.claude_code_provider_config().namespace,
         {:ok, agent_environment_id} <- ClaudeCodeRuntime.agent_environment_id(name),
         %AgentEnvironment{kind: :claude_code} = agent_environment <- Repo.get(AgentEnvironment, agent_environment_id) do
      case order(params) do
        {:ok, order} -> respond(conn, ClaudeCodeRunners.spawn(agent_environment, order))
        :error -> send_resp(conn, :bad_request, "Invalid spawn request")
      end
    else
      _ -> send_resp(conn, :unauthorized, "Invalid provider identity")
    end
  end

  defp order(%{"order_id" => order_id, "session_id" => session_id, "work_order" => work_order})
       when is_binary(order_id) and is_binary(session_id) and is_binary(work_order) do
    if Regex.match?(~r/\A[A-Za-z0-9._-]{1,255}\z/, order_id) and Regex.match?(~r/\A[A-Za-z0-9_-]{1,255}\z/, session_id) and
         Regex.match?(~r/\A[A-Za-z0-9_.-]{1,16384}\z/, work_order) do
      {:ok, %{order_id: order_id, session_id: session_id, work_order: work_order}}
    else
      :error
    end
  end

  defp order(_params), do: :error

  defp respond(conn, {:ok, :accepted}), do: send_resp(conn, :accepted, "")
  defp respond(conn, {:ok, :running}), do: send_resp(conn, :no_content, "")
  defp respond(conn, {:error, :disabled}), do: send_resp(conn, :forbidden, "Sandboxes are disabled")
  defp respond(conn, {:error, :no_capacity}), do: send_resp(conn, :too_many_requests, "No sandbox capacity")

  defp respond(conn, {:error, :sandbox_recovery_required}),
    do: send_resp(conn, :unprocessable_entity, "The session's macOS sandbox needs recovery")
end
