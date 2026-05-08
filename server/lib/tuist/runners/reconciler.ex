defmodule Tuist.Runners.Reconciler do
  @moduledoc """
  Maintains the warm runner pool — a hybrid of customer-reserved
  pre-bound Pods and a cluster-wide shared burst pool.

  Two reconcile streams per tick:

    1. For every pool with `min_warm > 0`, count Pods labeled
       `tuist.dev/runner=true,tuist.dev/runner-pool=<name>` in
       the runners namespace. If `alive < min_warm`, mint a JIT
       config from GitHub for that pool's repo and create a Pod
       carrying the JIT in env. The Pod's polling VM fetches the
       JIT on its first dispatch request and registers with
       GitHub within seconds of boot.

    2. For the shared pool, count Pods labeled
       `tuist.dev/runner=true,!tuist.dev/runner-pool`. If
       `alive < shared_burst_target`, create a generic Pod with
       no JIT. It polls the dispatch endpoint (returning 204
       while idle) until a `workflow_job: queued` webhook binds
       it to a customer.

  Cron-paced (60 s) by `Tuist.Runners.Workers.ReconcilePoolsWorker`.
  Idempotent — running twice converges to the same end state;
  the cron is configured singleton.

  Doesn't delete Pods: warm runners exit on their own after one
  job (`./run.sh --jitconfig` is single-shot); shrinking the pool
  is a v2 concern when concurrency tiers become customer-tunable.
  """

  alias Tuist.Environment
  alias Tuist.GitHub.App, as: GitHubApp
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client
  alias Tuist.Repo
  alias Tuist.Runners
  alias Tuist.Runners.PodSpec
  alias Tuist.Runners.PoolConfig

  require Logger

  # Postgres advisory-lock id used to serialize reconcile across
  # BEAM nodes. Arbitrary 63-bit constant; just needs to be
  # stable + unique across the codebase. Decimal form so a
  # `pg_locks` audit reads cleanly.
  @reconcile_lock_id 4_223_915_876_001

  @doc """
  Runs one reconcile pass. Always returns `:ok` — errors are
  logged but not surfaced (the next event/tick retries).

  Cluster-wide single-owner via a Postgres transaction-scoped
  advisory lock (`pg_try_advisory_xact_lock`). Every BEAM node
  runs its own watcher and may attempt reconcile concurrently,
  but only the node that wins the lock for that transaction
  does the list/create work; the rest skip. The lock auto-
  releases when the transaction commits / rolls back, so a
  crashing reconciler doesn't strand the lock. Without this
  guard each replica would compute the same gap independently
  and create duplicate Pods (over-registering JIT runners).
  """
  def reconcile do
    if PoolConfig.total_warm_target() == 0 do
      :ok
    else
      Repo.transaction(fn ->
        case Repo.query!("SELECT pg_try_advisory_xact_lock($1)", [@reconcile_lock_id]) do
          %{rows: [[true]]} ->
            reconcile_pre_bound()
            reconcile_shared()
            :ok

          _ ->
            Logger.debug("runners: reconcile skipped — another replica holds the lock")
            :skipped
        end
      end)

      :ok
    end
  end

  defp reconcile_pre_bound do
    PoolConfig.pools()
    |> Enum.filter(fn p -> p.min_warm > 0 end)
    |> Enum.each(fn pool ->
      case Client.list_pods(PodSpec.namespace(), PodSpec.pre_bound_selector(pool.name)) do
        {:ok, pods} ->
          alive = Enum.count(pods, &PodSpec.alive?/1)
          gap = max(0, pool.min_warm - alive)

          Logger.info("runners: pre-bound reconcile",
            pool: pool.name,
            target: pool.min_warm,
            observed: alive,
            gap: gap
          )

          Enum.each(1..gap//1, fn _ -> create_pre_bound_pod(pool) end)

        {:error, :not_in_cluster} ->
          Logger.debug("runners: skipping pre-bound reconcile — not running in-cluster")

        {:error, reason} ->
          Logger.warning("runners: pre-bound list_pods failed",
            pool: pool.name,
            reason: inspect(reason)
          )
      end
    end)
  end

  defp reconcile_shared do
    target = PoolConfig.shared_burst_target()

    if target == 0 do
      :ok
    else
      case Client.list_pods(PodSpec.namespace(), PodSpec.shared_selector()) do
        {:ok, pods} ->
          alive = Enum.count(pods, &PodSpec.alive?/1)
          gap = max(0, target - alive)

          Logger.info("runners: shared reconcile",
            target: target,
            observed: alive,
            gap: gap
          )

          Enum.each(1..gap//1, fn _ -> create_shared_pod() end)

        {:error, :not_in_cluster} ->
          Logger.debug("runners: skipping shared reconcile — not running in-cluster")

        {:error, reason} ->
          Logger.warning("runners: shared list_pods failed", reason: inspect(reason))
      end
    end
  end

  defp create_pre_bound_pod(pool) do
    image = Environment.runner_image()
    dispatch_url = Environment.runner_dispatch_url()
    fleet = Environment.runners_fleet_name()
    token = generate_dispatch_token()
    pod_name = PodSpec.generate_pool_name(pool.name)

    with {:ok, installation_id} <- GitHubApp.get_installation_id_for_repo(pool.owner, pool.repo),
         {:ok, %{encoded_jit_config: jit, runner_name: runner_name}} <-
           GitHubClient.generate_jit_config(installation_id, pool.owner, jit_attrs(pool, pod_name)),
         pod = PodSpec.build(pod_name, image, dispatch_url, token, fleet, pool: pool.name),
         {:ok, %{"metadata" => %{"uid" => uid, "name" => pod_name}}} <-
           Client.create_pod(PodSpec.namespace(), pod),
         {:ok, _} <-
           Runners.create_pre_bound_assignment(%{
             pod_uid: uid,
             pod_name: pod_name,
             pool_name: pool.name,
             jit_config: jit,
             dispatch_token_hash: Runners.hash_token(token),
             account_id: pool.account_id,
             owner: pool.owner,
             repo: pool.repo
           }) do
      Logger.info("runners: created pre-bound pod",
        pod_name: pod_name,
        pod_uid: uid,
        pool: pool.name,
        runner_name: runner_name,
        image: image,
        fleet: fleet
      )

      :ok
    else
      {:error, :not_installed} ->
        Logger.warning("runners: skipping pre-bound — Tuist GitHub App not installed on repo",
          pool: pool.name,
          repo: "#{pool.owner}/#{pool.repo}"
        )

        :ok

      {:error, %Ecto.Changeset{} = cs} ->
        # Persisted Pod but row insert failed — orphan that
        # needs manual cleanup. Loud log because we can't
        # auto-recover; manual `kubectl delete pod` then the
        # next reconcile tick rebuilds.
        Logger.error("runners: pre-bound assignment row failed; orphaned Pod will need manual cleanup",
          pool: pool.name,
          changeset_errors: inspect(cs.errors)
        )

        :ok

      {:error, reason} ->
        Logger.warning("runners: create_pre_bound_pod failed",
          pool: pool.name,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp create_shared_pod do
    image = Environment.runner_image()
    dispatch_url = Environment.runner_dispatch_url()
    fleet = Environment.runners_fleet_name()
    token = generate_dispatch_token()
    pod_name = PodSpec.generate_name()
    pod = PodSpec.build(pod_name, image, dispatch_url, token, fleet)

    with {:ok, %{"metadata" => %{"uid" => uid, "name" => pod_name}}} <-
           Client.create_pod(PodSpec.namespace(), pod),
         {:ok, _} <-
           Runners.create_idle_assignment(%{
             pod_uid: uid,
             pod_name: pod_name,
             dispatch_token_hash: Runners.hash_token(token)
           }) do
      Logger.info("runners: created shared pod",
        pod_name: pod_name,
        pod_uid: uid,
        image: image,
        fleet: fleet
      )

      :ok
    else
      {:error, %Ecto.Changeset{} = cs} ->
        Logger.error("runners: shared assignment row failed; orphaned Pod will need manual cleanup",
          changeset_errors: inspect(cs.errors)
        )

        :ok

      {:error, reason} ->
        Logger.warning("runners: create_shared_pod failed", reason: inspect(reason))
        :ok
    end
  end

  # GitHub's runner-name uniqueness is per repo. Embed the Pod's
  # name (already unique-per-Pod via the random suffix) so a
  # re-create can never collide with a still-pending registration.
  defp runner_jit_name(pool, pod_name) do
    "tuist-#{pool.name}-#{pod_name}"
  end

  defp jit_attrs(pool, pod_name) do
    base = %{name: runner_jit_name(pool, pod_name), labels: pool.labels}

    case Map.get(pool, :runner_group_id) do
      nil -> base
      id when is_integer(id) -> Map.put(base, :runner_group_id, id)
    end
  end

  defp generate_dispatch_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
