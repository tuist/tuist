defmodule Tuist.Runners.Claims do
  @moduledoc """
  Postgres-backed claim coordination for the dispatch path. The
  table is **very thin** — one row per currently-claimed
  workflow_job, deleted on completion / release / stale recovery.

  Two responsibilities, both genuinely OLTP:

    1. **Atomic claim.** `attempt/5` runs the full check-and-set
       inside a single Postgres transaction. It inserts the
       uniqueness-sensitive reservation before acquiring a non-blocking
       advisory lock keyed on `(account_id, platform)`, so a unique-index
       wait cannot hold the account's admission lock. Once acquired, the
       lock covers only the resource aggregate, capacity decision, and
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

  ClickHouse `runner_jobs` is the customer-facing view (queued,
  running, completed, history). The two stores stay in sync via a
  one-way protocol: PG is the source of truth for "is this
  claimed and counted?" and every transition that flips that bit
  pairs the PG write with an INSERT to CH.

  Recovery: `list_stale/1` returns `claimed` claims older than the
  threshold WITHOUT deleting them; the stale-claims worker iterates
  the result, writes `queued` to ClickHouse first, then calls
  `release/2` to delete the PG row. CH-first is critical — if PG
  were deleted first and we crashed, the CH row would stay
  `claimed`, `Jobs.pick_queued` would skip it, and no PG claim
  would remain for the next worker run to recover, stranding the
  workflow_job permanently.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Concurrency

  @doc """
  Attempts to claim `workflow_job_id` for `pod_name` on behalf of
  `account_id`, consuming the requested platform resources. Runs
  check-and-set inside one Postgres transaction. The claim reservation
  is inserted before taking the non-blocking advisory lock on
  `(account_id, platform)`; the lock then serialises the capacity check
  through transaction completion:

  Returns one of:

    * `{:ok, %Claim{}}` — claim landed; caller should mint the
      JIT and call `mark_running/2` on success.
    * `{:error, :account_busy}` — another transaction is currently
      admitting work for this account and platform. The caller should
      try another account instead of waiting.
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
               :ok <- try_acquire_account_platform_lock(account.id, resources.platform),
               :ok <- check_reserved_capacity(account, resources) do
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

  defp try_acquire_account_platform_lock(account_id, platform) do
    lock_key = account_platform_lock_key(account_id, platform)

    case Repo.query("SELECT pg_try_advisory_xact_lock($1::bigint)", [lock_key]) do
      {:ok, %{rows: [[true]]}} -> :ok
      {:ok, %{rows: [[false]]}} -> {:error, :account_busy}
      {:error, reason} -> {:error, {:lock_failed, reason}}
    end
  end

  # Account IDs are positive bigint values. Mapping Linux to the positive
  # ID and macOS to its negative gives each platform a distinct,
  # collision-free lock key across the full account ID range.
  defp account_platform_lock_key(account_id, :linux), do: account_id
  defp account_platform_lock_key(account_id, :macos), do: -account_id

  defp fetch_account(account_id) do
    case Repo.get(Account, account_id) do
      nil -> {:error, :unknown_account}
      account -> {:ok, account}
    end
  end

  defp check_reserved_capacity(account, resources) do
    reserved = usage_for_platform(account.id, resources.platform)

    # The transaction sees its own reservation; preserve the `fits?/3`
    # contract by passing only the usage that existed before this claim.
    used = %{
      vcpus: reserved.vcpus - resources.vcpus,
      memory_gb: reserved.memory_gb - resources.memory_gb
    }

    limit = Concurrency.limits_for(account, resources.platform)

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

  defp usage_for_platform(account_id, platform) do
    {vcpus, memory_gb} =
      Repo.one(
        from(claim in Claim,
          where: claim.account_id == ^account_id and claim.platform == ^platform,
          select: {sum(claim.vcpus), sum(claim.memory_gb)}
        )
      )

    %{vcpus: vcpus || 0, memory_gb: memory_gb || 0}
  end

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
    {_count, _} =
      Repo.update_all(
        from(c in Claim, where: c.workflow_job_id == ^workflow_job_id and c.lifecycle_state == "claimed"),
        set: [lifecycle_state: "running", runner_name: runner_name]
      )

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
    {count, _} =
      Repo.delete_all(from(c in Claim, where: c.workflow_job_id == ^workflow_job_id and c.claimed_at == ^claimed_at))

    if count == 1, do: :ok, else: {:error, :stale_claim}
  end

  @doc """
  Deletes the claim for `workflow_job_id` regardless of handle.
  Called from the `workflow_job.completed` webhook to free the
  cap slot the instant GitHub tells us the job finished — without
  this the slot stays occupied until `StaleClaimsWorker` sweeps
  it (~5 min later), which is a real UX issue for a customer who
  just freed a slot and wants to claim the next workflow_job.

  Idempotent — repeated webhook deliveries are a no-op. Returns
  `:ok` whether or not a row existed.
  """
  def complete(workflow_job_id) when is_integer(workflow_job_id) do
    Repo.delete_all(from(c in Claim, where: c.workflow_job_id == ^workflow_job_id))
    :ok
  end

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
  Returns active claim workflow_job IDs for `fleet_name`.

  Dispatch uses this as an anti-list when selecting queued ClickHouse
  rows. If ClickHouse still says a job is queued while Postgres already
  has a live claim for it, that row must not pin the fleet's queue head.
  """
  def workflow_job_ids_for_fleet(fleet_name) when is_binary(fleet_name) do
    Repo.all(from(c in Claim, where: c.fleet_name == ^fleet_name, select: c.workflow_job_id))
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
  uses this to recover row-by-row: for each stale claim it FIRST
  writes `queued` to ClickHouse, THEN calls `release/2` with the
  handle to delete the PG row. Reversing that order would leave a
  window where the PG row is gone but CH still shows `claimed` —
  `pick_queued` would skip the row and no PG claim would remain
  for the next worker run to recover, stranding the workflow_job
  permanently.

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
  Resolves the live claim (`claimed` or `running`) owning `pod_name`
  to its `workflow_job_id` and `account_id`. The metrics ingest
  endpoint uses this to map a sampled Pod back to the job it's running,
  so the runners-controller can POST samples keyed by Pod name without
  knowing job ids. Returns `:error` when the Pod holds no live claim
  (an idle/warm Pod, or one whose job already released its claim).
  """
  def by_pod_name(pod_name) when is_binary(pod_name) do
    Claim
    |> where([c], c.pod_name == ^pod_name)
    |> select([c], %{workflow_job_id: c.workflow_job_id, account_id: c.account_id})
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> :error
      claim -> {:ok, claim}
    end
  end
end
