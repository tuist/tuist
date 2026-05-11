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

  `Tuist.Runners.PoolConfig` reads pools from `RunnerPool` CRs in
  the runners namespace — the chart renders the CRs from
  `runnerPools` in values, so the helm values are the operator-
  facing surface and there's exactly one source of truth for
  `name` / `owner` / `labels` / `runnerGroupID` / `allowedRepos`.
  """

  alias Tuist.GitHub.App, as: GitHubApp
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.PoolConfig

  require Logger

  @pool_label "tuist.dev/runner-pool"
  @claim_annotation "tuist.dev/claimed-by-pod"
  @max_claim_attempts 3

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
  def dispatch_for_sa(namespace, sa_name) when is_binary(namespace) and is_binary(sa_name) do
    with {:ok, sa} <- K8sClient.get_service_account(namespace, sa_name),
         {:ok, pool_name} <- pool_label(sa),
         {:ok, pool} <- find_pool(pool_name) do
      case pool.role do
        :shared_warm -> dispatch_shared_warm(namespace, sa_name, pool)
        _ -> dispatch_customer(pool, sa_name)
      end
    end
  end

  defp dispatch_customer(pool, sa_name) do
    with {:ok, jit, runner_name} <- mint_jit(pool, sa_name) do
      Logger.info("runners: dispatched jit",
        pool: pool.name,
        sa: sa_name,
        runner: runner_name
      )

      {:ok, %{jit: jit, pool: pool, runner_name: runner_name}}
    end
  end

  # SharedWarm path: the calling Pod is a warm runner waiting for
  # work. List Burst RunnerAssignments, find one that's unclaimed
  # and ready to bind, atomically claim it via Update+resourceVersion,
  # then mint a JIT for the Burst's customer pool. Retries on
  # 409-conflict (another warm Pod won the race) up to a small cap;
  # past that we tell the caller "no work yet" and the warm Pod
  # keeps polling.
  defp dispatch_shared_warm(namespace, sa_name, _warm_pool) do
    case fetch_burst_candidates(namespace) do
      {:ok, []} ->
        {:error, :no_work_yet}

      {:ok, candidates} ->
        try_claim(namespace, sa_name, candidates, @max_claim_attempts)

      {:error, reason} ->
        Logger.warning("runners: shared-warm list_runner_assignments failed",
          reason: inspect(reason)
        )

        {:error, :no_work_yet}
    end
  end

  defp fetch_burst_candidates(namespace) do
    case K8sClient.list_runner_assignments(namespace) do
      {:ok, items} ->
        {:ok,
         items
         |> Enum.filter(&unclaimed_burst?/1)
         # Oldest first — fairness, and minimizes user-perceived
         # queue latency.
         |> Enum.sort_by(&Map.get(&1["metadata"], "creationTimestamp", ""))}

      err ->
        err
    end
  end

  defp unclaimed_burst?(%{"spec" => %{"trigger" => "Burst"}, "metadata" => meta}) do
    annotations = Map.get(meta, "annotations", %{}) || %{}
    deletion_ts = Map.get(meta, "deletionTimestamp")
    Map.get(annotations, @claim_annotation) in [nil, ""] and is_nil(deletion_ts)
  end

  defp unclaimed_burst?(_), do: false

  defp try_claim(_namespace, _sa_name, [], _attempts), do: {:error, :no_work_yet}
  defp try_claim(_namespace, _sa_name, _candidates, 0), do: {:error, :no_work_yet}

  defp try_claim(namespace, sa_name, [candidate | rest], attempts) do
    case claim(namespace, sa_name, candidate) do
      {:ok, pool_name} ->
        case find_pool(pool_name) do
          {:ok, customer_pool} ->
            dispatch_customer(customer_pool, sa_name)

          {:error, :unknown_pool} ->
            # Burst was claimed but its poolRef target is gone.
            # Don't release the claim (the apiserver/CR cleanup
            # will reap on terminal phase); skip to next candidate.
            try_claim(namespace, sa_name, rest, attempts - 1)
        end

      {:error, :conflict} ->
        # Another warm Pod claimed this Burst. Skip and try the next.
        try_claim(namespace, sa_name, rest, attempts - 1)

      {:error, :not_found} ->
        # Burst was deleted in flight (controller GC race).
        try_claim(namespace, sa_name, rest, attempts - 1)

      {:error, reason} ->
        Logger.warning("runners: shared-warm claim failed",
          reason: inspect(reason)
        )

        try_claim(namespace, sa_name, rest, attempts - 1)
    end
  end

  defp claim(namespace, sa_name, candidate) do
    name = candidate["metadata"]["name"]
    pool_ref = get_in(candidate, ["spec", "poolRef", "name"])

    annotations =
      Map.get(candidate["metadata"], "annotations", %{}) || %{}

    updated = put_in(candidate, ["metadata", "annotations"], Map.put(annotations, @claim_annotation, sa_name))

    case K8sClient.update_runner_assignment(namespace, name, updated) do
      {:ok, _} ->
        Logger.info("runners: shared-warm claimed burst",
          burst: name,
          claimer: sa_name,
          pool: pool_ref
        )

        {:ok, pool_ref}

      err ->
        err
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
