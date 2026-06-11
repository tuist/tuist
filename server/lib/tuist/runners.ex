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
    * **Runner availability is gated by the `:runners` feature
      flag** (`Tuist.FeatureFlags.runners_enabled?/1`) — the only
      per-customer switch. There's no concurrency cap.
    * **Two-store split for the workflow_job lifecycle.** Postgres
      `runner_claims` is the thin OLTP table — one row per
      currently-claimed workflow_job, used for atomic claim (`INSERT
      … ON CONFLICT DO NOTHING` on the PK). ClickHouse `runner_jobs`
      is the customer-facing view + history — `queued`, `claimed`,
      `running`, `completed` state transitions recorded as RMT
      INSERTs. Every PG write is
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
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry
  alias Tuist.VCS

  require Logger

  @pool_label "tuist.dev/runner-pool"
  @owner_label "tuist.dev/runner-pool-owner"
  @account_label "tuist.dev/runner-account"

  # The owner label gates dispatch egress: the runners-namespace
  # NetworkPolicy admits only label-less (idle, polling) Pods to the
  # churning dispatch policy, so a claimed Pod's egress isn't perturbed
  # by a server rollout mid-job. A claimed Pod that never gets the
  # label stays in the idle policy and loses that protection, so the
  # stamp is retried to ride out a transient apiserver blip before
  # falling back to best-effort.
  @owner_label_stamp_attempts 3
  @owner_label_stamp_retry_backoff_ms 100

  # Drain stagger: stale Pods are partitioned into `@drain_slots`
  # buckets keyed by `phash2(pod_name)`. Slot N becomes drain-
  # eligible `N * @drain_interval_seconds` after the controller
  # records the image roll. Total rollout time is
  # `(@drain_slots - 1) * @drain_interval_seconds` (~3.5 min at
  # the current values). Stateless and deterministic across
  # server replicas — every instance computes the same slot for
  # the same Pod without coordination.
  @drain_slots 8
  @drain_interval_seconds 30

  @doc """
  Returns the raw load signals the runners-controller's autoscaler
  uses to compute the desired replica count for `fleet_name`:

    * `claimed` — Pods currently running or in the process of
      claiming (Postgres `runner_claims` grouped by `fleet_name`).
    * `queued` — workflow_jobs still in `runner_jobs.status =
      'queued'` for this fleet (ClickHouse).
    * `p95_concurrent_last_hour` — rolling p95 of concurrent
      claimed/running jobs over the last 60 one-minute buckets
      (ClickHouse). Smooths out single-spike noise while keeping
      the warm pool sized for typical peak load.

  The controller composes these into a desired-replica value
  using its CRD-bound knobs (`minWarmPoolFloor`, `maxReplicas`)
  — keeping the policy on the controller side and the signal
  source on the server side.
  """
  def scaling_signals_for_fleet(fleet_name) when is_binary(fleet_name) do
    %{
      fleet: fleet_name,
      claimed: Map.get(Claims.counts_per_fleet(), fleet_name, 0),
      queued: Jobs.queued_count_by_fleet(fleet_name),
      p95_concurrent_last_hour: Jobs.p95_concurrent_last_hour(fleet_name)
    }
  end

  @doc """
  Claims the next eligible queued workflow_job for the SA's fleet
  and mints a JIT for the workflow_job's account.

  Returns `{:ok, %{jit, account, runner_name}}` on success.

  Error cases the web layer translates to HTTP responses:
    * `{:error, :no_work_yet}` — queue empty or we lost a claim
      race; warm Pod keeps polling.
    * `{:error, :not_found}` — SA gone (raced with GC).
    * `{:error, :no_pool_label}` — SA missing the fleet label.
    * `{:error, :unknown_account}` — claimed entry's account
      went away.
    * `{:error, :github_mint_failed}` — GitHub refused the JIT.
    * `{:error, :not_in_cluster}` — server not running in-cluster.
    * `{:error, :drain}` — the polling Pod's image no longer
      matches its RunnerPool's `spec.image`. The Pod is idle
      and stale, so the web layer returns HTTP 410 to signal
      the Pod's dispatch-poll script to exit cleanly; the
      single-shot lifecycle then halts the VM and the runner-
      pool reconciler replaces the Pod with one on the current
      image. In-flight customer jobs are unaffected because
      the check runs only on idle polls (before claim attempt).
  """
  def dispatch_for_sa(namespace, sa_name) when is_binary(namespace) and is_binary(sa_name) do
    :telemetry.span(Telemetry.event_name_dispatch_request(), %{}, fn ->
      result = do_dispatch_for_sa(namespace, sa_name)
      {result, %{outcome: dispatch_outcome(result)}}
    end)
  end

  defp do_dispatch_for_sa(namespace, sa_name) do
    with {:ok, sa} <- K8sClient.get_service_account(namespace, sa_name),
         {:ok, fleet_name} <- pool_label(sa),
         :ok <- check_not_stale(namespace, sa_name, fleet_name) do
      with {:ok, candidate} <- Jobs.pick_queued(fleet_name, []),
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

        {:error, reason} when reason in [:lost_race, :pod_in_use] ->
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

  defp dispatch_outcome({:ok, _}), do: "served"
  defp dispatch_outcome({:error, reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp dispatch_outcome(_), do: "unknown"

  defp serve_claim(namespace, sa_name, fleet_name, candidate, claim) do
    case Accounts.get_account_by_id(candidate.account_id) do
      {:ok, account} ->
        pod_name = pod_name_from_sa(sa_name)

        with {:ok, %{dispatch_label: pool_dispatch_label, runner_labels: runner_labels}} <-
               Dispatch.pool_summary_by_name(fleet_name),
             dispatch_label = pick_dispatch_label(candidate, pool_dispatch_label),
             :ok <- stamp_owner_labels(namespace, pod_name, account),
             {:ok, jit, runner_name} <- mint_jit(account, sa_name, dispatch_label, runner_labels),
             :ok <- Claims.mark_running(candidate.workflow_job_id, runner_name),
             :ok <- record_running_safe(candidate.workflow_job_id, runner_name) do
          # Open the per-Pod billing session only after dispatch
          # commits — JIT minted, PG marked running, CH state
          # transitioned. Opening earlier (e.g. at claim-win in
          # `Jobs.record_claimed/3`) leaks a session on every
          # mid-dispatch failure since `release_safely/3` only
          # re-queues the CH row and releases the PG claim — the
          # session row would sit open and Billing would clamp it
          # to the 6h max-lifetime.
          RunnerSessions.open(%{
            workflow_job_id: candidate.workflow_job_id,
            account_id: candidate.account_id,
            fleet_name: Map.get(candidate, :fleet_name, fleet_name),
            pod_name: pod_name,
            runner_name: runner_name,
            repository: Map.get(candidate, :repository, ""),
            workflow_name: Map.get(candidate, :workflow_name, ""),
            started_at: claim.claimed_at
          })

          Logger.info("runners: dispatched",
            account: account.name,
            sa: sa_name,
            runner: runner_name,
            fleet: fleet_name,
            workflow_job_id: candidate.workflow_job_id
          )

          {:ok,
           %{
             jit: jit,
             account: account,
             runner_name: runner_name,
             workflow_job_id: candidate.workflow_job_id,
             fleet_platform: Catalog.fleet_platform(fleet_name)
           }}
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

  # `Jobs.record_running` can raise on ClickHouse connectivity
  # failures (Tuist.IngestRepo is :async by default but the
  # underlying connection pool surfaces hard errors). A raise
  # after `Claims.mark_running/2` would leave PG in `running`
  # (which `Claims.list_stale/1` skips), the cap consumed
  # forever, and the runner stranded because no JIT ever
  # reached the VM. Catch it, surface as `{:error, _}` so the
  # `with`'s `else` runs `release_safely` and the
  # `workflow_job` returns to the queued pool.
  defp record_running_safe(workflow_job_id, runner_name) do
    Jobs.record_running(workflow_job_id, runner_name)
    :ok
  rescue
    e ->
      Logger.warning("runners: record_running raised; releasing claim",
        workflow_job_id: workflow_job_id,
        runner: runner_name,
        ch_error: Exception.message(e)
      )

      {:error, :record_running_failed}
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

  defp stamp_owner_labels(namespace, pod_name, account) do
    patch = %{
      "metadata" => %{
        "labels" => %{
          @owner_label => account.name,
          @account_label => Integer.to_string(account.id)
        }
      }
    }

    patch_pod_labels(namespace, pod_name, patch, @owner_label_stamp_attempts)
  end

  defp patch_pod_labels(namespace, pod_name, patch, attempts_left) do
    case K8sClient.patch_pod(namespace, pod_name, patch) do
      {:ok, _} ->
        :ok

      {:error, reason} when attempts_left > 1 ->
        Logger.warning("runners: pod label stamp failed; retrying",
          pod: pod_name,
          reason: inspect(reason)
        )

        Process.sleep(@owner_label_stamp_retry_backoff_ms)
        patch_pod_labels(namespace, pod_name, patch, attempts_left - 1)

      {:error, reason} ->
        Logger.warning(
          "runners: pod label stamp failed after retries; Pod stays in the idle dispatch NetworkPolicy and a server rollout may perturb its egress",
          pod: pod_name,
          reason: inspect(reason)
        )

        # Non-fatal on purpose. The claim is already won here; failing
        # dispatch would strand the job, and a sustained apiserver
        # outage would block all dispatch. Degrade to "running without
        # the label" rather than dropping the job. Per-account cap
        # accounting reads from Postgres, not these labels.
        :ok
    end
  end

  defp mint_jit(account, sa_name, dispatch_label, runner_labels) do
    # GitHub's `create JIT config` API caps `name` at 64 characters.
    # Earlier versions prefixed `tuist-<account.name>-` — for macOS
    # pools that fit, but the Linux pool name is longer
    # (`<release>-tuist-runner-pool-linux-ubuntu-22-04`), so the
    # combined string overshoots and GitHub returns 422. The SA
    # name is already unique within the cluster and contains the
    # chart's release + pool prefix, and the runner is registered
    # under `account.name` via the API URL — so dropping the
    # redundant prefix is safe.
    runner_name = sa_name

    # Resolve the full installation row (carries `installation_id`
    # AND `client_url`) instead of just the integer id. The JIT
    # mint must hit the same GitHub host the webhook arrived from
    # — github.com for SaaS, the customer's GHES host otherwise.
    # Without this we'd silently mint a github.com runner for a
    # GHES org with the same login.
    #
    # `runner_labels` carries the OS/arch identification triple
    # (e.g. `["self-hosted", "macOS", "ARM64"]` for the Mac fleet,
    # `["self-hosted", "Linux", "X64"]` for the Hetzner Cloud
    # fleet); `dispatch_label` is appended so the customer's
    # `runs-on` matches and GitHub binds the workflow_job to this
    # specific pool's runner.
    # Match GitHub-hosted's workspace path so on-disk artifacts
    # that bake absolute paths (SwiftPM `.build/checkouts/`,
    # DerivedData, `actions/cache` payloads) work interchangeably
    # between hosted and self-hosted runs. The runner images
    # create a `runner` user with the corresponding HOME on each
    # OS — `/Users/runner` on macOS, `/home/runner` on Linux.
    work_folder =
      if "macOS" in runner_labels do
        "/Users/runner/work"
      else
        "/home/runner/work"
      end

    with {:ok, installation} <- VCS.get_github_app_installation_for_account(account.id),
         {:ok, %{encoded_jit_config: jit, runner_name: runner_name}} <-
           GitHubClient.generate_jit_config(installation, account.name, %{
             name: runner_name,
             labels: runner_labels ++ [dispatch_label],
             work_folder: work_folder
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

  # Profile-aware dispatch labelling: prefer the customer-facing
  # label the workflow_job carried in `runs-on:` (e.g.
  # `tuist-default`), which the webhook stored on the candidate's
  # CH row. Fall back to the pool's internal `dispatchLabel`
  # (e.g. `shape-linux-4vcpu-16gb`) only when the candidate's
  # `requested_dispatch_label` is missing — that path only fires
  # for legacy rows enqueued before the requested-label column
  # existed.
  defp pick_dispatch_label(candidate, pool_dispatch_label) do
    case Map.get(candidate, :requested_dispatch_label, "") do
      label when is_binary(label) and label != "" -> label
      _ -> pool_dispatch_label
    end
  end

  # The polling Pod's name. The controller's podtemplate stamps
  # Pods + SAs with the same name, so the SA name IS the Pod name.
  defp pod_name_from_sa(sa_name), do: sa_name

  # Compare the polling Pod's runner-container image to the
  # RunnerPool's `spec.image`. When the chart bumps the digest pin,
  # idle Running Pods that are still on the old image return
  # `{:error, :drain}` here, which the web layer translates to HTTP
  # 410. The Pod's `dispatch-poll.sh` handles 410 by exiting cleanly;
  # the EXIT trap halts the VM and the runner-pool reconciler reaps
  # the Pod and creates a replacement on the current image.
  #
  # Drains are staggered by a per-Pod time slot computed from
  # `status.imageRolledAt` (recorded by the controller on every
  # observed `spec.image` change) so the warm pool doesn't drop to
  # zero on every digest bump. See `slot_active?/2`.
  #
  # Guarded by `K8sClient` lookups that may fail (Pod / RunnerPool
  # gone, in-cluster client misconfigured). Any lookup failure is
  # downgraded to `:ok` — refusing dispatch on a transient k8s blip
  # would stall the whole pool. The drain check is opportunistic
  # cleanup, not a correctness gate; the reconciler's
  # Pending-stale path catches the unhappy long-tail.
  defp check_not_stale(namespace, sa_name, fleet_name) do
    pod_name = pod_name_from_sa(sa_name)

    with {:ok, pool} <- K8sClient.get_runner_pool(namespace, fleet_name),
         {:ok, pool_image} <- pool_image(pool),
         {:ok, pod} <- K8sClient.get_pod(namespace, pod_name),
         {:ok, pod_image} <- pod_image(pod) do
      cond do
        pod_image == pool_image ->
          :ok

        not slot_active?(pool, pod_name) ->
          # Stale, but this Pod's drain slot hasn't opened yet.
          # Let it keep polling — it'll receive 410 on a later
          # tick once its slot becomes eligible.
          :ok

        true ->
          Logger.info("runners: draining stale pod",
            pod: pod_name,
            fleet: fleet_name,
            pod_image: pod_image,
            pool_image: pool_image
          )

          {:error, :drain}
      end
    else
      _ -> :ok
    end
  end

  defp pool_image(%{"spec" => %{"image" => image}}) when is_binary(image) and image != "", do: {:ok, image}
  defp pool_image(_), do: :error

  defp pod_image(%{"spec" => %{"containers" => [%{"image" => image} | _]}}) when is_binary(image) and image != "",
    do: {:ok, image}

  defp pod_image(_), do: :error

  # `slot_active?/2` returns true when enough time has elapsed
  # since `status.imageRolledAt` for this specific Pod's drain
  # slot to fire. Slot is `phash2(pod_name) rem @drain_slots`; the
  # slot's drain window opens `slot * @drain_interval_seconds`
  # after the roll. When the controller hasn't yet recorded a roll
  # (status.imageRolledAt absent or unparseable), we defer the
  # drain rather than fire eagerly — the controller catches up
  # within one reconcile tick (≤60s) and the Pending-stale
  # recycler in the controller covers the Pending half meanwhile.
  defp slot_active?(pool, pod_name) do
    case rolled_at(pool) do
      {:ok, %DateTime{} = t} ->
        slot = :erlang.phash2(pod_name, @drain_slots)
        elapsed = DateTime.diff(Tuist.Time.utc_now(), t, :second)
        elapsed >= slot * @drain_interval_seconds

      :error ->
        false
    end
  end

  defp rolled_at(%{"status" => %{"imageRolledAt" => ts}}) when is_binary(ts) and ts != "" do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> :error
    end
  end

  defp rolled_at(_), do: :error
end
