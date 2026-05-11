defmodule Tuist.Runners.Claims do
  @moduledoc """
  Postgres-backed claim coordination for the dispatch path. The
  table is **very thin** — one row per currently-claimed
  workflow_job, deleted on completion / release / stale recovery.

  Two responsibilities, both genuinely OLTP:

    1. **Atomic claim.** `attempt/4` is `INSERT … ON CONFLICT
       (workflow_job_id) DO NOTHING RETURNING …`. Two racing
       claims for the same workflow_job collapse here: the unique
       constraint serialises them, exactly one row lands, the
       loser gets zero rows back and bails before any side
       effect (mint, runner registration).

    2. **Per-account cap count.** `counts_per_account/0` is a
       single indexed `GROUP BY account_id` against this table.
       Gives the dispatch path an authoritative inflight count
       without querying ClickHouse or the K8s apiserver. The cap
       is account-level (NOT fleet-level), so this query does not
       filter by fleet — an account at cap=1 can't run one job
       per pool.

  ClickHouse `runner_jobs` is the customer-facing view (queued,
  running, completed, history). The two stores stay in sync via a
  one-way protocol: PG is the source of truth for "is this
  claimed and counted?" and every transition that flips that bit
  pairs the PG write with an INSERT to CH.

  Recovery: `list_stale/1` returns claims older than the
  threshold WITHOUT deleting them; the stale-claims worker iterates
  the result, writes `queued` to ClickHouse first, then calls
  `release/2` to delete the PG row. CH-first is critical — if PG
  were deleted first and we crashed, the CH row would stay
  `claimed`, `Jobs.pick_queued` would skip it, and no PG claim
  would remain for the next worker run to recover, stranding the
  workflow_job permanently.
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.Claim

  require Logger

  @doc """
  Attempts to claim `workflow_job_id` for `pod_name`. Returns
  `{:ok, %Claim{}}` on success (we won) or `{:error, :lost_race}`
  if the workflow_job is already claimed by another pod.

  The claim is atomic on the unique PK — no verify-readback
  needed.
  """
  def attempt(workflow_job_id, account_id, fleet_name, pod_name)
      when is_integer(workflow_job_id) and is_integer(account_id) and is_binary(fleet_name) and is_binary(pod_name) do
    now = DateTime.utc_now()

    # `insert_all/3` + `returning: …` lets us count actually-inserted
    # rows directly — 0 means ON CONFLICT DO NOTHING fired and
    # another pod owns the claim. `Repo.insert/2` here would
    # always return `{:ok, struct}` even on conflict, which
    # forces a less-clean detection path (extra SELECT).
    {count, rows} =
      Repo.insert_all(
        Claim,
        [
          %{
            workflow_job_id: workflow_job_id,
            account_id: account_id,
            fleet_name: fleet_name,
            pod_name: pod_name,
            claimed_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: :workflow_job_id,
        returning: [:workflow_job_id, :account_id, :fleet_name, :pod_name, :claimed_at]
      )

    case count do
      0 ->
        {:error, :lost_race}

      1 ->
        [row] = rows
        {:ok, struct(Claim, Map.from_struct(row))}
    end
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
  Counts active claims per account **across all fleets**. Returns
  `%{account_id => count}`. Powers the cap_lookup the dispatch
  path builds before each claim attempt.

  Cap is account-level — `accounts.runner_max_concurrent` is the
  customer's total concurrent runner budget across every pool
  they reach. If we filtered by fleet, an account at cap=1 could
  run one job per pool simultaneously (one in `default`, one in
  `xcode-15`, etc.), breaching the contract.
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
  Returns claims older than `threshold` without deleting them.
  The stale-claims worker uses this to recover row-by-row: for
  each stale claim it FIRST writes `queued` to ClickHouse, THEN
  calls `release/2` with the handle to delete the PG row.
  Reversing that order would leave a window where the PG row is
  gone but CH still shows `claimed` — `pick_queued` would skip
  the row and no PG claim would remain for the next worker run
  to recover, stranding the workflow_job permanently.
  """
  def list_stale(%DateTime{} = threshold) do
    Repo.all(
      from(c in Claim,
        where: c.claimed_at < ^threshold,
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
