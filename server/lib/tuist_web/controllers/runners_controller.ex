defmodule TuistWeb.RunnersController do
  @moduledoc """
  Authenticated dispatch endpoint the runner Pods poll for their
  JIT runner config.

  Authentication: the Pod presents its projected ServiceAccount
  token as a `Bearer` token in the `Authorization` header. The
  endpoint validates the token via the Kubernetes TokenReview API
  (so a leaked or forged token can't pass), recovers the SA's
  namespace + name from the validated principal, then asks
  `Tuist.Runners.dispatch_for_sa/2` to resolve the SA to a pool
  and mint a JIT runner config from GitHub. The Pod execs
  `./run.sh --jitconfig <jit>` once and halts.

  Trust chain: the runners-controller is the only writer of SAs
  in the runners namespace and stamps each SA with its pool
  label at create time. The K8s API server signs the projected
  token. Therefore "the bearer of this token = a Pod minted by
  our controller for pool X" without any server-side state.
  """

  use TuistWeb, :controller

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners

  require Logger

  def dispatch(conn, _params) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, %{namespace: ns, name: sa_name}} <- K8sClient.create_token_review(token),
         {:ok, %{jit: jit, pool: pool}} <- Runners.dispatch_for_sa(ns, sa_name) do
      json(conn, %{
        encoded_jit_config: jit,
        pool: pool.name,
        owner: pool.owner
      })
    else
      {:error, :no_work_yet} ->
        # SharedWarm Pod polled but no Burst is pending. Tell it to
        # keep polling — 204 No Content carries the "alive but
        # nothing to do" semantics without forcing the VM to
        # shut down.
        send_resp(conn, :no_content, "")

      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})

      {:error, :unauthenticated} ->
        Logger.warning("runners: tokenreview rejected token")
        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})

      {:error, :not_service_account} ->
        Logger.warning("runners: tokenreview principal is not an SA")
        conn |> put_status(:unauthorized) |> json(%{error: "not a service account"})

      {:error, :not_found} ->
        # SA was authenticated but is gone from the apiserver — race
        # between Pod startup and SA deletion (controller GCing a
        # terminal assignment). 401 is the safe default.
        conn |> put_status(:unauthorized) |> json(%{error: "service account gone"})

      {:error, :no_pool_label} ->
        Logger.warning("runners: SA missing pool label")
        conn |> put_status(:unauthorized) |> json(%{error: "no pool label on service account"})

      {:error, :unknown_pool} ->
        # SA labeled for a pool the server's PoolConfig doesn't know
        # about — likely an out-of-band CR or a pool deleted mid-flight.
        # 404 (not 401: the auth was valid).
        conn |> put_status(:not_found) |> json(%{error: "pool not configured"})

      {:error, :github_mint_failed} ->
        conn |> put_status(:bad_gateway) |> json(%{error: "jit mint failed"})

      {:error, :not_in_cluster} ->
        # Server isn't running in a cluster (local dev). Refuse rather
        # than 500 — the dispatch endpoint has no meaning without K8s.
        conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})

      {:error, reason} ->
        Logger.error("runners: dispatch failed", reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> json(%{error: "dispatch failed"})
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
