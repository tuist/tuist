defmodule TuistWeb.RunnerControllerAuth do
  @moduledoc """
  Shared authentication for the internal endpoints the
  runners-controller calls (`pods/stopped`, job metrics ingestion).

  The controller presents its in-cluster ServiceAccount token as a
  `Bearer` token; we validate it via the Kubernetes TokenReview API
  and gate on the runners-controller SA specifically. Any in-cluster
  workload with a default-audience SA token would pass TokenReview,
  so without the principal check any pod could post on these
  endpoints by guessing the payload.
  """
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient

  @doc """
  Returns `:ok` when the request carries the runners-controller's SA
  bearer token, otherwise `{:error, reason}` where reason is one of
  `:missing_bearer`, `:unauthenticated`, `:not_service_account`,
  `{:wrong_principal, principal}`, or `:not_in_cluster`.
  """
  def authenticate(conn) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, principal} <- K8sClient.create_controller_token_review(token) do
      ensure_controller_principal(principal)
    end
  end

  defp ensure_controller_principal(%{namespace: ns, name: name} = principal) do
    if ns == Environment.runners_controller_namespace() and
         name == Environment.runners_controller_sa_name() do
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
