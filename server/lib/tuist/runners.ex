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
    * **Two-store split for the workflow_job lifecycle.** Postgres
      `runner_claims` is the thin OLTP table — one row per
      currently-claimed workflow_job, used for atomic claim (`INSERT
      … ON CONFLICT DO NOTHING` on the PK) and per-account cap
      counting. ClickHouse `runner_jobs` is the customer-facing
      view + history — `queued`, `claimed`, `running`, `completed`
      state transitions recorded as RMT INSERTs. Every PG write is
      paired with a CH INSERT so the customer surfaces stay in
      sync; CH is never queried for OLTP correctness.

  Claim flow:

      1. pick_queued from CH (candidate selection)
      2. Claims.attempt/4 — atomic PG INSERT, lost-race-safe by PK
      3. Jobs.record_claimed/3 — CH state for customer visibility
      4. mint JIT
      5. Jobs.record_running/2 — CH state once mint succeeds
      6. return 200 + JIT to the polling Pod

  On `workflow_job.completed`: Claims.delete + Jobs.complete.

  Recovery: `StaleClaimsWorker` deletes PG claims older than 5
  minutes and re-INSERTs `queued` state into CH so the next poll
  can pick the workflow_job up again.

  GitHub repo-scoping is currently delegated to the GitHub default
  runner group (id=1), which allows every repo in the org. A
  per-account `runner_group_id` is a follow-up once multi-tenant
  onboarding makes per-repo scoping necessary.
  """

  alias Tuist.Accounts
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Jobs
  alias Tuist.VCS

  require Logger

  @pool_label "tuist.dev/runner-pool"
  @owner_label "tuist.dev/runner-pool-owner"
  @account_label "tuist.dev/runner-account"

  @doc """
  Claims the next eligible queued workflow_job for the SA's fleet
  and mints a JIT for the workflow_job's account.

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
      # `ineligible_accounts/0` is a perf optimisation — skip
      # candidates whose account already hit cap so we don't
      # round-trip ClickHouse for a row we'd reject anyway. The
      # authoritative gate is `Claims.attempt/4`, which re-checks
      # the cap inside the same transaction as the INSERT and
      # holds an advisory lock on the account for the duration.
      # The pre-filter can be eventually-consistent without
      # affecting correctness.
      ineligible = ineligible_accounts()

      with {:ok, candidate} <- Jobs.pick_queued(fleet_name, ineligible),
           {:ok, claim} <-
             Claims.attempt(
               candidate.workflow_job_id,
               candidate.account_id,
               fleet_name,
               sa_name
             ) do
        Jobs.record_claimed(candidate, sa_name, claim.claimed_at)
        serve_claim(namespace, sa_name, fleet_name, candidate, claim)
      else
        {:error, :empty} ->
          {:error, :no_work_yet}

        {:error, reason} when reason in [:lost_race, :over_cap, :runners_disabled, :pod_in_use, :unknown_account] ->
          # All transactional-claim outcomes that mean "this poll
          # gets nothing right now" — collapsed for the caller.
          # The candidate (if we had one) stays queued in CH for
          # the next poll on this fleet to pick up.
          Logger.debug("runners: claim attempt declined",
            reason: reason,
            fleet: fleet_name,
            sa: sa_name
          )

          {:error, :no_work_yet}

        {:error, reason} ->
          Logger.warning("runners: dispatch_for_sa failed",
            reason: inspect(reason),
            fleet: fleet_name
          )

          {:error, :no_work_yet}
      end
    end
  end

  defp serve_claim(namespace, sa_name, fleet_name, candidate, claim) do
    case Accounts.get_account_by_id(candidate.account_id) do
      {:ok, account} ->
        pod_name = pod_name_from_sa(sa_name)

        with {:ok, dispatch_label} <- Dispatch.dispatch_label_for_pool(fleet_name),
             :ok <- stamp_owner_labels(namespace, pod_name, account),
             {:ok, jit, runner_name} <- mint_jit(account, sa_name, dispatch_label),
             :ok <- Claims.mark_running(candidate.workflow_job_id, runner_name),
             :ok <- Jobs.record_running(candidate.workflow_job_id, runner_name) do
          Logger.info("runners: dispatched",
            account: account.name,
            sa: sa_name,
            runner: runner_name,
            fleet: fleet_name,
            workflow_job_id: candidate.workflow_job_id
          )

          {:ok, %{jit: jit, account: account, runner_name: runner_name}}
        else
          {:error, reason} = err ->
            release_safely(candidate, claim, reason)
            err
        end

      {:error, :not_found} ->
        Logger.warning("runners: claimed entry has no account row",
          account_id: candidate.account_id,
          workflow_job_id: candidate.workflow_job_id
        )

        release_safely(candidate, claim, :unknown_account)
        {:error, :unknown_account}
    end
  end

  # Order matters: write `queued` to CH BEFORE deleting the PG
  # claim. If we deleted PG first and then crashed, the CH row
  # would stay `claimed`, `pick_queued` would skip it, and no
  # PG claim would remain for `StaleClaimsWorker` to recover —
  # the workflow_job would be stranded permanently.
  #
  # With CH first:
  #
  #   * Both succeed → row back in the queued pool immediately.
  #   * CH ok, PG delete fails / crash → CH says queued, PG
  #     still claimed. The next poll picks the row, hits a PG
  #     PK conflict on `Claims.attempt`, returns :lost_race
  #     and bails — no double-mint. `StaleClaimsWorker` later
  #     deletes the stale PG row (after 5 min) and the next
  #     poll claims cleanly.
  #   * CH fails → leave PG alone; the stale-worker will both
  #     drop the PG row AND re-INSERT `queued` to CH on its
  #     normal recovery path.
  defp release_safely(candidate, claim, reason) do
    Jobs.record_queued(candidate.workflow_job_id)
  rescue
    e ->
      Logger.warning("runners: record_queued failed; leaving PG claim for stale-worker",
        workflow_job_id: candidate.workflow_job_id,
        original_reason: inspect(reason),
        ch_error: Exception.message(e)
      )

      :ok
  else
    :ok ->
      case Claims.release(candidate.workflow_job_id, claim.claimed_at) do
        :ok ->
          :ok

        {:error, :stale_claim} ->
          # Stale-claims worker already released this row and
          # something else re-claimed it; leave it alone.
          Logger.warning("runners: release skipped (claim went stale)",
            workflow_job_id: candidate.workflow_job_id,
            original_reason: inspect(reason)
          )

          :ok
      end
  end

  # Builds the at-cap account list for the candidate query. One
  # indexed Postgres query across all fleets for the inflight
  # counts (the cap is account-level, NOT fleet-level — a
  # customer at cap=1 can't run one job per pool); a per-account
  # lookup for the cap config.
  defp ineligible_accounts do
    Claims.counts_per_account()
    |> Enum.filter(&at_cap?/1)
    |> Enum.map(fn {account_id, _inflight} -> account_id end)
  end

  defp at_cap?({account_id, inflight}) do
    case Accounts.get_account_by_id(account_id) do
      {:ok, %{runner_max_concurrent: cap}} when is_integer(cap) and cap > 0 ->
        inflight >= cap

      _ ->
        # No account row or cap=0 — treat as ineligible.
        true
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

        # Continue — cap accounting reads from Postgres, the K8s
        # labels are operational visibility only.
        :ok
    end
  end

  defp mint_jit(account, sa_name, dispatch_label) do
    runner_name = "tuist-#{account.name}-#{sa_name}"

    # Resolve the full installation row (carries `installation_id`
    # AND `client_url`) instead of just the integer id. The JIT
    # mint must hit the same GitHub host the webhook arrived from
    # — github.com for SaaS, the customer's GHES host otherwise.
    # Without this we'd silently mint a github.com runner for a
    # GHES org with the same login.
    with {:ok, installation} <- VCS.get_github_app_installation_for_account(account.id),
         {:ok, %{encoded_jit_config: jit, runner_name: runner_name}} <-
           GitHubClient.generate_jit_config(installation, account.name, %{
             name: runner_name,
             labels: ["self-hosted", "macOS", "ARM64", dispatch_label]
           }) do
      {:ok, jit, runner_name}
    else
      {:error, :not_found} ->
        Logger.warning("runners: no GitHub App installation for account",
          account: account.name,
          account_id: account.id
        )

        {:error, :github_mint_failed}

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
