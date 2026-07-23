defmodule Tuist.Runners.VolumeHeads do
  @moduledoc """
  The per-account cache-volume HEAD: the API over `runner_volume_heads`.

  The HEAD is the single cross-host reference version of an account's warm
  set. A runner reports it on promote (`bump_head/5`, a fast-forward
  compare-and-swap), and dispatch hands it back to the next runner (`get_head/2`)
  so a host that is behind can converge its on-disk master toward it before
  materializing — turning "whatever this host last ran" into "the account's
  current warm set".

  The bump is fast-forward-only: a promote advances the HEAD only when the
  generation it built on is still the current HEAD. A job that built on a stale
  base (another host advanced the HEAD meanwhile) is rejected, so a slow or behind
  host can never clobber a newer warm set — the loser's delta is simply rebuilt by
  the next job. This is the coordination point of the whole fast-forward
  last-writer-wins model.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.VolumeHead

  @reserved_tuist_cache "tuist-cache"

  @doc "The reserved volume name for the managed Tuist module cache."
  def reserved_tuist_cache, do: @reserved_tuist_cache

  @doc """
  Fast-forwards `account_id`'s HEAD to `tree_digest` published from `node_name`,
  but ONLY when `base_generation` is still the current HEAD generation — a
  compare-and-swap.

  `base_generation` is the generation the promoting job's branch was cloned from.

    * base 0 (a cold job, no local master) succeeds only when the account has NO
      HEAD yet, establishing generation 1. If a HEAD already exists, the cold job
      built on nothing while the fleet moved on, so it is rejected.
    * base N > 0 succeeds only when the current HEAD is exactly generation N,
      advancing it to N+1. Any other current generation means another host already
      advanced past this job's base, so it is rejected.

  Returns `{:ok, new_generation}` on a successful fast-forward, or `:conflict`
  when the base is stale. Upserts on (account_id, volume_name).
  """
  def bump_head(account_id, node_name, tree_digest, base_generation, volume_name \\ @reserved_tuist_cache)

  def bump_head(account_id, node_name, tree_digest, 0, volume_name)
      when is_integer(account_id) and is_binary(tree_digest) and tree_digest != "" do
    establish_first_head(account_id, node_name, tree_digest, volume_name)
  end

  def bump_head(account_id, node_name, tree_digest, base_generation, volume_name)
      when is_integer(account_id) and is_binary(tree_digest) and tree_digest != "" and is_integer(base_generation) and
             base_generation > 0 do
    fast_forward_head(account_id, node_name, tree_digest, base_generation, volume_name)
  end

  # No digest to record (empty/absent) or an invalid base: nothing to publish.
  def bump_head(_account_id, _node_name, _tree_digest, _base_generation, _volume_name), do: :conflict

  # Cold job: establish generation 1 iff no HEAD exists. A conflict (a HEAD is
  # already there) rejects — a cold branch must not clobber an existing lineage.
  defp establish_first_head(account_id, node_name, tree_digest, volume_name) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _} =
      Repo.insert_all(
        VolumeHead,
        [
          %{
            account_id: account_id,
            volume_name: volume_name,
            node_name: node_name,
            tree_digest: tree_digest,
            generation: 1,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:account_id, :volume_name]
      )

    if count == 1, do: {:ok, 1}, else: :conflict
  end

  # Warm job: advance the HEAD only if it is still at the base the job built on.
  defp fast_forward_head(account_id, node_name, tree_digest, base_generation, volume_name) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _} =
      Repo.update_all(
        from(h in VolumeHead,
          where:
            h.account_id == ^account_id and h.volume_name == ^volume_name and
              h.generation == ^base_generation
        ),
        inc: [generation: 1],
        set: [tree_digest: tree_digest, node_name: node_name, updated_at: now]
      )

    if count == 1, do: {:ok, base_generation + 1}, else: :conflict
  end

  @doc """
  The account's current HEAD as `%{generation, tree_digest}`, or `nil` when the
  account has never promoted a volume (the host materializes cold and its first
  successful job establishes the HEAD).
  """
  def get_head(account_id, volume_name \\ @reserved_tuist_cache)

  def get_head(account_id, volume_name) when is_integer(account_id) do
    Repo.one(
      from(h in VolumeHead,
        where: h.account_id == ^account_id and h.volume_name == ^volume_name,
        select: %{generation: h.generation, tree_digest: h.tree_digest}
      )
    )
  end

  def get_head(_account_id, _volume_name), do: nil
end
