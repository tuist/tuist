defmodule TuistWeb.RunnersController do
  @moduledoc """
  Authenticated dispatch endpoint runner Pods poll for their JIT
  runner config.

  Authentication: the Pod presents its projected ServiceAccount
  token as a `Bearer` token. The endpoint validates the token via
  the Kubernetes TokenReview API, recovers the SA's namespace +
  name, then asks `Tuist.Runners.dispatch_for_sa/2` to claim a
  pending Burst and mint a JIT.

  Trust chain: the runners-controller is the only writer of SAs
  in the runners namespace and stamps each SA with the fleet's
  `tuist.dev/runner-pool` label at create time. The K8s API
  server signs the projected token. So "the bearer of this token
  = a Pod minted by our controller for this fleet" without any
  server-side state.
  """

  use TuistWeb, :controller

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners

  require Logger

  def dispatch(conn, _params) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, %{namespace: ns, name: sa_name}} <- K8sClient.create_token_review(token),
         {:ok,
          %{
            jit: jit,
            account: account,
            workflow_job_id: workflow_job_id,
            fleet_on_cluster_network: on_cluster_network
          }} <-
           Runners.dispatch_for_sa(ns, sa_name) do
      json(conn, dispatch_response(jit, account, workflow_job_id, on_cluster_network))
    else
      {:error, :no_work_yet} ->
        send_resp(conn, :no_content, "")

      {:error, :drain} ->
        # 410 Gone: the polling Pod's image no longer matches its
        # RunnerPool's spec.image. dispatch-poll.sh on the Pod side
        # treats this as a clean-exit signal — exits 0, the EXIT
        # trap halts the VM, tart-kubelet transitions the Pod to
        # Succeeded, and the runner-pool reconciler replaces it
        # with one on the current image.
        conn |> put_status(:gone) |> json(%{error: "drain", reason: "image stale"})

      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})

      {:error, :unauthenticated} ->
        Logger.warning("runners: tokenreview rejected token")
        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})

      {:error, :not_service_account} ->
        Logger.warning("runners: tokenreview principal is not an SA")
        conn |> put_status(:unauthorized) |> json(%{error: "not a service account"})

      {:error, :not_found} ->
        conn |> put_status(:unauthorized) |> json(%{error: "service account gone"})

      {:error, :no_pool_label} ->
        Logger.warning("runners: SA missing pool label")
        conn |> put_status(:unauthorized) |> json(%{error: "no pool label on service account"})

      {:error, :unknown_account} ->
        conn |> put_status(:not_found) |> json(%{error: "account not configured"})

      {:error, :github_mint_failed} ->
        conn |> put_status(:bad_gateway) |> json(%{error: "jit mint failed"})

      {:error, :not_in_cluster} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})

      {:error, reason} ->
        Logger.error("runners: dispatch failed", reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> json(%{error: "dispatch failed"})
    end
  end

  @doc """
  Returns the raw scaling signals the runners-controller's
  autoscaler reconciler uses to compute the desired replica count
  for a given fleet:

      GET /api/internal/runners/desired_replicas?fleet=<name>
      → 200 { fleet, claimed, queued, p95_concurrent_last_hour }

  Authentication: same SA-token + TokenReview path as the dispatch
  endpoint. Anyone with a valid in-cluster SA token can read —
  the values are aggregate counts (not per-customer detail), and
  the controller's SA holds no pool label so we cannot gate by
  pool membership the way `dispatch` does.

  The controller composes the response into a desired replicas
  value using `minWarmPoolFloor` + `maxReplicas` from the
  per-pool `spec.autoscaling` block; keeping the policy knobs on
  the controller side means a chart-only tuning change doesn't
  need a server deploy.
  """
  def desired_replicas(conn, %{"fleet" => fleet}) when is_binary(fleet) and fleet != "" do
    with {:ok, token} <- bearer_token(conn),
         {:ok, _} <- K8sClient.create_controller_token_review(token) do
      signals = Runners.scaling_signals_for_fleet(fleet)
      json(conn, signals)
    else
      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})

      {:error, :unauthenticated} ->
        Logger.warning("runners: tokenreview rejected token on desired_replicas")
        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})

      {:error, :not_service_account} ->
        Logger.warning("runners: tokenreview principal is not an SA on desired_replicas")
        conn |> put_status(:unauthorized) |> json(%{error: "not a service account"})

      {:error, :not_in_cluster} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})

      {:error, reason} ->
        Logger.error("runners: desired_replicas failed", reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> json(%{error: "scaling signals failed"})
    end
  end

  def desired_replicas(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing fleet query param"})
  end

  # Hands the polling Pod its JIT config plus, when the account runs a
  # private runner-cache Kura node, the in-cluster URL the job should
  # use. The runner image exports it as `TUIST_CACHE_ENDPOINT` so cache
  # traffic stays on the cluster's internal network next to the runner
  # instead of going through the public Kura ingress. Absent
  # (non-runner-cache accounts), the Pod falls back to normal
  # server-side cache resolution.
  #
  # Only fleets on the cluster pod network get the URL: it's a
  # `*.svc.cluster.local` address, and clients treat
  # `TUIST_CACHE_ENDPOINT` as a hard override rather than a hint, so
  # handing it to a runtime that can't reach it (today: macOS Tart VMs
  # on vmnet) breaks caching instead of degrading it. The capability
  # lives in `Catalog.fleet_on_cluster_network?/1` — macOS is excluded
  # by its current runtime, not by policy.
  defp dispatch_response(jit, account, workflow_job_id, fleet_on_cluster_network) do
    base = %{
      encoded_jit_config: jit,
      owner: account.name,
      workflow_job_id: workflow_job_id
    }

    with true <- fleet_on_cluster_network,
         url when is_binary(url) and url != "" <- Tuist.Kura.runner_cache_endpoint_url(account) do
      Map.put(base, :cache_endpoint_url, url)
    else
      _ -> base
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
