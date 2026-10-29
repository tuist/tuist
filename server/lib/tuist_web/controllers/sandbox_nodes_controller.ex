defmodule TuistWeb.SandboxNodesController do
  @moduledoc """
  Internal endpoint the sandboxd DaemonSet dials to open its control
  WebSocket. Authenticates the projected ServiceAccount token with a
  TokenReview scoped to the `tuist-sandboxes` audience and requires the
  sandboxes namespace. The node name comes from `X-Tuist-Node-Name` and
  must be the node the token's pod is bound to, so a pod on one node
  cannot speak for another.
  """
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias TuistWeb.SandboxNodeWebSock

  require Logger

  @kubernetes_name_pattern ~r/^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$/
  @kubernetes_name_max_length 253
  # Nodes send a report every 30 seconds whatever else they are doing, so
  # a connection silent for four of them belongs to a node that is gone
  # (a power cut sends no FIN) and must stop being offered for placement.
  @connection_timeout to_timeout(second: 120)

  def connect(conn, _params) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, %{namespace: namespace, name: service_account} = principal} <-
           K8sClient.create_sandbox_node_token_review(token),
         :ok <- verify_namespace(namespace),
         {:ok, node_name} <- node_name(conn),
         :ok <- verify_bound_node(principal, node_name) do
      Logger.info("sandboxes: node connecting", node: node_name, service_account: service_account)

      conn
      |> WebSockAdapter.upgrade(SandboxNodeWebSock, %{node_name: node_name}, timeout: @connection_timeout)
      |> halt()
    else
      {:error, reason} -> error_response(conn, reason)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end

  defp verify_namespace(namespace) do
    if namespace == Environment.sandboxes_namespace(), do: :ok, else: {:error, :wrong_namespace}
  end

  defp verify_bound_node(%{node_name: node_name}, node_name) when is_binary(node_name), do: :ok
  defp verify_bound_node(_principal, _node_name), do: {:error, :node_mismatch}

  defp node_name(conn) do
    case get_req_header(conn, "x-tuist-node-name") do
      [name | _] when is_binary(name) and name != "" ->
        if String.length(name) <= @kubernetes_name_max_length and Regex.match?(@kubernetes_name_pattern, name) do
          {:ok, name}
        else
          {:error, :invalid_node_name}
        end

      _ ->
        {:error, :missing_node_name}
    end
  end

  defp error_response(conn, :missing_bearer) do
    conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})
  end

  defp error_response(conn, :unauthenticated) do
    Logger.warning("sandboxes: tokenreview rejected node token")
    conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})
  end

  defp error_response(conn, :not_service_account) do
    Logger.warning("sandboxes: tokenreview principal is not a service account")
    conn |> put_status(:unauthorized) |> json(%{error: "not a service account"})
  end

  defp error_response(conn, :node_mismatch) do
    Logger.warning("sandboxes: node name does not match the node the token is bound to")
    conn |> put_status(:unauthorized) |> json(%{error: "node name does not match the token"})
  end

  defp error_response(conn, :wrong_namespace) do
    conn |> put_status(:unauthorized) |> json(%{error: "wrong namespace"})
  end

  defp error_response(conn, :missing_node_name) do
    conn |> put_status(:bad_request) |> json(%{error: "missing node name"})
  end

  defp error_response(conn, :invalid_node_name) do
    conn |> put_status(:bad_request) |> json(%{error: "invalid node name"})
  end

  defp error_response(conn, :not_in_cluster) do
    conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})
  end

  defp error_response(conn, reason) do
    Logger.error("sandboxes: node connection failed", reason: inspect(reason))
    conn |> put_status(:internal_server_error) |> json(%{error: "node connection failed"})
  end
end
