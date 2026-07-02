defmodule TuistWeb.RunnerPodAuth do
  @moduledoc """
  Authenticates a runner Pod acting on its own behalf (machine-metrics
  ingestion). Unlike `TuistWeb.RunnerControllerAuth` (which gates on the
  runners-controller's SA), this gates on the Pod's *own* ServiceAccount.

  The runner presents the same per-pod token it uses for `dispatch` —
  audience-scoped to `tuist-runners-dispatch` and validated via
  TokenReview. The runners-controller mints each Pod and its SA together
  with the same name, so the SA name equals the Pod name. We require the
  token's principal to be the SA for the `pod_name` being written, in the
  runners namespace. That makes a Pod able to report only for itself, and
  a leaked token unusable to write another Pod's metrics.
  """
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient

  @doc """
  Returns `:ok` when the request carries a valid runner SA token whose
  principal is the SA named `pod_name` in the runners namespace,
  otherwise `{:error, reason}` where reason is one of `:missing_bearer`,
  `:unauthenticated`, `:not_service_account`, `{:wrong_principal,
  principal}`, or `:not_in_cluster`.
  """
  def authenticate(conn, pod_name) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, principal} <- K8sClient.create_token_review(token) do
      ensure_pod_principal(principal, pod_name)
    end
  end

  defp ensure_pod_principal(%{namespace: ns, name: name} = principal, pod_name) do
    if ns == Environment.runners_namespace() and name == pod_name do
      :ok
    else
      {:error, {:wrong_principal, principal}}
    end
  end

  defp bearer_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end
end
