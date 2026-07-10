defmodule Tuist.Runners.VolumeAffinities do
  @moduledoc """
  Dispatch-time volume affinity (spec #76): the query API over
  `runner_volume_affinities`.

  Affinity is a pure dispatch-scoring policy over the shared warm pool — no
  Kubernetes scheduling change. `record/3` stamps "this account ran on this
  host" on every claim; `select_candidate/4` prefers an affine account's
  queued job for a polling runner, bounded by an age tolerance so affinity
  never delays a job past the tolerance (the precise operational meaning of
  the hard rule that affinity never starves an account holding no volume).
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.VolumeAffinity

  @reserved_tuist_cache "tuist-cache"

  @doc "The reserved volume name for the managed Tuist module cache."
  def reserved_tuist_cache, do: @reserved_tuist_cache

  @doc """
  Records that `account_id` ran a job on `node_name`, bumping last_run_at.
  Upserts on the (node_name, account_id, volume_name) key so a host keeps
  one row per account. No-op-safe to call on every claim.
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
  Set of account ids that recently ran on `node_name` for a volume — the
  accounts whose masters this host likely holds.
  """
  def affine_account_ids(node_name, volume_name \\ @reserved_tuist_cache)

  def affine_account_ids(node_name, volume_name) when is_binary(node_name) and node_name != "" do
    from(v in VolumeAffinity,
      where: v.node_name == ^node_name and v.volume_name == ^volume_name,
      select: v.account_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def affine_account_ids(_node_name, _volume_name), do: MapSet.new()

  @doc """
  Picks the candidate a polling runner on `node_name` should be handed
  from a top-K list of queued candidates (ordered oldest-enqueued first):
  the oldest one whose account is affine to the node AND whose enqueue
  time is within `tolerance_seconds` of the queue head, else the head.

  The tolerance bounds how long any job can be passed over, so affinity is
  a preference, never a delay past the bound. Returns nil for an empty
  list.
  """
  def select_candidate(candidates, node_name, tolerance_seconds, volume_name \\ @reserved_tuist_cache)

  def select_candidate([], _node_name, _tolerance_seconds, _volume_name), do: nil

  def select_candidate([head | _] = candidates, node_name, tolerance_seconds, volume_name) do
    affine = affine_account_ids(node_name, volume_name)

    if MapSet.size(affine) == 0 do
      head
    else
      Enum.find(candidates, head, fn candidate ->
        MapSet.member?(affine, candidate.account_id) and
          within_tolerance?(candidate.enqueued_at, head.enqueued_at, tolerance_seconds)
      end)
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

  defp within_tolerance?(%DateTime{} = enqueued_at, %DateTime{} = head_enqueued_at, tolerance_seconds) do
    DateTime.diff(enqueued_at, head_enqueued_at, :second) <= tolerance_seconds
  end

  # Defensive: if a candidate carries no enqueue time, don't let it win
  # affinity (fall back to the head).
  defp within_tolerance?(_enqueued_at, _head_enqueued_at, _tolerance_seconds), do: false
end
