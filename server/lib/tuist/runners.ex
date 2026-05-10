defmodule Tuist.Runners do
  @moduledoc """
  Customer-facing GitHub Actions runners on Tuist's Mac mini fleet.

  Architecture:

  - `tuist-runners-controller` (separate Go process running in
    the cluster) owns Pod + ServiceAccount lifecycle. It watches
    `RunnerPool` and `RunnerAssignment` CRDs and materializes
    one Pod + one per-Pod SA per assignment.
  - The controller's RunnerPool reconciler keeps `min_warm`
    pre-bound RunnerAssignment CRs alive per pool. The controller
    in turn creates one Pod + one SA per assignment; the SA's
    projected token is the dispatch-endpoint authentication
    anchor.
  - `Tuist.Runners.Dispatch.handle_webhook/2` is the burst path:
    when GitHub fires `workflow_job: queued` because the pool's
    pre-bound runners are saturated, the handler writes a Burst
    RunnerAssignment CR; the controller picks it up and
    materializes an on-demand Pod for that pool.
  - `dispatch_for_sa/2` is the JIT-mint path the dispatch
    endpoint calls after TokenReview-validating a Pod's projected
    SA token. The Tuist-boundary side owns the GitHub App + JIT
    plumbing; the controller's web boundary just orchestrates
    bearer extraction → TokenReview → this call → response.

  No `runner_assignments` table, no dispatch tokens in Postgres,
  no per-Pod state in the BEAM. The K8s API is the source of
  truth for which Pod/SA pair belongs to which pool; the SA-as-
  auth contract makes the dispatch endpoint stateless.

  See `Tuist.Runners.PoolConfig` for the pool table (hardcoded
  for v1; moves to the database in v2).
  """

  alias Tuist.GitHub.App, as: GitHubApp
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.PoolConfig

  require Logger

  @pool_label "tuist.dev/runner-pool"

  @doc """
  Resolves the SA at `namespace/sa_name` into a pool via its
  labels and mints a fresh JIT runner config from GitHub.
  Returns `{:ok, %{jit, pool}}` on success, or one of:
    * `{:error, :not_found}` — SA was authenticated but is gone
      from the apiserver (raced with controller GC)
    * `{:error, :no_pool_label}` — SA exists but is missing the
      pool label (out-of-band manual SA, mis-stamped controller)
    * `{:error, :unknown_pool}` — labeled for a pool the server
      doesn't have in PoolConfig
    * `{:error, :github_mint_failed}` — GitHub App refused the
      JIT mint (install gone, runner-group deleted, rate-limit)
    * `{:error, :not_in_cluster}` — server not running in-cluster
    * `{:error, _}` — transport / unexpected k8s status

  The web controller layer wraps this in HTTP-shaped responses.
  Bearer-extract + TokenReview live there; this function
  trusts its `namespace`/`sa_name` callers because they've
  already authenticated via TokenReview.
  """
  def dispatch_for_sa(namespace, sa_name)
      when is_binary(namespace) and is_binary(sa_name) do
    with {:ok, sa} <- K8sClient.get_service_account(namespace, sa_name),
         {:ok, pool_name} <- pool_label(sa),
         {:ok, pool} <- find_pool(pool_name),
         {:ok, jit, runner_name} <- mint_jit(pool, sa_name) do
      Logger.info("runners: dispatched jit",
        pool: pool.name,
        sa: sa_name,
        runner: runner_name
      )

      {:ok, %{jit: jit, pool: pool, runner_name: runner_name}}
    end
  end

  defp pool_label(%{"metadata" => %{"labels" => labels}}) when is_map(labels) do
    case Map.get(labels, @pool_label) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, :no_pool_label}
    end
  end

  defp pool_label(_), do: {:error, :no_pool_label}

  defp find_pool(name) do
    case PoolConfig.find_by_name(name) do
      nil -> {:error, :unknown_pool}
      pool -> {:ok, pool}
    end
  end

  defp mint_jit(pool, sa_name) do
    runner_name = "tuist-#{pool.name}-#{sa_name}"

    with {:ok, installation_id} <- GitHubApp.get_installation_id_for_org(pool.owner),
         attrs = jit_attrs(pool, runner_name),
         {:ok, %{encoded_jit_config: jit, runner_name: runner_name}} <-
           GitHubClient.generate_jit_config(installation_id, pool.owner, attrs) do
      {:ok, jit, runner_name}
    else
      {:error, :not_installed} ->
        Logger.warning("runners: GitHub App not installed on org",
          pool: pool.name,
          owner: pool.owner
        )

        {:error, :github_mint_failed}

      {:error, reason} ->
        Logger.error("runners: GitHub jit mint failed",
          pool: pool.name,
          reason: inspect(reason)
        )

        {:error, :github_mint_failed}
    end
  end

  defp jit_attrs(pool, runner_name) do
    base = %{name: runner_name, labels: pool.labels}

    case Map.get(pool, :runner_group_id) do
      nil -> base
      id when is_integer(id) -> Map.put(base, :runner_group_id, id)
    end
  end
end
