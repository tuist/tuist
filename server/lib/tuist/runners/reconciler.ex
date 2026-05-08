defmodule Tuist.Runners.Reconciler do
  @moduledoc """
  Maintains the per-customer pre-bound pool.

  For every pool with `min_warm > 0`, count Pods labeled
  `tuist.dev/runner=true,tuist.dev/runner-pool=<name>` in the
  runners namespace. If `alive < min_warm`, mint a JIT config
  from GitHub for that pool and create a Pod carrying the JIT in
  env. The Pod's polling VM fetches the JIT on its first
  dispatch poll and registers with GitHub seconds after boot.

  Bursts above `min_warm` are *not* reconciled here — they're
  served by the dispatch webhook handler creating an on-demand
  Pod for the queued workflow_job. This keeps the steady-state
  warm pool tightly bounded (no surge capacity sitting idle) at
  the cost of a one-time clone+boot+register tax (~30-90 s) on
  jobs above the customer's reserved slots. That's the same
  default-tier cold-start every other CI provider walks; we'll
  add a generic shared pre-warm pool back as a Phase 2+
  optimization if the cold-start tax starts mattering at scale.

  Triggered event-driven from `Tuist.Runners.Watcher` (Pod
  termination → reconcile) plus once at Watcher boot.
  Idempotent — running twice converges to the same end state.

  Doesn't delete Pods: warm runners exit on their own after one
  job (`./run.sh --jitconfig` is single-shot); the Watcher
  garbage-collects the terminal Pods after observing the phase
  transition.
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
    if PoolConfig.sum_min_warm() == 0 do
      :ok
    else
      {:ok, _} =
        Repo.transaction(fn ->
          case Repo.query!("SELECT pg_try_advisory_xact_lock($1)", [@reconcile_lock_id]) do
            %{rows: [[true]]} ->
              reconcile_pre_bound()
              :ok

            _ ->
              Logger.debug("runners: reconcile skipped — another replica holds the lock")
              :skipped
          end
        end)

      :ok
    end
  end

  @doc """
  Creates a fresh pre-bound Pod for a given pool. Used by both
  the reconciler (filling the steady-state min_warm gap) and the
  dispatch webhook (on-demand Pod for a queued workflow_job
  beyond `min_warm`). Same shape either way: a Pod with the JIT
  config minted at create time, the customer's labels, and the
  pool's runner group baked into the JIT registration.

  Returns `:ok` on success, `{:error, reason}` on failure. The
  caller logs.
  """
  def create_pre_bound_pod(pool) do
    image = Environment.runner_image()
    dispatch_url = Environment.runner_dispatch_url()
    fleet = Environment.runners_fleet_name()
    token = generate_dispatch_token()
    pod_name = PodSpec.generate_pool_name(pool.name)

    with {:ok, installation_id} <- GitHubApp.get_installation_id_for_org(pool.owner),
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
             owner: pool.owner
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
      {:error, :not_installed} = err ->
        Logger.warning("runners: skipping pre-bound — Tuist GitHub App not installed on org",
          pool: pool.name,
          owner: pool.owner
        )

        err

      {:error, %Ecto.Changeset{} = cs} = err ->
        # Persisted Pod but row insert failed — orphan that
        # needs manual cleanup. Loud log because we can't
        # auto-recover; manual `kubectl delete pod` then the
        # next reconcile tick rebuilds.
        Logger.error("runners: pre-bound assignment row failed; orphaned Pod will need manual cleanup",
          pool: pool.name,
          changeset_errors: inspect(cs.errors)
        )

        err

      {:error, reason} = err ->
        Logger.warning("runners: create_pre_bound_pod failed",
          pool: pool.name,
          reason: inspect(reason)
        )

        err
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
