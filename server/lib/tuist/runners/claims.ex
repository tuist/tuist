defmodule Tuist.Runners.Claims do
  @moduledoc """
  Postgres-backed claim coordination for the dispatch path. The
  table is **very thin** — one row per currently-claimed
  workflow_job, deleted on completion / release / stale recovery.

  Two responsibilities, both genuinely OLTP:

    1. **Atomic claim.** `attempt/5` runs the full check-and-set
       inside a single Postgres transaction. It inserts the
       uniqueness-sensitive reservation before acquiring a non-blocking
       row lock on the account's platform limit, so a unique-index wait
       cannot hold the account's admission lock. Once acquired, the lock
       covers only the resource aggregate, capacity decision, and
       transaction completion:

         * platform resource-limit check against the account's
           vCPU and memory budgets and this platform's live claims
         * the `workflow_job_id` primary key collapses concurrent
           attempts for the same job
         * the unique `pod_name` index prevents one Pod from owning
           two live claims, including attempts spanning accounts or
           platforms

       A busy lock returns immediately so one account cannot fill the
       database pool with waiting transactions. The dispatcher skips
       that account for the current poll and considers other work.

    2. **Per-account inflight count.** `counts_per_account/0` is
       a single indexed `GROUP BY account_id` against this table
       — a cheap read of how many runners each account is
       currently using, across all fleets.

  Lifecycle column (`lifecycle_state`):

    * `claimed` — INSERTed by `attempt/5`, pre-mint. Stale
      reaper targets these.
    * `running` — set by `mark_running/2` once the JIT mint
      lands and we're handing the runner to GitHub. A
      long-running build holds this slot until
      `workflow_job.completed` (or its webhook arrives) calls
      `complete/1`. Stale reaper never touches `running` rows;
      they're healthy cap accounting, not stuck claims.

  The claim row sits next to the workflow_job lifecycle row
  (`Tuist.Runners.WorkflowJobs`), and every claim mutation carries
  the matching lifecycle transition in the same transaction:
  `attempt/5` moves the row `queued → claimed`, `mark_running/2`
  `claimed → running`, and the release paths move it back to
  `queued`. There is no cross-store ordering to get right — a
  release either fully returns the job to the queue or does nothing.

  Recovery: `list_stale/1` returns `claimed` claims older than the
  threshold WITHOUT deleting them; the stale-claims worker calls
  `release/2` per row, which deletes the claim and re-queues the
  lifecycle row atomically.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.WorkflowJobs

  @doc """
  Attempts to claim `workflow_job_id` for `pod_name` on behalf of
  `account_id`, consuming the requested platform resources. Runs
  check-and-set inside one Postgres transaction. The claim reservation
  is inserted before taking a non-blocking row lock on the account's
  platform limit; the lock then serialises the capacity check through
  transaction completion:

  Returns one of:

    * `{:ok, %Claim{}}` — claim landed; caller should mint the
      JIT and call `mark_running/2` on success.
    * `{:error, :account_busy}` — another transaction is currently
      admitting work for this account and platform. The caller should
      try another account instead of waiting.
    * `{:error, :concurrency_limit_missing}` — the account's platform
      limit invariant is broken and admission cannot proceed safely.
    * `{:error, :lost_race}` — another pod beat us to the
      `workflow_job_id` PK.
    * `{:error, {:concurrency_limit_reached, details}}` — adding the
      requested shape would exceed either the platform's vCPU or
      memory limit.
    * `{:error, :pod_in_use}` — `pod_name` already owns a live
      claim. Closes the SA-token-reuse path.
  """
  def attempt(workflow_job_id, account_id, fleet_name, pod_name, resources) do
    with :ok <- validate_claim_inputs(workflow_job_id, account_id, fleet_name, pod_name, resources),
         :ok <- validate_resources(resources) do
      Repo.transaction(fn ->
        result =
          with {:ok, account} <- fetch_account(account_id),
               {:ok, claim} <- insert_claim(workflow_job_id, account.id, fleet_name, pod_name, resources),
               {:ok, limit} <- try_lock_concurrency_limit(account.id, resources.platform),
               :ok <- check_reserved_capacity(account.id, limit, resources) do
            # Same transaction as the claim insert, so the claim and
            # the lifecycle row's `queued → claimed` commit or roll
            # back together. `:noop` (row missing or not queued) never
            # fails the claim — a completion that raced the claim wins
            # and the caller's post-claim completion guard releases.
            WorkflowJobs.transition_claimed(claim.workflow_job_id, claim.pod_name, claim.claimed_at)
            {:ok, claim}
          end

        case result do
          {:ok, claim} -> claim
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  defp validate_claim_inputs(workflow_job_id, account_id, fleet_name, pod_name, resources) do
    valid? =
      Enum.all?([
        positive_integer?(workflow_job_id),
        positive_integer?(account_id),
        non_empty_binary?(fleet_name),
        non_empty_binary?(pod_name),
        is_map(resources)
      ])

    if valid?, do: :ok, else: {:error, :invalid_resources}
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_empty_binary?(value), do: is_binary(value) and value != ""

  defp try_lock_concurrency_limit(account_id, platform) do
    limit_query =
      from(limit in ConcurrencyLimit,
        where: limit.account_id == ^account_id and limit.platform == ^platform
      )

    case Repo.one(from(limit in limit_query, lock: "FOR UPDATE SKIP LOCKED")) do
      %ConcurrencyLimit{} = limit ->
        {:ok, limit}

      nil ->
        if Repo.exists?(limit_query) do
          {:error, :account_busy}
        else
          {:error, :concurrency_limit_missing}
        end
    end
  end

  defp fetch_account(account_id) do
    case Repo.get(Account, account_id) do
      nil -> {:error, :unknown_account}
      account -> {:ok, account}
    end
  end

  defp check_reserved_capacity(account_id, limit, resources) do
    with {:ok, reserved} <- usage_for_platform(account_id, resources.platform) do
      # The transaction sees its own reservation; preserve the `fits?/3`
      # contract by passing only the usage that existed before this claim.
      used = %{
        vcpus: reserved.vcpus - resources.vcpus,
        memory_gb: reserved.memory_gb - resources.memory_gb
      }

      limit = Concurrency.limit_resources(limit)

      if Concurrency.fits?(used, limit, resources) do
        :ok
      else
        {:error,
         {:concurrency_limit_reached,
          %{
            platform: resources.platform,
            requested: resources,
            used: used,
            limit: limit
          }}}
      end
    end
  end

  defp usage_for_platform(account_id, platform) do
    Claim
    |> where([claim], claim.account_id == ^account_id)
    |> select([claim], %{
      fleet_name: claim.fleet_name,
      platform: claim.platform,
      vcpus: claim.vcpus,
      memory_gb: claim.memory_gb
    })
    |> Repo.all()
    |> Enum.reduce_while({:ok, %{vcpus: 0, memory_gb: 0}}, fn claim, {:ok, usage} ->
      case resources_for_claim(claim) do
        {:ok, %{platform: ^platform} = resources} ->
          {:cont,
           {:ok,
            %{
              vcpus: usage.vcpus + resources.vcpus,
              memory_gb: usage.memory_gb + resources.memory_gb
            }}}

        {:ok, _other_platform} ->
          {:cont, {:ok, usage}}

        {:error, :invalid_resources} = error ->
          {:halt, error}
      end
    end)
  end

  defp resources_for_claim(%{platform: platform, vcpus: vcpus, memory_gb: memory_gb})
       when platform in [:linux, :macos] and vcpus > 0 and memory_gb > 0 do
    {:ok, %{platform: platform, vcpus: vcpus, memory_gb: memory_gb}}
  end

  defp resources_for_claim(%{fleet_name: fleet_name}), do: Catalog.resources_for_fleet(fleet_name)

  defp insert_claim(workflow_job_id, account_id, fleet_name, pod_name, resources) do
    now = DateTime.utc_now()

    {count, rows} =
      Repo.insert_all(
        Claim,
        [
          %{
            workflow_job_id: workflow_job_id,
            account_id: account_id,
            fleet_name: fleet_name,
            pod_name: pod_name,
            claimed_at: now,
            platform: resources.platform,
            vcpus: resources.vcpus,
            memory_gb: resources.memory_gb,
            lifecycle_state: "claimed",
            runner_name: ""
          }
        ],
        on_conflict: :nothing,
        returning: [
          :workflow_job_id,
          :account_id,
          :fleet_name,
          :pod_name,
          :claimed_at,
          :platform,
          :vcpus,
          :memory_gb,
          :lifecycle_state,
          :runner_name
        ]
      )

    case count do
      0 -> claim_conflict(workflow_job_id, pod_name)
      1 -> {:ok, struct(Claim, Map.from_struct(hd(rows)))}
    end
  end

  defp claim_conflict(workflow_job_id, pod_name) do
    cond do
      Repo.exists?(from(claim in Claim, where: claim.workflow_job_id == ^workflow_job_id)) ->
        {:error, :lost_race}

      Repo.exists?(from(claim in Claim, where: claim.pod_name == ^pod_name)) ->
        {:error, :pod_in_use}

      true ->
        {:error, :lost_race}
    end
  end

  defp validate_resources(%{platform: platform, vcpus: vcpus, memory_gb: memory_gb}) when platform in [:linux, :macos] do
    if Enum.all?([vcpus, memory_gb], &(is_integer(&1) and &1 > 0)),
      do: :ok,
      else: {:error, :invalid_resources}
  end

  defp validate_resources(_resources), do: {:error, :invalid_resources}

  @doc """
  Promotes a `claimed` claim to `running`. Called after the JIT
  mint succeeds, before we hand the encoded config back to the
  polling Pod. Once `running`, the row is no longer a candidate
  for the stale reaper — it's an active cap slot for a healthy
  build.

  Returns `:ok` whether or not the row is still around (the
  `workflow_job.completed` webhook can arrive between mint and
  the call to `mark_running/2`, deleting the row out from
  under us).
  """
  def mark_running(workflow_job_id, runner_name) when is_integer(workflow_job_id) and is_binary(runner_name) do
    {:ok, _} =
      Repo.transaction(fn ->
        {_count, _} =
          Repo.update_all(
            from(c in Claim, where: c.workflow_job_id == ^workflow_job_id and c.lifecycle_state == "claimed"),
            set: [lifecycle_state: "running", runner_name: runner_name]
          )

        WorkflowJobs.transition_running(workflow_job_id, runner_name)
      end)

    :ok
  end

  @doc """
  Releases the claim for `workflow_job_id` — DELETE'd from PG.
  The `claimed_at` argument is the claim handle returned by
  `attempt/5`; the DELETE filters on it so a stale serve whose
  PG row was already deleted by the stale-claims worker (and
  then re-claimed by a different poll) doesn't delete the second
  claim's row out from under it.

  Returns `:ok` on success, `{:error, :stale_claim}` if the row
  is gone or its `claimed_at` has moved on.
  """
  def release(workflow_job_id, %DateTime{} = claimed_at) when is_integer(workflow_job_id) do
    {:ok, outcome} =
      Repo.transaction(fn ->
        {count, _} =
          Repo.delete_all(from(c in Claim, where: c.workflow_job_id == ^workflow_job_id and c.claimed_at == ^claimed_at))

        # The lifecycle row re-queues in the same transaction as the
        # claim delete, so claim and row state cannot diverge across
        # a crash. Terminal rows never match `requeue/1`'s guard and
        # stay completed.
        if count == 1 do
          WorkflowJobs.requeue(workflow_job_id)
          :ok
        else
          {:error, :stale_claim}
        end
      end)

    outcome
  end

  @doc """
  Deletes the claim for `workflow_job_id` regardless of handle.

  **Recovery path only.** This releases the claim of whichever Pod
  *claimed* the job, which is not necessarily the Pod that *ran* it —
  GitHub assigns jobs to any label-eligible runner. The completed
  webhook must therefore NOT use this (see `complete_by_runner_name/1`);
  it exists for `OrphanedRunnersWorker`, where a GitHub-side terminal
  status has already proven the claim is stale and the slot is leaked.

  Idempotent — repeated deliveries are a no-op. Returns `:ok` whether
  or not a row existed.
  """
  def complete(workflow_job_id) when is_integer(workflow_job_id) do
    Repo.delete_all(from(c in Claim, where: c.workflow_job_id == ^workflow_job_id))
    :ok
  end

  @doc """
  Deletes claims with nothing left to run: every workflow_job attached to
  the claim has a recorded completion, and `claimed_at` predates
  `threshold`. Returns the row count.

  A `runner_job_completions` row is proof a job is over. It is written
  from the `workflow_job.completed` webhook, the same handler that
  releases the claim, so a claim still present alongside one is a slot
  held for work that finished. Every other recovery path is blind to it:

    * `list_stale/1` filters `lifecycle_state = 'claimed'`, and these
      sit in `running`.
    * `OrphanedRunnersWorker` drives off lifecycle rows still in
      `status = 'running'`. The completion already moved the row out of
      that state, so the scan never returns it.

  That leaves the row consuming the account's concurrency budget
  permanently. Because a completion is independent proof rather than a
  timeout, this can safely release `running` claims that the time-based
  sweep must not touch.

  ## Why the claimed job alone is not enough

  GitHub hands a queued job to any label-eligible runner, so the Pod that
  *claimed* job A is often executing job B (`executed_workflow_job_id`,
  learned from `workflow_job.in_progress`). Keying release on the claimed
  job's completion alone would delete a live runner's reservation the
  moment A finished elsewhere, pushing the account over cap while B is
  still running. This is the same trap `complete/1` warns about and that
  `executing?/1` guards for the queued-side recovery.

  So the claim is released only when the claimed job AND the executed job
  (when the runner took one) are both complete. A runner minted for a
  single-shot JIT runs at most one job, so those two cover everything the
  claim can be holding the slot for.

  `threshold` only avoids racing the webhook's own release between the
  completion insert and the delete; it is not the staleness signal.
  """
  def release_completed(%DateTime{} = threshold) do
    completed = from(completion in JobCompletion, select: completion.workflow_job_id)

    {count, _} =
      Repo.delete_all(
        from(c in Claim,
          where: c.claimed_at < ^threshold,
          where: c.workflow_job_id in subquery(completed),
          where:
            is_nil(c.executed_workflow_job_id) or
              c.executed_workflow_job_id in subquery(completed)
        )
      )

    count
  end

  @doc """
  Releases the claim held by the runner that GitHub says actually ran
  the job — keyed by the `runner_name` on the `workflow_job.completed`
  payload, not by the completed job's id.

  Job-keyed release is wrong under the claim↔execution mismatch: if Pod
  A claimed J1 and Pod B claimed J2, but GitHub ran J1 on B, then
  releasing on J2's completion would free B's slot while B is still
  executing J1 — the account's budget would under-count a live runner
  and admit work above its limit. Releasing by executor frees exactly
  the runner that finished, whichever job it was minted for.

  A job cancelled while still queued carries no `runner_name` (no
  runner ever ran it); nothing is released, because the Pod that
  claimed it is still alive and may still be handed a sibling job. Its
  slot is reclaimed when that Pod stops (idle timeout / scale-down) or
  by `OrphanedRunnersWorker`.

  Idempotent. Returns the number of claims released.
  """
  def complete_by_runner_name(runner_name, account_id)
      when is_binary(runner_name) and runner_name != "" and is_integer(account_id) do
    {count, _} =
      Repo.delete_all(from(c in Claim, where: c.runner_name == ^runner_name and c.account_id == ^account_id))

    count
  end

  def complete_by_runner_name(_runner_name, _account_id), do: 0

  @doc """
  Releases the claim held by `pod_name` — DELETE'd from PG,
  regardless of lifecycle state or which workflow_job it was minted
  for. Called when the runners-controller reports the Pod stopped.

  A stopped Pod consumes no capacity, so its claim must not keep
  charging the account's concurrency budget. This is the release
  path for the claim↔execution mismatch: a Pod stranded because
  GitHub ran its claimed job on a *different* eligible runner keeps
  a `running` claim that neither the completed webhook (that job
  completes elsewhere) nor `OrphanedRunnersWorker` (GitHub reports
  the job `in_progress`, so it's left alone) will free — until the
  Pod stops. We deliberately do NOT re-queue here: a job whose
  runner vanished mid-flight is re-queued by GitHub itself (a fresh
  `queued` webhook), and a job that already ran elsewhere is
  finalized by its own `completed` webhook.

  Returns the number of claims released (0 in the common case where
  the job's `completed` webhook already freed the claim before the
  Pod halted; ≥1 only for a stranded or crashed-mid-job Pod).
  """
  def release_by_pod_name(pod_name) when is_binary(pod_name) and pod_name != "" do
    {count, _} = Repo.delete_all(from(c in Claim, where: c.pod_name == ^pod_name))
    count
  end

  def release_by_pod_name(_pod_name), do: 0

  @doc """
  Counts active claims per fleet **across all accounts**. Returns
  `%{fleet_name => count}`. Powers the autoscaler's view of "how
  many Pods are currently busy" for a given pool — combined with
  the queued count from ClickHouse and the rolling p95 of
  concurrent load, the controller decides the desired replica
  count.

  Counts `claimed` + `running` together — both occupy a Pod and
  must be reflected as busy capacity when sizing the warm pool.
  """
  def counts_per_fleet do
    from(c in Claim,
      group_by: c.fleet_name,
      select: {c.fleet_name, count(c.workflow_job_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Counts active claims per account **across all fleets**. Returns
  `%{account_id => count}` — how many runners each account is
  currently using. Not fleet-scoped: an account's jobs spread
  across pools all roll up to one per-account total.

  Counts `claimed` and `running` together — both occupy a Pod.
  The lifecycle distinction matters for the stale reaper, not
  for this rollup.
  """
  def counts_per_account do
    from(c in Claim,
      group_by: c.account_id,
      select: {c.account_id, count(c.workflow_job_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns claims still in `lifecycle_state = 'claimed'` and older
  than `threshold` without deleting them. The stale-claims worker
  recovers row-by-row via `release/2` with the `claimed_at` handle —
  each release deletes the claim and re-queues the lifecycle row in
  one transaction, so a partial recovery cannot strand a job.

  `running` rows are deliberately excluded: a build running for
  hours is healthy, not stuck mid-mint. Reaping it here would
  free the cap slot for an already-active GitHub runner and
  over-schedule the account.
  """
  def list_stale(%DateTime{} = threshold) do
    Repo.all(
      from(c in Claim,
        where: c.lifecycle_state == "claimed" and c.claimed_at < ^threshold,
        select: %{
          workflow_job_id: c.workflow_job_id,
          account_id: c.account_id,
          fleet_name: c.fleet_name,
          claimed_at: c.claimed_at
        }
      )
    )
  end

  @doc """
  Returns the set of `pod_name`s that currently hold a live claim
  (`claimed` or `running`). `OrphanedStampedPodsWorker` diffs the
  owner-stamped Pods in Kubernetes against this set: a stamped Pod
  absent here has no claim backing its label and is therefore a
  leak the runner-pool reconciler can't see (the reconciler only
  reaps idle, un-stamped Pods).
  """
  def live_pod_names do
    from(c in Claim, select: c.pod_name, distinct: true)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Resolves the live claim (`claimed` or `running`) owning `pod_name` to
  the workflow_job it was minted for, plus its account and fleet.
  Interactive access (terminal / VNC) uses it to reconcile the
  customer-facing job view against the Pod that actually holds the claim.

  Note this answers with the **claimed** job, which is not necessarily
  the one the Pod is running: GitHub assigns a queued job to any
  label-eligible runner. Anything that must follow real execution (e.g.
  machine metrics) uses `RunnerSessions.executed_job_for_pod/1`, which
  only answers once GitHub has proven the binding.

  Returns `:error` when the Pod holds no live claim (an idle/warm Pod,
  or one whose job already released its claim).
  """
  def by_pod_name(pod_name) when is_binary(pod_name) do
    Claim
    |> where([c], c.pod_name == ^pod_name)
    |> select([c], %{
      workflow_job_id: c.workflow_job_id,
      account_id: c.account_id,
      fleet_name: c.fleet_name,
      pod_name: c.pod_name
    })
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> :error
      claim -> {:ok, claim}
    end
  end

  @doc """
  Resolves the live claim for `workflow_job_id`.

  This is the OLTP source of truth for which Pod currently owns a runner
  job. ClickHouse can lag or briefly carry an older lifecycle row, so
  interactive access uses this to reconcile the customer-facing job view
  with the actual claimed Pod before opening a terminal or VNC relay.
  """
  def by_workflow_job_id(workflow_job_id) when is_integer(workflow_job_id) do
    Claim
    |> where([c], c.workflow_job_id == ^workflow_job_id)
    |> select([c], %{
      workflow_job_id: c.workflow_job_id,
      account_id: c.account_id,
      fleet_name: c.fleet_name,
      pod_name: c.pod_name
    })
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> :error
      claim -> {:ok, claim}
    end
  end

  @doc """
  Claims eligible for Pod reconciliation: older than `grace_threshold`.

  The grace window is a correctness requirement, not tuning. A claim is
  inserted before its Pod carries the owner label, and the cluster read
  is eventually consistent, so a just-claimed Pod can legitimately be
  absent from an otherwise complete listing.
  """
  def list_for_pod_reconciliation(%DateTime{} = grace_threshold) do
    Repo.all(
      from(c in Claim,
        where: c.claimed_at < ^grace_threshold and c.pod_name != "",
        select: %{
          workflow_job_id: c.workflow_job_id,
          pod_name: c.pod_name,
          pod_missing_since: c.pod_missing_since
        }
      )
    )
  end

  @doc """
  Stamps `pod_missing_since` on claims whose Pod was absent this tick,
  leaving an existing stamp alone so the clock measures the FIRST
  observed absence rather than the most recent one.
  """
  def mark_pods_missing([], _now), do: 0

  def mark_pods_missing(workflow_job_ids, %DateTime{} = now) when is_list(workflow_job_ids) do
    {count, _} =
      Repo.update_all(
        from(c in Claim,
          where: c.workflow_job_id in ^workflow_job_ids and is_nil(c.pod_missing_since)
        ),
        set: [pod_missing_since: now]
      )

    count
  end

  @doc """
  Clears `pod_missing_since` for claims whose Pod is present again.

  A Pod that reappears resets the clock: absence has to be *consecutive*
  to count, so an intermittently-visible Pod never accumulates its way to
  a release.
  """
  def clear_pods_missing([]), do: 0

  def clear_pods_missing(workflow_job_ids) when is_list(workflow_job_ids) do
    {count, _} =
      Repo.update_all(
        from(c in Claim,
          where: c.workflow_job_id in ^workflow_job_ids and not is_nil(c.pod_missing_since)
        ),
        set: [pod_missing_since: nil]
      )

    count
  end

  @doc """
  Candidates for release: claims whose Pod has been continuously absent
  since before `confirmed_before`, at most `limit` per call.

  Returns the rows WITHOUT deleting them, carrying `pod_missing_since` as
  the release handle. A claim is capacity held by a Pod, and with no Pod
  there is no runner and no capacity; `release_pod_missing/2` deletes the
  claim and re-queues the lifecycle row in one transaction so the job is
  immediately claimable again.

  The `limit` bounds the blast radius of a wrong-but-plausible cluster
  read that survives the caller's checks. Anything above it waits for the
  next tick, and the caller reports the overflow.
  """
  def list_pods_missing_since(%DateTime{} = confirmed_before, limit) when is_integer(limit) and limit > 0 do
    Repo.all(
      from(c in Claim,
        where: not is_nil(c.pod_missing_since) and c.pod_missing_since < ^confirmed_before,
        order_by: [asc: c.pod_missing_since],
        limit: ^limit,
        select: %{
          workflow_job_id: c.workflow_job_id,
          pod_missing_since: c.pod_missing_since
        }
      )
    )
  end

  @doc """
  Releases one claim selected by `list_pods_missing_since/2`, keyed on
  the `pod_missing_since` handle it was selected with.

  The handle closes a stale-delete race. Between selection and delete,
  another path can release the row and the same workflow_job be
  re-claimed by a live Pod; deleting by id alone would drop that fresh
  claim. A re-claimed row carries a NULL `pod_missing_since`, so the
  handle no longer matches and nothing is deleted. Same reason `release/2`
  keys on `claimed_at`.
  """
  def release_pod_missing(workflow_job_id, %DateTime{} = pod_missing_since) when is_integer(workflow_job_id) do
    {:ok, outcome} =
      Repo.transaction(fn ->
        {count, _} =
          Repo.delete_all(
            from(c in Claim,
              where: c.workflow_job_id == ^workflow_job_id and c.pod_missing_since == ^pod_missing_since
            )
          )

        if count == 1 do
          WorkflowJobs.requeue(workflow_job_id)
          :ok
        else
          {:error, :stale_claim}
        end
      end)

    outcome
  end

  @doc """
  Count of claims eligible for release right now, ignoring the per-tick
  limit. The reconciler reports the difference so a sustained backlog is
  visible instead of silently trickling.
  """
  def count_pods_missing_since(%DateTime{} = confirmed_before) do
    Repo.aggregate(
      from(c in Claim, where: not is_nil(c.pod_missing_since) and c.pod_missing_since < ^confirmed_before),
      :count
    )
  end

  @doc """
  Whether the runner holding the claim for `workflow_job_id` has been
  proven to be executing some job — i.e. `executed_workflow_job_id` is
  set, whichever job it turned out to be.

  This is the busy signal for recovery paths that would otherwise judge a
  claim by its *claimed* job's GitHub status: a runner can be hard at work
  on a sibling's job while the job it was minted for still sits queued.
  Releasing such a claim would delete a live runner's reservation mid-job.
  """
  def executing?(workflow_job_id) when is_integer(workflow_job_id) do
    Repo.exists?(
      from(c in Claim,
        where: c.workflow_job_id == ^workflow_job_id and not is_nil(c.executed_workflow_job_id)
      )
    )
  end

  @doc """
  Records the workflow_job GitHub actually placed on the runner named
  `runner_name`, learned from the `workflow_job.in_progress` /
  `completed` webhook. The mint-chosen `runner_name` is unique per
  runner and stored on the claim at `mark_running/2`, so it resolves
  the live claim regardless of which job the claim was minted for.

  Scoped to `account_id` (resolved from the webhook's App installation):
  a runner name is only ours to act on within the account that minted
  it, since every other account controls the names of its own
  self-hosted runners.

  Idempotent: repeated deliveries set the same value. Returns which
  of the three attribution outcomes occurred so the webhook path can
  emit it as telemetry:

    * `:matched` — GitHub ran the job the claim was minted for.
    * `:mismatch` — GitHub ran a *different* job on this runner than
      the one claimed (the claim↔execution mismatch we're measuring).
    * `:unknown_runner` — no live claim carries this `runner_name`
      (a dropped/late webhook, or the claim already completed). The
      durable session binding is the backstop for this case.
  """
  def record_execution(runner_name, executed_workflow_job_id, account_id)
      when is_binary(runner_name) and runner_name != "" and is_integer(executed_workflow_job_id) and
             is_integer(account_id) do
    claim =
      Claim
      |> where([c], c.runner_name == ^runner_name and c.account_id == ^account_id)
      |> limit(1)
      |> Repo.one()

    case claim do
      nil ->
        :unknown_runner

      %Claim{workflow_job_id: claimed_job_id} ->
        Repo.update_all(
          from(c in Claim, where: c.runner_name == ^runner_name and c.account_id == ^account_id),
          set: [executed_workflow_job_id: executed_workflow_job_id]
        )

        if claimed_job_id == executed_workflow_job_id, do: :matched, else: :mismatch
    end
  end

  def record_execution(_runner_name, _executed_workflow_job_id, _account_id), do: :unknown_runner
end
