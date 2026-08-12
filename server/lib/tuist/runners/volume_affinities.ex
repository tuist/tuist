defmodule Tuist.Runners.VolumeAffinities do
  @moduledoc """
  Dispatch-time volume affinity: the query API over
  `runner_volume_affinities`.

  Affinity is a pure dispatch-scoring policy over the shared warm pool — no
  Kubernetes scheduling change. `record/4` stamps "this account materialized a
  master on this host" on every claim that can leave one behind;
  `select_candidate/3` prefers a queued job whose account is one of the host's
  likely-resident masters, bounded by an age tolerance so affinity never delays
  a job past the tolerance (the precise operational meaning of the hard rule
  that affinity never starves an account holding no volume).

  ## Why the resident set is bounded

  A host holds only the last M masters it materialized: tart-kubelet's
  admission evicts masters in LRU order (by master-image mtime, which
  materialize touches) until the branch it is admitting fits. Recording
  affinity without that bound made a node affine to every account that had
  ever run on it inside the retention window, so the "preference" contained
  the queue head's account too and `select_candidate/3` reduced to "take the
  head" — byte-identical to no affinity at all.

  So the resident set is the `limit` most recent distinct accounts by
  `last_run_at`, which mirrors the host's own eviction order. It is an
  approximation, not ground truth (the host, not the server, knows which
  masters survived), and both error directions are graceful: too small
  prefers a subset of what the host really holds, too large drifts back
  toward preferring nothing in particular. Bias the bound low.

  The approximation is also self-correcting rather than one-shot. Once a node
  prefers accounts A and B, the jobs it wins are mostly A's and B's, which
  keeps A and B at the top of its `last_run_at` order and keeps their masters
  freshest in the host's LRU. Preference and residency reinforce each other, so
  the fleet settles into a stable partition of accounts over hosts without the
  server ever placing a job on a chosen host — which is what makes the
  node-pull dispatch direction sufficient here.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.VolumeAffinity

  @reserved_tuist_cache "tuist-cache"

  @default_resident_limit 2

  @doc "The reserved volume name for the managed Tuist module cache."
  def reserved_tuist_cache, do: @reserved_tuist_cache

  @doc """
  Records that `account_id` ran a job on `node_name`, bumping last_run_at.
  Upserts on the (node_name, account_id, volume_name) key so a host keeps
  one row per account. No-op-safe to call on every claim.

  Only call this for a job that will actually materialize a master. An
  untrusted (fork) job is dispatched with the cache-untrusted label and the
  host skips materialize and promote for it, so it leaves no master behind;
  recording it would spend one of the host's few resident slots in this
  model on a master that does not exist, evicting a real one from the
  preference set.
  """
  def record(node_name, account_id, volume_name \\ @reserved_tuist_cache)

  def record(node_name, account_id, volume_name)
      when is_binary(node_name) and node_name != "" and is_integer(account_id) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(
      VolumeAffinity,
      [
        %{
          node_name: node_name,
          account_id: account_id,
          volume_name: volume_name,
          last_run_at: now,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:last_run_at, :updated_at]},
      conflict_target: [:node_name, :account_id, :volume_name]
    )

    :ok
  end

  # No node identity (pod without spec.nodeName, or a lookup that failed):
  # there's nothing to record. Affinity degrades to "no preference", which
  # is exactly today's behaviour.
  def record(_node_name, _account_id, _volume_name), do: :ok

  @doc """
  Set of account ids whose masters `node_name` most likely still holds: the
  `limit` accounts that ran there most recently, newest first, which is the
  inverse of the host's LRU eviction order.

  `limit` is the host's surviving master count. A non-positive limit disables
  the preference (empty set) rather than falling back to unbounded, so a
  misconfigured bound degrades to plain oldest-queued dispatch instead of
  silently reinstating the saturated set.
  """
  def resident_account_ids(node_name, limit \\ @default_resident_limit, volume_name \\ @reserved_tuist_cache)

  def resident_account_ids(node_name, limit, volume_name)
      when is_binary(node_name) and node_name != "" and is_integer(limit) and limit > 0 do
    from(v in VolumeAffinity,
      where: v.node_name == ^node_name and v.volume_name == ^volume_name,
      order_by: [desc: v.last_run_at, desc: v.account_id],
      limit: ^limit,
      select: v.account_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def resident_account_ids(_node_name, _limit, _volume_name), do: MapSet.new()

  @doc """
  Picks the candidate a polling runner on `node_name` should be handed
  from a top-K list of queued candidates (ordered oldest-enqueued first):
  the oldest one whose account is likely resident on the node, UNLESS the
  queue head has itself been waiting longer than `:tolerance_seconds`, in
  which case the head is returned so it can't be passed over indefinitely.

  The tolerance bounds how long the head can be delayed by affinity, measured
  from now — not the enqueue gap between the chosen candidate and the head.
  Comparing candidate-vs-head only bounds how far apart the two were enqueued,
  which a burst of affine jobs enqueued within the window can exploit to starve
  the head for far longer than the tolerance. Bounding head age from now caps
  the head's worst-case delay at `:tolerance_seconds`.

  Returns `nil` for an empty list, else `{candidate, outcome}`. The outcome is
  why that candidate was picked, so dispatch can report whether the preference
  is discriminating at all:

    * `:resident` — a queued job of a likely-resident account was preferred.
    * `:head_resident` — the head's own account is likely resident; nothing
      was reordered but the job still lands warm.
    * `:no_resident_candidate` — the node has a resident set, but none of the
      top-K queued jobs belong to it; the head goes out cold.
    * `:no_residency` — the node has no resident set at all (first jobs on a
      fresh host, or the bound is disabled).
    * `:head_overdue` — a resident candidate was queued, but the head hit the
      starvation bound and took precedence. This is the only outcome the
      tolerance costs anything, so it is the one to tune it against.

  ## Options

    * `:tolerance_seconds` — the starvation bound. Required.
    * `:resident_limit` — how many masters the host is assumed to hold.
      Defaults to #{@default_resident_limit}.
    * `:volume_name` — defaults to the reserved Tuist cache volume.
  """
  def select_candidate(candidates, node_name, opts)

  def select_candidate([], _node_name, _opts), do: nil

  def select_candidate([head | _] = candidates, node_name, opts) do
    tolerance_seconds = Keyword.fetch!(opts, :tolerance_seconds)
    limit = Keyword.get(opts, :resident_limit, @default_resident_limit)
    volume_name = Keyword.get(opts, :volume_name, @reserved_tuist_cache)

    resident = resident_account_ids(node_name, limit, volume_name)

    cond do
      MapSet.size(resident) == 0 ->
        {head, :no_residency}

      # Checked before the starvation bound: an overdue head is handed out
      # either way, and reporting that as `:head_overdue` would hide that the
      # placement was warm anyway and make the bound look more expensive than
      # it is.
      MapSet.member?(resident, head.account_id) ->
        {head, :head_resident}

      true ->
        candidates
        |> Enum.find(fn candidate -> MapSet.member?(resident, candidate.account_id) end)
        |> resolve_against_starvation_bound(head, tolerance_seconds)
    end
  end

  # Nothing resident is queued, so the head goes out and the tolerance was never
  # in play. Reported apart from `:head_overdue` so that outcome counts only the
  # warm placements the bound actually gave up — the number the tolerance should
  # be tuned against.
  defp resolve_against_starvation_bound(nil, head, _tolerance_seconds), do: {head, :no_resident_candidate}

  defp resolve_against_starvation_bound(candidate, head, tolerance_seconds) do
    if head_overdue?(head, tolerance_seconds) do
      {head, :head_overdue}
    else
      {candidate, :resident}
    end
  end

  @doc """
  Deletes affinity rows older than `older_than_seconds` (default 14 days).
  Called on the periodic runner-maintenance sweep. A pruned row only costs
  a status-quo cold job that re-warms the volume anyway.
  """
  def prune(older_than_seconds \\ 14 * 24 * 60 * 60) do
    cutoff = DateTime.add(DateTime.utc_now(), -older_than_seconds, :second)

    {deleted, _} = Repo.delete_all(from(v in VolumeAffinity, where: v.last_run_at < ^cutoff))

    deleted
  end

  # The head is overdue once it has been queued longer than the tolerance,
  # measured from now. Past that point affinity must stop passing it over.
  defp head_overdue?(%{enqueued_at: %DateTime{} = head_enqueued_at}, tolerance_seconds) do
    DateTime.diff(DateTime.utc_now(), head_enqueued_at, :second) > tolerance_seconds
  end

  # Defensive: a head with no enqueue time can't be aged, so never treat it as
  # overdue — affinity may still prefer an affine candidate.
  defp head_overdue?(_head, _tolerance_seconds), do: false
end
