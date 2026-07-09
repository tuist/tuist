defmodule TuistWeb.RunnerInteractiveShellAgentController do
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.InteractiveSession
  alias Tuist.Runners.InteractiveSessions
  alias TuistWeb.RunnerShellAgentWebSock

  require Logger

  def show(conn, _params) do
    with {:ok, pod_name} <- authenticated_pod_name(conn),
         %InteractiveSession{} = session <- InteractiveSessions.current_shell_for_pod(pod_name) do
      json(conn, %{
        session_id: session.id,
        workflow_job_id: session.workflow_job_id,
        websocket_url: websocket_url("/api/internal/runners/interactive/shell/#{session.id}/tunnel")
      })
    else
      nil ->
        send_resp(conn, :no_content, "")

      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})

      {:error, :unauthenticated} ->
        Logger.warning("runners: tokenreview rejected token on shell tunnel discovery")
        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})

      {:error, :not_service_account} ->
        Logger.warning("runners: tokenreview principal is not an SA on shell tunnel discovery")
        conn |> put_status(:unauthorized) |> json(%{error: "not a service account"})

      {:error, :wrong_namespace} ->
        conn |> put_status(:unauthorized) |> json(%{error: "wrong namespace"})

      {:error, :not_in_cluster} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})

      {:error, reason} ->
        Logger.error("runners: shell tunnel discovery failed", reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> json(%{error: "shell tunnel discovery failed"})
    end
  end

  def connect(conn, %{"session_id" => session_id}) do
    with {session_id, ""} <- Integer.parse(session_id),
         {:ok, pod_name} <- authenticated_pod_name(conn),
         {:ok, session} <- InteractiveSessions.validate_shell_pod(session_id, pod_name) do
      conn
      |> WebSockAdapter.upgrade(RunnerShellAgentWebSock, %{session: session}, timeout: to_timeout(minute: 65))
      |> halt()
    else
      _ ->
        conn
        |> send_resp(:not_found, "")
        |> halt()
    end
  end

  defp authenticated_pod_name(conn) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, %{namespace: namespace, name: service_account_name}} <- K8sClient.create_token_review(token),
         true <- namespace == Environment.runners_namespace() do
      {:ok, service_account_name}
    else
      false -> {:error, :wrong_namespace}
      error -> error
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end

  defp websocket_url(path) do
    uri = URI.parse(Environment.app_url(path: path, route_type: :app))
    scheme = if uri.scheme == "https", do: "wss", else: "ws"

    URI.to_string(%{uri | scheme: scheme})
  end
end
