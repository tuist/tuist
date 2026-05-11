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

    2. **Per-account cap count.** `counts_per_account/1` is a
       single indexed `GROUP BY account_id` against this table.
       Gives the dispatch path an authoritative inflight count
       without querying ClickHouse or the K8s apiserver.

  ClickHouse `runner_jobs` is the customer-facing view (queued,
  running, completed, history). The two stores stay in sync via a
  one-way protocol: PG is the source of truth for "is this
  claimed and counted?" and every transition that flips that bit
  pairs the PG write with an INSERT to CH.

  Recovery: `release_stale/1` deletes claims older than the
  threshold and returns the released rows so the caller can
  re-surface them in CH as `queued`. A server crash between PG
  INSERT and CH INSERT leaves PG holding a claim that CH doesn't
  show — self-correcting because the next candidate pick reads
  CH, doesn't see the workflow_job, no double-claim. A crash
  between PG DELETE (release/finalize) and CH INSERT leaves CH
  showing a stale `claimed` state — visible to ops but not
  functionally bad; the next state transition or the stale-claims
  worker re-syncs.
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
  Counts active claims per account on `fleet_name`. Returns
  `%{account_id => count}`. Powers the cap_lookup the dispatch
  path builds before each claim attempt.
  """
  def counts_per_account(fleet_name) when is_binary(fleet_name) do
    from(c in Claim,
      where: c.fleet_name == ^fleet_name,
      group_by: c.account_id,
      select: {c.account_id, count(c.workflow_job_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Deletes claims older than `threshold` and returns the deleted
  rows. The caller re-surfaces them as `queued` in ClickHouse
  so the next poll can pick them up.
  """
  def release_stale(%DateTime{} = threshold) do
    {_count, rows} =
      Repo.delete_all(
        from(c in Claim,
          where: c.claimed_at < ^threshold,
          select: %{
            workflow_job_id: c.workflow_job_id,
            account_id: c.account_id,
            fleet_name: c.fleet_name
          }
        )
      )

    rows
  end
end
