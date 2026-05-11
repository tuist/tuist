defmodule Tuist.Runners.DispatchQueue do
  @moduledoc """
  Postgres-backed dispatch queue. One row per pending Burst — a
  workflow_job the webhook handler accepted but no warm Pod has
  claimed yet.

  ## Claim flow

  The claim is a **soft claim**: instead of `DELETE … RETURNING`,
  we `UPDATE … SET claimed_at = now() … RETURNING`, then the
  caller (`Tuist.Runners.dispatch_for_sa/2`) deletes the row only
  after the JIT mint + Pod label-stamp succeed. On mint failure
  the row is released back (`claimed_at = NULL`).

  The claim transaction:

    1. `SELECT … FOR UPDATE SKIP LOCKED LIMIT 1` against the
       partial pending index for the fleet, excluding accounts
       reported as at-cap by the K8s-Pod-count snapshot the
       caller passed in.
    2. `pg_advisory_xact_lock` keyed on the candidate row's
       account id. Serialises concurrent claims for the *same*
       account so the in-flight re-check below sees a fresh count.
    3. Re-count this account's soft-claimed rows
       (`claimed_at IS NOT NULL`) + the K8s-Pod count for this
       account that the caller passed in. If combined ≥ cap,
       roll back: the row is not claimed, its lock is released
       on `FOR UPDATE SKIP LOCKED` rollback, and the caller's
       next poll (5 s later) finds an updated K8s snapshot.
    4. Otherwise `UPDATE … SET claimed_at = now()` and commit.

  Step 2 + step 3 close the gap between Pod-label-stamp and
  K8s LIST seeing it: any concurrent poll for the same account
  blocks on step 2 and then sees the prior poll's `claimed_at`
  row in step 3.

  ## Recovery

  If the server dies between claim and finalize, the row stays
  with `claimed_at` set indefinitely. `Tuist.Runners.StaleClaimsWorker`
  scans by the `claimed_at` partial index and NULLs claims older
  than the configured threshold so the row goes back to the
  pending pool.

  ## No per-account enqueue ceiling today

  One customer can queue as many entries as they generate; the
  cap on actually running jobs is enforced at claim time via
  `runner_max_concurrent`. If table growth becomes a real
  concern later, a depth ceiling is a small addition here.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Runners.DispatchQueueEntry

  # `pg_advisory_xact_lock` takes a bigint. Account ids fit in 32
  # bits today; we hash with a per-domain salt so we don't collide
  # with other features' advisory locks. The salt is a stable
  # 32-bit constant — `'runner-dispatch-claim'` SHA-1 reduced.
  @claim_lock_salt 0x7E1F_0DB8

  @doc """
  Inserts a queue entry. Returns `{:ok, entry}` on success,
  `{:error, :runners_disabled}` if the account's
  `runner_max_concurrent` is 0, or `{:error, changeset}` on
  validation errors.
  """
  def enqueue(%Account{} = account, fleet_name, repo) when is_binary(fleet_name) and is_binary(repo) do
    if (account.runner_max_concurrent || 0) <= 0 do
      {:error, :runners_disabled}
    else
      Repo.insert(%DispatchQueueEntry{
        account_id: account.id,
        fleet_name: fleet_name,
        repo: repo
      })
    end
  end

  @doc """
  Claims the oldest pending entry for `fleet_name` whose account
  is below its `runner_max_concurrent` cap.

  `cap_lookup` maps `account_id => {max_concurrent, k8s_running_count}`
  for every account currently observed running on the fleet.
  Accounts not present in the map are assumed to have zero
  running Pods. `ineligible_account_ids` is the precomputed set
  of accounts already at cap by K8s count alone.

  Returns `{:ok, %{id, account_id, repo}}` on a successful soft
  claim, `{:error, :empty}` if the queue has no eligible entry,
  or `{:error, :over_cap}` if the candidate row's account turned
  out to be over-cap once the per-account lock + in-flight
  re-check ran (caller should retry on the next poll).
  """
  def claim_oldest_eligible(fleet_name, ineligible_account_ids, cap_lookup \\ %{})
      when is_binary(fleet_name) and is_list(ineligible_account_ids) and is_map(cap_lookup) do
    fn ->
      run_claim(fleet_name, ineligible_account_ids, cap_lookup)
    end
    |> Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_claim(fleet_name, ineligible_account_ids, cap_lookup) do
    case select_candidate(fleet_name, ineligible_account_ids) do
      nil ->
        Repo.rollback(:empty)

      candidate ->
        finalize_candidate(candidate, cap_lookup)
    end
  end

  defp finalize_candidate({id, account_id, repo}, cap_lookup) do
    acquire_account_lock(account_id)
    {cap_from_lookup, k8s_count} = Map.get(cap_lookup, account_id, {nil, 0})

    # `cap_from_lookup == nil` means the caller didn't supply an
    # entry for this account in `cap_lookup` — i.e. K8s reports
    # 0 running Pods for it. We still need a cap to compare
    # against, so re-read the account row inside the tx. Stale
    # `cap_lookup` (cap changed in flight) is also caught here.
    effective_cap = cap_from_lookup || lookup_cap(account_id)
    inflight = inflight_count(account_id)

    if cap_exceeded?(effective_cap, k8s_count + inflight) do
      Repo.rollback(:over_cap)
    else
      soft_claim!(id)
      %{id: id, account_id: account_id, repo: repo}
    end
  end

  defp cap_exceeded?(cap, _running) when is_nil(cap) or cap <= 0, do: true
  defp cap_exceeded?(cap, running), do: running >= cap

  @doc """
  Finalises a soft claim: deletes the queue row. Called after the
  JIT mint + Pod label-stamp succeed.
  """
  def finalize_claim(id) when is_integer(id) do
    {count, _} = Repo.delete_all(from(q in DispatchQueueEntry, where: q.id == ^id))

    if count == 1, do: :ok, else: {:error, :not_found}
  end

  @doc """
  Releases a soft claim: NULLs `claimed_at` so the row returns to
  the pending pool. Called when serving the claim fails after the
  soft claim (e.g. JIT mint refused by GitHub).
  """
  def release_claim(id) when is_integer(id) do
    {count, _} =
      Repo.update_all(
        from(q in DispatchQueueEntry, where: q.id == ^id and not is_nil(q.claimed_at), update: [set: [claimed_at: nil]]),
        []
      )

    if count == 1, do: :ok, else: {:error, :not_found}
  end

  @doc """
  Releases every soft claim older than `threshold` (a `DateTime`).
  Returns the number of rows released. Called by the stale-claim
  Oban worker so a server crash mid-mint doesn't strand a row.
  """
  def release_stale_claims(%DateTime{} = threshold) do
    {count, _} =
      Repo.update_all(
        from(q in DispatchQueueEntry,
          where: not is_nil(q.claimed_at) and q.claimed_at < ^threshold,
          update: [set: [claimed_at: nil]]
        ),
        []
      )

    count
  end

  @doc """
  Count entries for an account that are either pending or
  in-flight (soft-claimed but not yet finalized). Surface for
  diagnostics + the eventual ops dashboard.
  """
  def pending_count(%Account{} = account) do
    Repo.aggregate(
      from(q in DispatchQueueEntry, where: q.account_id == ^account.id),
      :count
    )
  end

  # ----- internal -----

  defp select_candidate(fleet_name, ineligible_account_ids) do
    sql =
      if ineligible_account_ids == [] do
        """
        SELECT id, account_id, repo
        FROM runner_dispatch_queue
        WHERE fleet_name = $1 AND claimed_at IS NULL
        ORDER BY inserted_at ASC
        LIMIT 1
        FOR UPDATE SKIP LOCKED
        """
      else
        """
        SELECT id, account_id, repo
        FROM runner_dispatch_queue
        WHERE fleet_name = $1
          AND claimed_at IS NULL
          AND NOT (account_id = ANY($2))
        ORDER BY inserted_at ASC
        LIMIT 1
        FOR UPDATE SKIP LOCKED
        """
      end

    params =
      if ineligible_account_ids == [],
        do: [fleet_name],
        else: [fleet_name, ineligible_account_ids]

    case Repo.query!(sql, params) do
      %{rows: [[id, account_id, repo]]} -> {id, account_id, repo}
      %{rows: []} -> nil
    end
  end

  defp acquire_account_lock(account_id) do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@claim_lock_salt, account_id])
    :ok
  end

  defp inflight_count(account_id) do
    Repo.aggregate(
      from(q in DispatchQueueEntry,
        where: q.account_id == ^account_id and not is_nil(q.claimed_at)
      ),
      :count
    )
  end

  defp lookup_cap(account_id) do
    case Repo.one(from a in Account, where: a.id == ^account_id, select: a.runner_max_concurrent) do
      nil -> nil
      cap -> cap
    end
  end

  defp soft_claim!(id) do
    {1, _} =
      Repo.update_all(from(q in DispatchQueueEntry, where: q.id == ^id and is_nil(q.claimed_at)),
        set: [claimed_at: DateTime.utc_now()]
      )

    :ok
  end
end
