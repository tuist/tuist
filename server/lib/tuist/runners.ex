defmodule Tuist.Runners do
  @moduledoc """
  Customer-facing GitHub Actions runners on Tuist's Mac mini fleet.

  Architecture:

    * **One CRD: `RunnerPool`.** Helm-rendered, one CR per image
      variant (v1 ships a single `default` pool; adding a second
      image is a new entry in `runnersFleet.pools`). Each pool's
      `spec.dispatchLabel` is the runner label customers put in
      `runs-on` to route to it; the webhook handler matches
      `workflow_job.labels` against every pool's `dispatchLabel`.
      `spec.minWarm` per pool sums to ≤ host count under the v1
      one-VM-per-host design choice.
    * **The Go controller's `RunnerPoolReconciler`** maintains
      each pool's Pods + per-Pod ServiceAccounts directly via
      owner refs — no `RunnerAssignment` CRD. Pod terminates →
      reconciler reaps the Pod + SA, then boots a replacement.
    * **`accounts.runner_max_concurrent`** is the only per-customer
      knob. 0 = runners disabled; N>0 = at most N concurrent
      across all pools the customer reaches.
    * **Postgres `runner_dispatch_queue`** is the burst queue.
      Rows are scoped to a fleet (= pool name), so a per-pool
      backlog never blocks another pool. The webhook enqueues;
      warm Pods polling the dispatch endpoint claim via
      `FOR UPDATE SKIP LOCKED`, then `UPDATE … SET claimed_at =
      now()` so the row survives a JIT-mint failure and
      `Tuist.Runners.StaleClaimsWorker` can recover from a
      mid-claim crash.

  `max_concurrent` enforcement is two-stage:

    1. **Coarse, outside the tx.** The dispatch endpoint LISTs
       Pods labeled `tuist.dev/runner-pool-owner=<account-name>`,
       counts per owner, and excludes accounts at cap from the
       claim's candidate set.
    2. **Fine, inside the tx.** After picking a candidate, the
       claim grabs `pg_advisory_xact_lock(account_id)` and adds
       in-flight (soft-claimed) queue rows for that account into
       the count. Closes the window between claim and Pod
       label-stamp where two polls could race past stage 1 with
       the same stale K8s snapshot.

  Capped customers' rows wait in the queue until their count
  drops; oldest-eligible-first keeps other customers unblocked.

  GitHub repo-scoping is currently delegated to the GitHub default
  runner group (id=1), which allows every repo in the org. A
  per-account `runner_group_id` is a follow-up once multi-tenant
  onboarding makes per-repo scoping necessary.
  """

  alias Tuist.Accounts
  alias Tuist.GitHub.App, as: GitHubApp
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.DispatchQueue

  require Logger

  @pool_label "tuist.dev/runner-pool"
  @owner_label "tuist.dev/runner-pool-owner"
  @account_label "tuist.dev/runner-account"

  @doc """
  Claims the oldest eligible queue entry for the SA's fleet and
  mints a JIT for the entry's account. Stamps the polling Pod
  with owner labels so subsequent `max_concurrent` counts include
  it.

  Returns `{:ok, %{jit, account}}` on success.

  Error cases the web layer translates to HTTP responses:
    * `{:error, :no_work_yet}` — queue empty (or all pending
      accounts at cap); warm Pod keeps polling.
    * `{:error, :not_found}` — SA gone (raced with GC).
    * `{:error, :no_pool_label}` — SA missing the fleet label.
    * `{:error, :unknown_account}` — claimed entry's account
      went away.
    * `{:error, :github_mint_failed}` — GitHub refused the JIT.
    * `{:error, :not_in_cluster}` — server not running in-cluster.
  """
  def dispatch_for_sa(namespace, sa_name) when is_binary(namespace) and is_binary(sa_name) do
    with {:ok, sa} <- K8sClient.get_service_account(namespace, sa_name),
         {:ok, fleet_name} <- pool_label(sa) do
      {ineligible, cap_lookup} = account_state_snapshot(namespace)

      case DispatchQueue.claim_oldest_eligible(fleet_name, ineligible, cap_lookup) do
        {:ok, %{id: id, account_id: account_id}} ->
          serve_claim(namespace, sa_name, fleet_name, id, account_id)

        {:error, :empty} ->
          {:error, :no_work_yet}

        {:error, :over_cap} ->
          # Per-account lock + in-flight re-check inside the claim
          # tx noticed the account just hit cap. Stay in warm
          # standby; next poll's K8s snapshot will reflect it.
          {:error, :no_work_yet}

        {:error, reason} ->
          Logger.warning("runners: claim_oldest_eligible failed", reason: inspect(reason))
          {:error, :no_work_yet}
      end
    end
  end

  defp serve_claim(namespace, sa_name, fleet_name, claim_id, account_id) do
    case Accounts.get_account_by_id(account_id) do
      {:ok, account} ->
        pod_name = pod_name_from_sa(sa_name)

        with {:ok, dispatch_label} <- Dispatch.dispatch_label_for_pool(fleet_name),
             :ok <- stamp_owner_labels(namespace, pod_name, account),
             {:ok, jit, runner_name} <- mint_jit(account, sa_name, dispatch_label),
             :ok <- DispatchQueue.finalize_claim(claim_id) do
          Logger.info("runners: dispatched",
            account: account.name,
            sa: sa_name,
            runner: runner_name,
            fleet: fleet_name
          )

          {:ok, %{jit: jit, account: account, runner_name: runner_name}}
        else
          {:error, :not_found} = err ->
            release_claim_safely(claim_id, :no_pool)
            err

          {:error, :no_dispatch_label} = err ->
            release_claim_safely(claim_id, :no_dispatch_label)
            err

          {:error, reason} = err ->
            release_claim_safely(claim_id, reason)
            err
        end

      {:error, :not_found} ->
        Logger.warning("runners: claimed entry has no account row", account_id: account_id)
        release_claim_safely(claim_id, :unknown_account)
        {:error, :unknown_account}
    end
  end

  defp release_claim_safely(claim_id, reason) do
    case DispatchQueue.release_claim(claim_id) do
      :ok ->
        :ok

      {:error, release_error} ->
        Logger.warning("runners: release_claim failed; stale-claim worker will recover",
          claim_id: claim_id,
          original_reason: inspect(reason),
          release_error: inspect(release_error)
        )

        :ok
    end
  end

  # Builds:
  #   * the set of account ids whose owners are currently at
  #     `runner_max_concurrent` by K8s Pod count alone (skip-set
  #     for the candidate query); and
  #   * a `cap_lookup` of `account_id => {cap, k8s_count}` for
  #     every account that has at least one Pod stamped against
  #     it (so the in-tx re-check inside `claim_oldest_eligible`
  #     can compute `k8s_count + inflight_count` without a second
  #     DB hop for the cap value).
  #
  # Returns `{[], %{}}` if the LIST fails so the queue keeps
  # draining; the in-tx per-account re-check + cap re-read
  # is the safety net.
  defp account_state_snapshot(namespace) do
    case K8sClient.list_pods(namespace, @owner_label) do
      {:ok, pods} -> snapshot_from_pods(pods)
      {:error, reason} -> log_list_failure_and_skip(reason)
    end
  end

  defp snapshot_from_pods(pods) do
    pods
    |> Enum.filter(&active_pod?/1)
    |> Enum.frequencies_by(&owner_from_pod/1)
    |> Map.delete(nil)
    |> Enum.reduce({[], %{}}, &fold_owner_count/2)
  end

  defp fold_owner_count({owner, count}, {ineligible, lookup}) do
    case Accounts.get_account_by_handle(owner) do
      %{id: id, runner_max_concurrent: cap} when is_integer(cap) and cap > 0 ->
        lookup = Map.put(lookup, id, {cap, count})
        ineligible = if count >= cap, do: [id | ineligible], else: ineligible
        {ineligible, lookup}

      _ ->
        {ineligible, lookup}
    end
  end

  defp log_list_failure_and_skip(reason) do
    Logger.warning("runners: list_pods failed; ineligibility check open",
      reason: inspect(reason)
    )

    {[], %{}}
  end

  defp active_pod?(%{"status" => %{"phase" => phase}, "metadata" => meta}) do
    deletion_ts = Map.get(meta, "deletionTimestamp")
    phase not in ["Succeeded", "Failed"] and is_nil(deletion_ts)
  end

  defp active_pod?(%{"metadata" => meta}) do
    is_nil(Map.get(meta, "deletionTimestamp"))
  end

  defp active_pod?(_), do: false

  defp owner_from_pod(%{"metadata" => %{"labels" => labels}}) when is_map(labels) do
    Map.get(labels, @owner_label)
  end

  defp owner_from_pod(_), do: nil

  defp stamp_owner_labels(namespace, pod_name, account) do
    patch = %{
      "metadata" => %{
        "labels" => %{
          @owner_label => account.name,
          @account_label => Integer.to_string(account.id)
        }
      }
    }

    case K8sClient.patch_pod(namespace, pod_name, patch) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("runners: pod label stamp failed; max_concurrent count may undercount",
          pod: pod_name,
          reason: inspect(reason)
        )

        # Continue — the runner still serves the job; counts are
        # eventually consistent.
        :ok
    end
  end

  defp mint_jit(account, sa_name, dispatch_label) do
    runner_name = "tuist-#{account.name}-#{sa_name}"

    with {:ok, installation_id} <- GitHubApp.get_installation_id_for_org(account.name),
         {:ok, %{encoded_jit_config: jit, runner_name: runner_name}} <-
           GitHubClient.generate_jit_config(installation_id, account.name, %{
             name: runner_name,
             labels: ["self-hosted", "macOS", "ARM64", dispatch_label]
           }) do
      {:ok, jit, runner_name}
    else
      {:error, :not_installed} ->
        Logger.warning("runners: GitHub App not installed on org", account: account.name)
        {:error, :github_mint_failed}

      {:error, reason} ->
        Logger.error("runners: GitHub jit mint failed",
          account: account.name,
          reason: inspect(reason)
        )

        {:error, :github_mint_failed}
    end
  end

  defp pool_label(%{"metadata" => %{"labels" => labels}}) when is_map(labels) do
    case Map.get(labels, @pool_label) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, :no_pool_label}
    end
  end

  defp pool_label(_), do: {:error, :no_pool_label}

  # The polling Pod's name. The controller's podtemplate stamps
  # Pods + SAs with the same name, so the SA name IS the Pod name.
  defp pod_name_from_sa(sa_name), do: sa_name
end
