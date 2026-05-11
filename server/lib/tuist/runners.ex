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
      `spec.replicas` per pool sums to ≤ host count under the v1
      one-VM-per-host design choice.
    * **The Go controller's `RunnerPoolReconciler`** maintains
      each pool's Pods + per-Pod ServiceAccounts directly via
      owner refs — no `RunnerAssignment` CRD. Pod terminates →
      reconciler reaps the Pod + SA, then boots a replacement.
    * **`accounts.runner_max_concurrent`** is the only per-customer
      knob. 0 = runners disabled; N>0 = at most N concurrent
      across all pools the customer reaches.
    * **`runner_jobs` in ClickHouse** is the lifecycle table.
      One ReplacingMergeTree row per workflow_job; state
      transitions (`queued → claimed → running → completed`) are
      INSERTs advancing the version column. Customer-facing
      surfaces — what's queued, what's running, recent runs —
      read directly from this table. See `Tuist.Runners.Jobs`
      for the full contract.

  `max_concurrent` enforcement is two-stage:

    1. **Skip-set built from the snapshot.** Before claiming, the
       dispatch endpoint computes `counts_per_account/1` and
       compares against `accounts.runner_max_concurrent`,
       excluding accounts already at cap from the candidate
       query.
    2. **Verify-by-readback after insert.** The claim itself is
       an INSERT-then-verify pair against the RMT — concurrent
       claims for the same workflow_job both INSERT, but a
       deterministic tiebreaker on `(updated_at DESC, pod_name
       ASC)` means both pollers compute the same winner from any
       vantage point. The loser bails before any side effect
       (no mint, no Pod label, no runner registration).

  Capped customers' jobs wait in the `queued` state until their
  count drops; oldest-eligible-first keeps other customers
  unblocked.

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
  alias Tuist.Runners.Jobs

  require Logger

  @pool_label "tuist.dev/runner-pool"
  @owner_label "tuist.dev/runner-pool-owner"
  @account_label "tuist.dev/runner-account"

  @doc """
  Claims the next eligible queued workflow_job for the SA's fleet
  and mints a JIT for the workflow_job's account. Stamps the
  polling Pod with owner labels so it shows up in operational
  views; runtime cap accounting reads `runner_jobs` directly.

  Returns `{:ok, %{jit, account, runner_name}}` on success.

  Error cases the web layer translates to HTTP responses:
    * `{:error, :no_work_yet}` — queue empty, all accounts at
      cap, or we lost a claim race; warm Pod keeps polling.
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
      cap_lookup = build_cap_lookup(fleet_name)

      case Jobs.claim(fleet_name, sa_name, cap_lookup) do
        {:ok, job} ->
          serve_claim(namespace, sa_name, fleet_name, job)

        {:error, :empty} ->
          {:error, :no_work_yet}

        {:error, :lost_race} ->
          {:error, :no_work_yet}

        {:error, reason} ->
          Logger.warning("runners: claim failed", reason: inspect(reason))
          {:error, :no_work_yet}
      end
    end
  end

  defp serve_claim(namespace, sa_name, fleet_name, job) do
    case Accounts.get_account_by_id(job.account_id) do
      {:ok, account} ->
        pod_name = pod_name_from_sa(sa_name)

        with {:ok, dispatch_label} <- Dispatch.dispatch_label_for_pool(fleet_name),
             :ok <- stamp_owner_labels(namespace, pod_name, account),
             {:ok, jit, runner_name} <- mint_jit(account, sa_name, dispatch_label),
             :ok <- Jobs.start(job, runner_name) do
          Logger.info("runners: dispatched",
            account: account.name,
            sa: sa_name,
            runner: runner_name,
            fleet: fleet_name,
            workflow_job_id: job.workflow_job_id
          )

          {:ok, %{jit: jit, account: account, runner_name: runner_name}}
        else
          {:error, reason} = err ->
            release_safely(job, reason)
            err
        end

      {:error, :not_found} ->
        Logger.warning("runners: claimed entry has no account row",
          account_id: job.account_id,
          workflow_job_id: job.workflow_job_id
        )

        release_safely(job, :unknown_account)
        {:error, :unknown_account}
    end
  end

  defp release_safely(job, reason) do
    Jobs.release(job)
  rescue
    e ->
      Logger.warning("runners: release failed; stale-claims worker will recover",
        workflow_job_id: job.workflow_job_id,
        original_reason: inspect(reason),
        release_error: Exception.message(e)
      )

      :ok
  end

  # Builds `%{account_id => %{cap: max, inflight: count}}` for
  # the cap check inside `Jobs.claim/3`. Reads the inflight
  # counts from ClickHouse (`runner_jobs`) — no K8s LIST on the
  # hot path. Caps come from `accounts.runner_max_concurrent`
  # for every account currently observed in-flight.
  defp build_cap_lookup(fleet_name) do
    counts = Jobs.counts_per_account(fleet_name)

    if counts == %{} do
      %{}
    else
      counts
      |> Map.keys()
      |> Enum.reduce(%{}, fn account_id, acc ->
        case Accounts.get_account_by_id(account_id) do
          {:ok, %{runner_max_concurrent: cap}} when is_integer(cap) and cap > 0 ->
            Map.put(acc, account_id, %{cap: cap, inflight: Map.get(counts, account_id, 0)})

          _ ->
            # No account row or cap=0 — treat as ineligible to be
            # safe (we shouldn't be running for them anyway).
            Map.put(acc, account_id, %{cap: 0, inflight: Map.get(counts, account_id, 0)})
        end
      end)
    end
  end

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
        Logger.warning("runners: pod label stamp failed; operational view may be wrong",
          pod: pod_name,
          reason: inspect(reason)
        )

        # Continue — cap accounting reads from ClickHouse, the K8s
        # labels are operational visibility only.
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
