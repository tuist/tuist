defmodule Tuist.Runners.Claims do
  @moduledoc """
  Postgres-backed claim coordination for the dispatch path. The
  table is **very thin** — one row per currently-claimed
  workflow_job, deleted on completion / release / stale recovery.

  Two responsibilities, both genuinely OLTP:

    1. **Atomic claim.** `attempt/4` runs the full check-and-set
       inside a single Postgres transaction, holding an
       advisory lock keyed on `account_id` for the duration:

         * cap re-check against `accounts.runner_max_concurrent`
           and a SELECT count(*) over this account's live rows
         * pod-in-use rejection if the polling Pod already owns
           a live claim (defends against the SA-token reuse
           attack: customer workflow code can read
           `/etc/tuist-sa-token` and call dispatch a second
           time; the active claim makes the second attempt
           fail-closed)
         * `INSERT … ON CONFLICT (workflow_job_id) DO NOTHING`
           collapses concurrent attempts for the same job;
           the loser sees zero rows and bails with `:lost_race`

       The advisory lock is the bit that makes the cap atomic
       across pollers in different fleets — two warm pods for
       the same account can't both pass the count check and
       INSERT in parallel because they serialise on the lock.

    2. **Per-account cap count.** `counts_per_account/0` is a
       single indexed `GROUP BY account_id` against this table.
       Cap is account-level (NOT fleet-level), so this query
       does not filter by fleet — an account at cap=1 can't run
       one job per pool.

  Lifecycle column (`lifecycle_state`):

    * `claimed` — INSERTed by `attempt/4`, pre-mint. Stale
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

  require Logger

  # Postgres advisory locks accept a single 64-bit int or two
  # 32-bit ints. Using the two-int form lets us namespace by a
  # constant so we don't collide with other advisory-lock users
  # in the same DB. `runner_claim_account_lock` truncated to 32
  # bits.
  @claim_lock_namespace 0x52434C4B

  @doc """
  Attempts to claim `workflow_job_id` for `pod_name` on behalf of
  `account_id`. Runs check-and-set inside one Postgres transaction
  with an advisory lock on `account_id`:

  Returns one of:

    * `{:ok, %Claim{}}` — claim landed; caller should mint the
      JIT and call `mark_running/2` on success.
    * `{:error, :lost_race}` — another pod beat us to the
      `workflow_job_id` PK.
    * `{:error, :over_cap}` — account is already at
      `runner_max_concurrent`.
    * `{:error, :runners_disabled}` — account's
      `runner_max_concurrent` is 0 or nil. Cap-check fires
      even if dispatch let the candidate through, in case ops
      flipped the knob between webhook arrival and claim.
    * `{:error, :pod_in_use}` — `pod_name` already owns a live
      claim. Closes the SA-token-reuse path.
    * `{:error, :unknown_account}` — `account_id` has no row.
  """
  def attempt(workflow_job_id, account_id, fleet_name, pod_name)
      when is_integer(workflow_job_id) and is_integer(account_id) and is_binary(fleet_name) and is_binary(pod_name) do
    Repo.transaction(fn ->
      with :ok <- acquire_account_lock(account_id),
           {:ok, cap} <- fetch_cap(account_id),
           :ok <- check_cap(account_id, cap),
           :ok <- check_pod_not_in_use(pod_name) do
        case insert_claim(workflow_job_id, account_id, fleet_name, pod_name) do
          {:ok, claim} -> claim
          {:error, :lost_race} -> Repo.rollback(:lost_race)
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp acquire_account_lock(account_id) do
    # `pg_advisory_xact_lock` is released automatically on
    # COMMIT/ROLLBACK — no need to track release ourselves.
    case Repo.query("SELECT pg_advisory_xact_lock($1, $2)", [@claim_lock_namespace, account_id]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:lock_failed, reason}}
    end
  end

  defp fetch_cap(account_id) do
    case Repo.one(from(a in Account, where: a.id == ^account_id, select: a.runner_max_concurrent)) do
      nil -> {:error, :unknown_account}
      cap -> {:ok, cap}
    end
  end

  defp check_cap(_account_id, cap) when is_nil(cap) or cap <= 0, do: {:error, :runners_disabled}

  defp check_cap(account_id, cap) when is_integer(cap) and cap > 0 do
    inflight = Repo.one(from(c in Claim, where: c.account_id == ^account_id, select: count(c.workflow_job_id)))
    if inflight >= cap, do: {:error, :over_cap}, else: :ok
  end

  defp check_pod_not_in_use(pod_name) do
    case Repo.one(from(c in Claim, where: c.pod_name == ^pod_name, select: c.workflow_job_id, limit: 1)) do
      nil -> :ok
      _ -> {:error, :pod_in_use}
    end
  end

  defp insert_claim(workflow_job_id, account_id, fleet_name, pod_name) do
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
            lifecycle_state: "claimed",
            runner_name: ""
          }
        ],
        on_conflict: :nothing,
        conflict_target: :workflow_job_id,
        returning: [
          :workflow_job_id,
          :account_id,
          :fleet_name,
          :pod_name,
          :claimed_at,
          :lifecycle_state,
          :runner_name
        ]
      )

    case count do
      0 -> {:error, :lost_race}
      1 -> {:ok, struct(Claim, Map.from_struct(hd(rows)))}
    end
  end

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
  `attempt/4`; the DELETE filters on it so a stale serve whose
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
  Counts active claims per account **across all fleets**. Returns
  `%{account_id => count}`. Powers the cap_lookup the dispatch
  path builds before each claim attempt.

  Cap is account-level — `accounts.runner_max_concurrent` is the
  customer's total concurrent runner budget across every pool
  they reach. If we filtered by fleet, an account at cap=1 could
  run one job per pool simultaneously (one in `default`, one in
  `xcode-15`, etc.), breaching the contract.

  Counts `claimed` and `running` together — both occupy a cap
  slot. The lifecycle distinction matters for the stale reaper,
  not for cap accounting.
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
end
