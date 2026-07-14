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
      flag** (`Tuist.FeatureFlags.runners_enabled?/1`). Independent
      Linux and macOS vCPU/RAM budgets protect shared capacity from
      a single account consuming every runner.
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
      2. Claims.attempt/5 — atomic resource check + PG INSERT,
         lost-race-safe by PK
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
  alias Tuist.Runners.CacheGrant
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.VolumeAffinities
  alias Tuist.Runners.VolumeHeads
  alias Tuist.Storage
  alias Tuist.VCS

  require Logger

  @pool_label "tuist.dev/runner-pool"
  @owner_label "tuist.dev/runner-pool-owner"
  @account_label "tuist.dev/runner-account"
  # Stamped on a Pod whenever dispatch cannot POSITIVELY confirm the job is
  # trusted (same-repo, not a fork). tart-kubelet reads it and skips cache-volume
  # materialization + promotion, so an untrusted fork job neither reads the
  # account's warm master nor writes into it. Fail-closed: any uncertainty means
  # the label is present and the job runs cold on an isolated branch.
  @cache_untrusted_label "tuist.dev/runner-cache-untrusted"

  # The owner label gates dispatch egress: the runners-namespace
  # NetworkPolicy admits only label-less (idle, polling) Pods to the
  # churning dispatch policy, so a claimed Pod's egress isn't perturbed
  # by a server rollout mid-job. A claimed Pod that never gets the
  # label stays in the idle policy and loses that protection, so the
  # stamp is retried to ride out a transient apiserver blip before
  # falling back to best-effort.
  @owner_label_stamp_attempts 3
  @owner_label_stamp_retry_backoff_ms 100
  @github_runner_name_max_length 64

  # The runners-controller stamps `tuist.dev/drain-eligible=true` on the
  # stale Pods it has selected to retire in the current roll wave, up to
  # a concurrency cap it derives from Pod readiness. The dispatch
  # endpoint 410s a stale Pod only when it carries this label, so the
  # rollout pace lives in the controller (which can see readiness and
  # bound how many nodes `tart pull` the new image at once) rather than
  # the server draining every stale Pod the moment its image diverges —
  # the open-loop time stagger this replaced drained on a fixed 30s
  # cadence that was far shorter than a multi-minute image pull.
  @drain_eligible_label "tuist.dev/drain-eligible"
  @max_claim_attempts_per_dispatch 16

  # Dispatch-time volume affinity. `pick_queued` fetches the K
  # oldest queued jobs; the server hands the polling runner the oldest one
  # affine to its node only if that job's enqueue time is within the age
  # tolerance of the queue head, else the head. Both are configuration,
  # tuned from the affinity hit rate and queue-latency telemetry rather
  # than re-litigated here; the age tolerance is the precise operational
  # meaning of the hard rule that affinity never delays a job.
  @volume_affinity_top_k 20
  @volume_affinity_age_tolerance_seconds 30

  defp volume_affinity_top_k do
    Application.get_env(:tuist, :runner_volume_affinity_top_k, @volume_affinity_top_k)
  end

  defp volume_affinity_age_tolerance_seconds do
    Application.get_env(
      :tuist,
      :runner_volume_affinity_age_tolerance_seconds,
      @volume_affinity_age_tolerance_seconds
    )
  end

  # Volume affinity is a macOS-only concern: only the Mac fleet keeps per-account
  # cache masters on its hosts. Gating on platform keeps the Linux fleet (and any
  # other volumeless fleet) out of affinity recording and queue reordering, so a
  # host that holds no volume never has its queue scored for one. The macOS host
  # capability itself is the runner-cache volume; the server can't see a host's
  # per-host `gib`, so platform is the capability proxy — a `gib:0` macOS host
  # just records harmless affinity that materialize never acts on.
  defp volume_affinity_enabled?(fleet_name) do
    Catalog.fleet_platform(fleet_name) == :macos
  end

  # Presigned-URL lifetime for the cache-volume master archive. Comfortably
  # covers a job: the download is used at materialize, the upload at job end.
  @volume_master_url_ttl_seconds 6 * 60 * 60

  # The account's cache-volume HEAD for the dispatch response: the current
  # generation + inventory digest, plus presigned GET/PUT URLs for the master
  # archive so the runner can converge a stale local master and publish a fresh
  # one. Best-effort — any failure returns nil and the runner stays on its
  # local master (the status quo).
  defp volume_head_payload(account) do
    key = volume_master_object_key(account.id)
    head = VolumeHeads.get_head(account.id)
    download_url = Storage.generate_download_url(key, account, expires_in: @volume_master_url_ttl_seconds)
    upload_url = Storage.generate_upload_url(key, account, expires_in: @volume_master_url_ttl_seconds)

    # SSRF guard: a runner host follows the download URL (and the guest the
    # upload URL), so refuse to hand out one whose host resolves to a private,
    # loopback, or link-local address. A misconfigured or hostile storage
    # endpoint would otherwise turn this into an SSRF primitive from every host.
    # A rejected URL just means no HEAD (the job stays on its local master, the
    # status quo) — never a fetch against an internal address.
    if Tuist.URL.public_host_url?(download_url) and Tuist.URL.public_host_url?(upload_url) do
      %{
        generation: (head && head.generation) || 0,
        digest: head && head.tree_digest,
        download_url: download_url,
        upload_url: upload_url
      }
    end
  rescue
    _ -> nil
  end

  @doc """
  Records a runner's promote of `account_id`'s cache volume: bumps the account's
  HEAD to `tree_digest` published from `node_name`. Called by the runner after a
  successful, cache-changing job whose branch it uploaded to the master archive.
  """
  def report_volume_head(account_id, node_name, tree_digest) do
    VolumeHeads.bump_head(account_id, node_name, tree_digest)
  end

  @doc """
  Resolves the account a runner Pod ran, from the `tuist.dev/runner-account`
  label the server stamped on it at claim. Authoritative — the runner can't
  change it — so a volume-head report is bound to the account it actually ran,
  not to whatever the request body claims.

  A Pod carrying the `tuist.dev/runner-cache-untrusted` label (an untrusted
  fork-PR job) is rejected: it was dispatched with no volume-head and its cache
  branch is discarded on the host, so it must never be able to advance an
  account's shared HEAD. Fail-closed so a compromised fork job can't poison the
  master by reporting a promote.
  """
  def account_id_for_sa(namespace, sa_name) do
    with {:ok, pod} <- K8sClient.get_pod(namespace, pod_name_from_sa(sa_name)),
         :ok <- reject_untrusted_pod(pod),
         label when is_binary(label) <- get_in(pod, ["metadata", "labels", @account_label]),
         {account_id, ""} <- Integer.parse(label) do
      {:ok, account_id}
    else
      {:error, :cache_untrusted} = error -> error
      _ -> {:error, :account_unresolved}
    end
  end

  defp reject_untrusted_pod(pod) do
    if get_in(pod, ["metadata", "labels", @cache_untrusted_label]) == "true" do
      {:error, :cache_untrusted}
    else
      :ok
    end
  end

  @doc """
  Object-storage prefix holding an account's runner cache-volume master
  archive(s). Deleting this prefix removes the account's cache masters
  regardless of the per-object key, so it is the unit of account-deletion
  cleanup. Keyed by `account_id` (stable across handle renames), so it is not
  swept by the account-handle-based artifact retention — account deletion is
  what removes it.
  """
  def volume_master_object_prefix(account_id) do
    "runner-volume-masters/#{account_id}/"
  end

  defp volume_master_object_key(account_id) do
    volume_master_object_prefix(account_id) <> "#{VolumeHeads.reserved_tuist_cache()}.zip"
  end

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
      {result, fleet_name} = do_dispatch_for_sa(namespace, sa_name)
      {to_caller_result(result), %{outcome: dispatch_outcome(result), fleet: fleet_name || "unknown"}}
    end)
  end

  # Returns `{result, fleet_name}`. `result` carries the *granular*
  # reason (`:empty`, `:lost_race`, `:pod_in_use`, …) so the dispatch
  # telemetry can tell "queue was empty" apart from "lost the claim
  # race" — the old blanket `:no_work_yet` hid that distinction and
  # made a real dispatch stall indistinguishable from an idle warm
  # pool polling. `fleet_name` is the resolved pool label (or `nil`
  # when the SA / label lookup failed) so the dispatch metric is
  # sliceable per fleet. The web-facing collapse back to `:no_work_yet`
  # happens in `to_caller_result/1`.
  defp do_dispatch_for_sa(namespace, sa_name) do
    with {:ok, sa} <- K8sClient.get_service_account(namespace, sa_name),
         {:ok, fleet_name} <- pool_label(sa) do
      case check_not_stale(namespace, sa_name, fleet_name) do
        {:ok, node_name} -> {claim_and_serve(namespace, sa_name, fleet_name, node_name), fleet_name}
        {:error, reason} -> {{:error, reason}, fleet_name}
      end
    else
      {:error, reason} -> {{:error, reason}, nil}
    end
  end

  defp claim_and_serve(namespace, sa_name, fleet_name, node_name) do
    excluded_workflow_job_ids = Claims.workflow_job_ids_for_fleet(fleet_name)

    claim_and_serve(
      namespace,
      sa_name,
      fleet_name,
      node_name,
      [],
      excluded_workflow_job_ids,
      @max_claim_attempts_per_dispatch
    )
  end

  defp claim_and_serve(_namespace, sa_name, fleet_name, _node_name, _excluded_account_ids, _excluded_workflow_job_ids, 0) do
    Logger.debug("runners: claim attempts exhausted",
      fleet: fleet_name,
      sa: sa_name
    )

    {:error, :lost_race}
  end

  defp claim_and_serve(
         namespace,
         sa_name,
         fleet_name,
         node_name,
         excluded_account_ids,
         excluded_workflow_job_ids,
         attempts_left
       ) do
    case pick_affine_candidate(fleet_name, node_name, excluded_account_ids, excluded_workflow_job_ids) do
      {:ok, candidate} ->
        claim_candidate(
          namespace,
          sa_name,
          fleet_name,
          node_name,
          candidate,
          excluded_account_ids,
          excluded_workflow_job_ids,
          attempts_left
        )

      {:error, :empty} ->
        {:error, :empty}
    end
  end

  defp claim_candidate(
         namespace,
         sa_name,
         fleet_name,
         node_name,
         candidate,
         excluded_account_ids,
         excluded_workflow_job_ids,
         attempts_left
       ) do
    case candidate_resources(candidate, fleet_name) do
      {:ok, resources} ->
        attempt_candidate(
          namespace,
          sa_name,
          fleet_name,
          node_name,
          candidate,
          resources,
          excluded_account_ids,
          excluded_workflow_job_ids,
          attempts_left
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp attempt_candidate(
         namespace,
         sa_name,
         fleet_name,
         node_name,
         candidate,
         resources,
         excluded_account_ids,
         excluded_workflow_job_ids,
         attempts_left
       ) do
    case Claims.attempt(candidate.workflow_job_id, candidate.account_id, fleet_name, sa_name, resources) do
      {:ok, claim} ->
        # Record the affinity signal on every claim win, but only for fleets
        # that actually hold volumes (macOS): a volume for this account
        # exists (or is about to) where its jobs ran, so future jobs of this
        # account prefer this node. Volumeless fleets record nothing so their
        # queues are never reordered for masters that don't exist.
        if volume_affinity_enabled?(fleet_name) do
          VolumeAffinities.record(node_name, candidate.account_id)
        end

        Jobs.record_claimed(candidate, sa_name, claim.claimed_at)
        serve_claim(namespace, sa_name, fleet_name, candidate, claim)

      {:error, :lost_race} ->
        Logger.debug("runners: claim attempt lost race; trying next queued job",
          fleet: fleet_name,
          sa: sa_name,
          workflow_job_id: candidate.workflow_job_id
        )

        claim_and_serve(
          namespace,
          sa_name,
          fleet_name,
          node_name,
          excluded_account_ids,
          [candidate.workflow_job_id | excluded_workflow_job_ids],
          attempts_left - 1
        )

      {:error, :account_busy} ->
        Logger.debug("runners: account admission is busy; trying next account",
          fleet: fleet_name,
          sa: sa_name,
          account_id: candidate.account_id
        )

        claim_and_serve(
          namespace,
          sa_name,
          fleet_name,
          node_name,
          [candidate.account_id | excluded_account_ids],
          excluded_workflow_job_ids,
          attempts_left
        )

      {:error, {:concurrency_limit_reached, details}} ->
        Logger.debug("runners: account reached platform concurrency limit; trying next account",
          fleet: fleet_name,
          sa: sa_name,
          account_id: candidate.account_id,
          reason: inspect({:concurrency_limit_reached, details})
        )

        claim_and_serve(
          namespace,
          sa_name,
          fleet_name,
          node_name,
          [candidate.account_id | excluded_account_ids],
          excluded_workflow_job_ids,
          attempts_left
        )

      {:error, :pod_in_use} ->
        Logger.debug("runners: claim attempt declined",
          reason: :pod_in_use,
          fleet: fleet_name,
          sa: sa_name
        )

        {:error, :pod_in_use}

      {:error, reason} ->
        Logger.warning("runners: dispatch_for_sa failed",
          reason: inspect(reason),
          fleet: fleet_name
        )

        {:error, reason}
    end
  end

  defp candidate_resources(%{platform: "linux", vcpus: vcpus, memory_gb: memory_gb}, _fleet_name)
       when is_integer(vcpus) and vcpus > 0 and is_integer(memory_gb) and memory_gb > 0,
       do: {:ok, %{platform: :linux, vcpus: vcpus, memory_gb: memory_gb}}

  defp candidate_resources(%{platform: "macos", vcpus: vcpus, memory_gb: memory_gb}, _fleet_name)
       when is_integer(vcpus) and vcpus > 0 and is_integer(memory_gb) and memory_gb > 0,
       do: {:ok, %{platform: :macos, vcpus: vcpus, memory_gb: memory_gb}}

  defp candidate_resources(_candidate, fleet_name), do: Catalog.resources_for_fleet(fleet_name)

  # Fetch the K oldest queued candidates and let the volume-affinity policy
  # pick the one to hand this node: the oldest affine candidate within the
  # age tolerance of the head, else the head. With no node identity or no
  # affinity, this is exactly today's "oldest queued job".
  defp pick_affine_candidate(fleet_name, node_name, excluded_account_ids, excluded_workflow_job_ids) do
    case Jobs.pick_queued_top_k(
           fleet_name,
           excluded_account_ids,
           excluded_workflow_job_ids,
           volume_affinity_top_k()
         ) do
      {:ok, candidates} ->
        if volume_affinity_enabled?(fleet_name) do
          {:ok,
           VolumeAffinities.select_candidate(
             candidates,
             node_name,
             volume_affinity_age_tolerance_seconds()
           )}
        else
          # No volumes on this fleet: hand out the plain oldest-queued head, no
          # affinity scoring or reordering.
          {:ok, List.first(candidates)}
        end

      {:error, :empty} ->
        {:error, :empty}
    end
  end

  # The dispatch poll loop only needs "nothing for you this tick", so
  # the empty-queue / claim-contention family collapses to the single
  # `:no_work_yet` the web layer and the polling Pod already handle.
  # Every other reason — `:drain`, `:no_pool_label`, `:github_mint_failed`,
  # … — passes through untouched.
  defp to_caller_result({:error, reason}) when reason in [:empty, :lost_race, :pod_in_use], do: {:error, :no_work_yet}

  defp to_caller_result(result), do: result

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
             github_org = github_org_login(candidate, account),
             :ok <- stamp_owner_label(namespace, pod_name, account),
             {:ok, jit, runner_name} <- mint_jit(account, github_org, sa_name, dispatch_label, runner_labels),
             :ok <- Claims.mark_running(candidate.workflow_job_id, runner_name),
             :ok <- record_running_safe(candidate.workflow_job_id, runner_name) do
          # Fork-exclusion: only a trusted (same-repo, non-fork) job may touch
          # the account's shared cache. Determine trust fail-closed — any
          # uncertainty means untrusted, so the job runs cold and cannot poison
          # the master. Untrusted jobs get NO grant and NO volume HEAD (so the
          # cache isn't account-portable and the guest can't publish), and the
          # host is told to skip materialize/promote via the untrusted label.
          trusted = job_trusted?(candidate, account)

          # Stamp the account label (the host's cache-materialize trigger) only
          # now that dispatch has fully committed — stamping it before the commit
          # would let a failed dispatch strand a stale account on a Pod that later
          # runs a different one. The untrusted label rides the same patch so the
          # host sees both atomically. See stamp_account_label/4.
          stamp_account_label(namespace, pod_name, account, trusted)

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
             fleet_on_cluster_network: Catalog.fleet_on_cluster_network?(fleet_name),
             fleet_platform: Catalog.fleet_platform(fleet_name),
             # Per-account cache-signing grant — trusted jobs only. nil for an
             # untrusted (fork) job or when minting is unconfigured; the runner
             # then falls back to the MAC default (machine-local), so an
             # untrusted job's cache is never account-portable.
             cache_signing_grant: if(trusted, do: CacheGrant.mint(candidate.account_id)),
             # Current cache-volume HEAD (generation + inventory digest) plus
             # presigned URLs for the account's master archive — trusted jobs
             # only. nil for an untrusted job (no convergence, and the guest has
             # no upload URL so it cannot publish a HEAD) or best-effort failure.
             volume_head: if(trusted, do: volume_head_payload(account))
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
  #     still claimed. The next poll skips rows already claimed
  #     in PG (or loses the claim race once and tries the next
  #     queued row), so later workflow_jobs can still dispatch
  #     while `StaleClaimsWorker` cleans up the stale PG row.
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

  # The owner label gates dispatch egress (see the @owner_label_stamp_attempts
  # note) so it is stamped as soon as the claim is won, before the JIT mint.
  defp stamp_owner_label(namespace, pod_name, account) do
    patch = %{"metadata" => %{"labels" => %{@owner_label => account.name}}}
    patch_pod_labels(namespace, pod_name, patch, @owner_label_stamp_attempts)
  end

  # The account label is the host's cache-materialize trigger: tart-kubelet
  # clonefiles this account's cache master into the VM's branch when it observes
  # the label. It is stamped only after the dispatch fully commits, NOT alongside
  # the owner label. Stamping it pre-commit would let a dispatch that fails after
  # the stamp (mint or ClickHouse error → release_safely re-queues the job while
  # the Pod keeps polling) leave a stale account on a Pod that later wins a claim
  # for a DIFFERENT account — the host would then run the second account's job on
  # the first account's materialized cache. Post-commit stamping guarantees only
  # the account the VM actually runs ever triggers materialization. Best-effort:
  # a stamp failure degrades to a cold (unmaterialized) job, never a
  # wrong-account one.
  defp stamp_account_label(namespace, pod_name, account, trusted) do
    labels = %{@account_label => Integer.to_string(account.id)}
    labels = if trusted, do: labels, else: Map.put(labels, @cache_untrusted_label, "true")
    patch_pod_labels(namespace, pod_name, %{"metadata" => %{"labels" => labels}}, @owner_label_stamp_attempts)
  end

  # A job is trusted only when its workflow run's head repository is the base
  # repository — a same-repo push or PR, whose author has write access — not a
  # fork. Fail-closed: a missing run id, an API error, an unexpected response
  # shape, or any exception is treated as UNTRUSTED, so the cache volume is
  # withheld and the job runs cold rather than risk a fork poisoning the shared
  # master. Runs in the committed-dispatch path, so an error here only costs
  # warmth, never correctness.
  defp job_trusted?(candidate, account) do
    with run_id when is_integer(run_id) <- Map.get(candidate, :workflow_run_id),
         repository when is_binary(repository) and repository != "" <- Map.get(candidate, :repository),
         {:ok, installation} <- VCS.get_github_app_installation_for_account(account.id),
         {:ok, run} <-
           GitHubClient.get_workflow_run(%{
             repository_full_handle: repository,
             installation: installation,
             run_id: run_id
           }),
         head when is_binary(head) <- get_in(run, ["head_repository", "full_name"]),
         base when is_binary(base) <- get_in(run, ["repository", "full_name"]) do
      String.downcase(head) == String.downcase(base)
    else
      _ -> false
    end
  rescue
    _ -> false
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

  # The GitHub org login to register the runner under — the owner of
  # the repo whose workflow_job we're serving. This is NOT
  # `account.name`: a Tuist account handle can differ from the GitHub
  # org login it's connected to, and the org-scoped JIT endpoint
  # (`/orgs/<org>/actions/runners/generate-jitconfig`) 404s on the
  # wrong login, stranding every job in a claim→mint-fail→requeue
  # loop. The installation's org owns the repo, so the repo owner is
  # the correct login; fall back to `account.name` only when the
  # candidate carries no repository (synthetic rows).
  defp github_org_login(%{repository: repository}, account) when is_binary(repository) do
    case String.split(repository, "/", parts: 2) do
      [owner, _repo] when owner != "" -> owner
      _ -> account.name
    end
  end

  defp github_org_login(_candidate, account), do: account.name

  defp mint_jit(account, github_org, sa_name, dispatch_label, runner_labels) do
    # GitHub's `create JIT config` API caps `name` at 64 characters.
    # Earlier versions prefixed `tuist-<account.name>-` — for macOS
    # pools that fit, but the Linux pool name is longer
    # (`<release>-tuist-runner-pool-linux-ubuntu-22-04`), so the
    # combined string overshoots and GitHub returns 422. Use the
    # polling Pod's SA name as the stable prefix, but add a fresh
    # per-mint suffix. GitHub reserves the runner name as soon as it
    # creates the JIT config; if the HTTP response or a later local
    # state write fails before the Pod receives that JIT, retrying
    # the same name loops forever on 409 "Already exists".
    runner_name = github_runner_name(sa_name)

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
           GitHubClient.generate_jit_config(installation, github_org, %{
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
          org: github_org,
          runner: runner_name,
          reason: inspect(reason)
        )

        {:error, :github_mint_failed}
    end
  end

  defp github_runner_name(sa_name) do
    suffix = "-" <> (4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower))
    prefix = String.slice(sa_name, 0, @github_runner_name_max_length - byte_size(suffix))

    prefix <> suffix
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
  # Drains are paced by the controller, which marks only a capped number
  # of stale Pods `tuist.dev/drain-eligible` at a time so a digest roll
  # doesn't make the whole fleet pull the new image at once and collapse
  # the warm pool. See `drain_eligible?/1`.
  #
  # Guarded by `K8sClient` lookups that may fail (Pod / RunnerPool
  # gone, in-cluster client misconfigured). Any lookup failure is
  # downgraded to `:ok` — refusing dispatch on a transient k8s blip
  # would stall the whole pool. The drain check is opportunistic
  # cleanup, not a correctness gate; the reconciler's
  # Pending-stale path catches the unhappy long-tail.
  # Returns {:ok, node_name} — the Node the polling Pod is running on, read
  # from the same Pod object the staleness check already fetches (no extra
  # API call) — so the caller can score volume affinity for this node.
  # node_name is nil when the Pod/pool lookup fails or spec.nodeName isn't
  # set yet; affinity then degrades to "no preference". {:error, :drain}
  # still short-circuits a stale Pod.
  defp check_not_stale(namespace, sa_name, fleet_name) do
    pod_name = pod_name_from_sa(sa_name)

    case K8sClient.get_pod(namespace, pod_name) do
      {:ok, pod} ->
        if committed?(pod) do
          # The account label is stamped only after a claim fully commits, and a
          # committed Pod that received its JIT runs the job in place and never
          # polls again. So a committed Pod polling HERE means its dispatch
          # response was lost and the runner never started — it must not be
          # handed a second, possibly different, account on the cache already
          # materialized for the first (the host's SourceAccount guard blocks
          # promotion, but not the guest reading it). 410 so the guest halts and
          # the runner-pool reconciler replaces it with a fresh Pod.
          Logger.info("runners: reaping committed-but-polling pod",
            pod: pod_name,
            fleet: fleet_name
          )

          {:error, :pod_committed}
        else
          check_image_staleness(namespace, fleet_name, pod)
        end

      _ ->
        # Pod unreadable (transient apiserver blip / not in cluster). We can't
        # check commitment or staleness; degrade to "no preference" and let the
        # claim path proceed, same as a pool-lookup miss.
        {:ok, nil}
    end
  end

  # A Pod carries the account label once its dispatch has committed.
  defp committed?(pod), do: is_binary(get_in(pod, ["metadata", "labels", @account_label]))

  defp check_image_staleness(namespace, fleet_name, pod) do
    with {:ok, pool} <- K8sClient.get_runner_pool(namespace, fleet_name),
         {:ok, pool_image} <- pool_image(pool),
         {:ok, pod_image} <- pod_image(pod) do
      cond do
        pod_image == pool_image ->
          {:ok, node_name_of(pod)}

        not drain_eligible?(pod) ->
          # Stale, but the controller hasn't marked this Pod
          # drain-eligible yet — it paces the rollout by labeling only a
          # capped number of stale Pods at a time. Keep polling; we'll
          # 410 once the controller labels it.
          {:ok, node_name_of(pod)}

        true ->
          Logger.info("runners: draining stale pod",
            pod: get_in(pod, ["metadata", "name"]),
            fleet: fleet_name,
            pod_image: pod_image,
            pool_image: pool_image
          )

          {:error, :drain}
      end
    else
      # Pool lookup / image parse failed but we have the Pod; degrade to "not
      # stale" with the Pod's node for affinity.
      _ -> {:ok, node_name_of(pod)}
    end
  end

  defp node_name_of(%{"spec" => %{"nodeName" => node_name}}) when is_binary(node_name) and node_name != "", do: node_name

  defp node_name_of(_), do: nil

  defp pool_image(%{"spec" => %{"image" => image}}) when is_binary(image) and image != "", do: {:ok, image}
  defp pool_image(_), do: :error

  defp pod_image(%{"spec" => %{"containers" => [%{"image" => image} | _]}}) when is_binary(image) and image != "",
    do: {:ok, image}

  defp pod_image(_), do: :error

  # True when the controller has marked this Pod drain-eligible for the
  # current roll wave. Missing metadata/labels, or the label absent or
  # not "true", → false, so an unlabeled stale Pod is never 410'd.
  defp drain_eligible?(pod) do
    get_in(pod, ["metadata", "labels", @drain_eligible_label]) == "true"
  end
end
