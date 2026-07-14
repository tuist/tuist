defmodule TuistWeb.RunnerInteractiveShellAgentController do
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.InteractiveSession
  alias Tuist.Runners.InteractiveSessions
  alias TuistWeb.RunnerShellAgentWebSock

  require Logger

  @kubernetes_name_pattern ~r/^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/

  def show(conn, _params) do
    case authenticated_pod_name(conn) do
      {:ok, pod_name} ->
        case InteractiveSessions.current_shell_for_pod(pod_name) do
          %InteractiveSession{} = session ->
            json(conn, %{
              session_id: session.id,
              workflow_job_id: session.workflow_job_id,
              websocket_url: websocket_url("/api/internal/runners/interactive/shell/#{session.id}/tunnel")
            })

          nil ->
            log_shell_discovery_miss(conn, pod_name)
            send_resp(conn, :no_content, "")
        end

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

      {:error, :pod_identity_mismatch} ->
        Logger.warning("runners: shell tunnel discovery pod identity mismatch")
        conn |> put_status(:unauthorized) |> json(%{error: "pod identity mismatch"})

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
         true <- namespace == Environment.runners_namespace(),
         {:ok, pod_name} <- verified_pod_name(conn, namespace, service_account_name) do
      {:ok, pod_name}
    else
      false -> {:error, :wrong_namespace}
      error -> error
    end
  end

  defp verified_pod_name(conn, namespace, service_account_name) do
    case header(conn, "x-tuist-runner-pod-name") do
      reported when is_binary(reported) and reported != "" and reported != service_account_name ->
        verify_reported_pod_name(namespace, service_account_name, reported)

      _ ->
        {:ok, service_account_name}
    end
  end

  defp verify_reported_pod_name(namespace, service_account_name, reported_pod_name) do
    with true <- Regex.match?(@kubernetes_name_pattern, reported_pod_name),
         {:ok, %{"spec" => %{"serviceAccountName" => ^service_account_name}}} <-
           K8sClient.get_pod(namespace, reported_pod_name) do
      {:ok, reported_pod_name}
    else
      false ->
        {:error, :pod_identity_mismatch}

      {:ok, _pod} ->
        {:error, :pod_identity_mismatch}

      {:error, :not_found} ->
        {:error, :pod_identity_mismatch}

      error ->
        error
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end

  defp log_shell_discovery_miss(conn, pod_name) do
    context = InteractiveSessions.shell_discovery_miss_context(pod_name)

    if context.open_sessions != [] do
      Logger.info("runners: shell discovery had no matching open session",
        pod: pod_name,
        reported_pod: header(conn, "x-tuist-runner-pod-name"),
        reported_pool: header(conn, "x-tuist-runner-pool"),
        binding: inspect(context.binding),
        open_sessions: inspect(context.open_sessions)
      )
    end
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp websocket_url(path) do
    uri = URI.parse(Environment.app_url(path: path, route_type: :app))
    scheme = if uri.scheme == "https", do: "wss", else: "ws"

    URI.to_string(%{uri | scheme: scheme})
  end
end
