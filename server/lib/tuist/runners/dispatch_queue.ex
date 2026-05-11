defmodule Tuist.Runners.DispatchQueue do
  @moduledoc """
  Postgres-backed dispatch queue. One row per pending Burst — a
  workflow_job the webhook handler accepted but no warm Pod has
  claimed yet.

  Claim is `DELETE … WHERE id = (SELECT … FOR UPDATE SKIP LOCKED LIMIT 1)`
  so concurrent warm Pods + concurrent server replicas can't grab
  the same row. The eligibility filter (skip accounts already at
  their `runner_max_concurrent`) is built by the caller from a K8s
  Pod LIST and passed in as the set of ineligible account ids to
  exclude.

  Enqueue refuses when the requesting account already has
  `4 × runner_max_concurrent` rows queued — a guard against one
  customer's sustained over-rate filling the table.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Runners.DispatchQueueEntry

  @queue_depth_multiplier 4

  @doc """
  Inserts a queue entry. Returns `{:ok, entry}` on success,
  `{:error, :queue_full}` when the account's pending count would
  exceed its per-customer ceiling, `{:error, :runners_disabled}`
  if `runner_max_concurrent` is 0, or `{:error, changeset}` on
  validation errors.
  """
  def enqueue(%Account{} = account, fleet_name, repo) when is_binary(fleet_name) and is_binary(repo) do
    cap = depth_cap_for(account)

    if cap == 0 do
      {:error, :runners_disabled}
    else
      Repo.transaction(fn ->
        pending =
          Repo.aggregate(
            from(q in DispatchQueueEntry, where: q.account_id == ^account.id),
            :count
          )

        if pending >= cap do
          Repo.rollback(:queue_full)
        else
          case Repo.insert(%DispatchQueueEntry{
                 account_id: account.id,
                 fleet_name: fleet_name,
                 repo: repo
               }) do
            {:ok, entry} -> entry
            {:error, cs} -> Repo.rollback(cs)
          end
        end
      end)
    end
  end

  @doc """
  Atomically claims the oldest pending entry for `fleet_name` whose
  account is NOT in `ineligible_account_ids` (customers currently at
  `runner_max_concurrent`). Returns `{:ok, %{account_id, repo}}` or
  `{:error, :empty}`.
  """
  def claim_oldest_eligible(fleet_name, ineligible_account_ids)
      when is_binary(fleet_name) and is_list(ineligible_account_ids) do
    sql =
      if ineligible_account_ids == [] do
        """
        DELETE FROM runner_dispatch_queue
        WHERE id = (
          SELECT id
          FROM runner_dispatch_queue
          WHERE fleet_name = $1
          ORDER BY inserted_at ASC
          LIMIT 1
          FOR UPDATE SKIP LOCKED
        )
        RETURNING id, account_id, repo
        """
      else
        """
        DELETE FROM runner_dispatch_queue
        WHERE id = (
          SELECT id
          FROM runner_dispatch_queue
          WHERE fleet_name = $1
            AND NOT (account_id = ANY($2))
          ORDER BY inserted_at ASC
          LIMIT 1
          FOR UPDATE SKIP LOCKED
        )
        RETURNING id, account_id, repo
        """
      end

    params =
      if ineligible_account_ids == [],
        do: [fleet_name],
        else: [fleet_name, ineligible_account_ids]

    case Repo.query(sql, params) do
      {:ok, %{rows: [[id, account_id, repo]]}} ->
        {:ok, %{id: id, account_id: account_id, repo: repo}}

      {:ok, %{rows: []}} ->
        {:error, :empty}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Count pending entries for an account. Surface for diagnostics +
  the eventual ops dashboard.
  """
  def pending_count(%Account{} = account) do
    Repo.aggregate(
      from(q in DispatchQueueEntry, where: q.account_id == ^account.id),
      :count
    )
  end

  # 0 means runners disabled. Otherwise multiplier-of-cap so larger
  # tiers get proportional headroom.
  defp depth_cap_for(%Account{runner_max_concurrent: cap}) when is_integer(cap) and cap > 0,
    do: cap * @queue_depth_multiplier

  defp depth_cap_for(_), do: 0
end
