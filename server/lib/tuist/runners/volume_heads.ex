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

  ## Retiring a HEAD no host can adopt

  Fast-forward-only has one failure mode with no way out of itself: a HEAD whose
  stored object does not reproduce the `tree_digest` it advertises. Converging
  hosts verify the object before adopting it and decline — correctly, since that
  check is what stops a corrupt master propagating fleet-wide — so no host obtains
  that generation, and every job then promotes from base 0, which the rule above
  rejects because a HEAD exists. The account can neither adopt the HEAD nor
  replace it, on any host, for as long as it stands.

  So a base-0 promote may also take over an existing lineage, on one condition:
  the promoting host reports the current HEAD's digest as one it downloaded and
  could not verify. That is evidence about the object, produced by a host that
  fetched it, and it retires only the exact digest it names — the lineage
  continues at `generation + 1` rather than resetting, so local masters elsewhere
  in the fleet stay comparable against one monotonic counter.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.VolumeHead

  require Logger

  @reserved_tuist_cache "tuist-cache"

  @doc "The reserved volume name for the managed Tuist module cache."
  def reserved_tuist_cache, do: @reserved_tuist_cache

  @doc """
  Fast-forwards `account_id`'s HEAD to `tree_digest` published from `node_name`,
  but ONLY when `base_generation` is still the current HEAD generation — a
  compare-and-swap.

  `base_generation` is the generation the promoting job's branch was cloned from.

    * base 0 (a cold job, no local master) succeeds when the account has NO HEAD
      yet, establishing generation 1. If a HEAD already exists, the cold job built
      on nothing while the fleet moved on, so it is rejected — unless
      `opts[:unverifiable_digest]` names that HEAD's digest, which retires it (see
      the moduledoc).
    * base N > 0 succeeds only when the current HEAD is exactly generation N,
      advancing it to N+1. Any other current generation means another host already
      advanced past this job's base, so it is rejected.

  Returns `{:ok, new_generation}` on a successful fast-forward, or `:conflict`
  when the base is stale. Upserts on (account_id, volume_name).
  """
  def bump_head(account_id, node_name, tree_digest, base_generation, volume_name \\ @reserved_tuist_cache, opts \\ [])

  def bump_head(account_id, node_name, tree_digest, 0, volume_name, opts)
      when is_integer(account_id) and is_binary(tree_digest) and tree_digest != "" do
    establish_first_head(account_id, node_name, tree_digest, volume_name, Keyword.get(opts, :unverifiable_digest))
  end

  def bump_head(account_id, node_name, tree_digest, base_generation, volume_name, _opts)
      when is_integer(account_id) and is_binary(tree_digest) and tree_digest != "" and is_integer(base_generation) and
             base_generation > 0 do
    fast_forward_head(account_id, node_name, tree_digest, base_generation, volume_name)
  end

  # No digest to record (empty/absent) or an invalid base: nothing to publish.
  def bump_head(_account_id, _node_name, _tree_digest, _base_generation, _volume_name, _opts), do: :conflict

  # Cold job: establish generation 1 iff no HEAD exists. A conflict (a HEAD is
  # already there) falls through to the retirement rule, which rejects unless the
  # promoting host proved that HEAD's object cannot be verified — a cold branch
  # must not otherwise clobber an existing lineage.
  defp establish_first_head(account_id, node_name, tree_digest, volume_name, unverifiable_digest) do
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

    if count == 1 do
      {:ok, 1}
    else
      retire_unverifiable_head(account_id, node_name, tree_digest, volume_name, unverifiable_digest)
    end
  end

  # Take over a lineage whose object the promoting host proved unverifiable. The
  # WHERE pins BOTH the generation and the digest that was disproved, so this stays
  # a compare-and-swap: if another host advanced the HEAD (or retired the same
  # digest first) between the read and the write, it matches nothing and rejects.
  # The generation advances rather than resetting, so a host still holding an older
  # master keeps comparing against one monotonic counter.
  defp retire_unverifiable_head(account_id, node_name, tree_digest, volume_name, unverifiable_digest) do
    head = get_head(account_id, volume_name)

    if retires_head?(head, unverifiable_digest) do
      %{generation: generation} = head
      now = DateTime.truncate(DateTime.utc_now(), :second)

      {count, _} =
        Repo.update_all(
          from(h in VolumeHead,
            where:
              h.account_id == ^account_id and h.volume_name == ^volume_name and
                h.generation == ^generation and h.tree_digest == ^unverifiable_digest
          ),
          set: [
            generation: generation + 1,
            tree_digest: tree_digest,
            node_name: node_name,
            updated_at: now
          ]
        )

      if count == 1 do
        Logger.warning(
          "runners: retired cache-volume HEAD #{unverifiable_digest} for account #{account_id} " <>
            "(reported unverifiable by #{node_name}); lineage continues at generation #{generation + 1}"
        )

        {:ok, generation + 1}
      else
        :conflict
      end
    else
      :conflict
    end
  end

  # The one rule both the pre-flight and the bump evaluate, kept in a single place
  # so they cannot drift: a cold promote retires an existing HEAD only when the
  # promoting host names that exact digest as one it downloaded and could not
  # verify. Anything else — no HEAD to compare, no report, a report naming a digest
  # the HEAD has already moved off — does not retire it.
  defp retires_head?(%{tree_digest: digest}, unverifiable_digest)
       when is_binary(unverifiable_digest) and unverifiable_digest != "" do
    digest == unverifiable_digest
  end

  defp retires_head?(_head, _unverifiable_digest), do: false

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

  @doc """
  Whether a promote built on `base_generation` could still win the fast-forward —
  the pre-flight the runner makes BEFORE uploading its image.

  Mirrors `bump_head/6`'s acceptance rule: base 0 is viable while the account has
  no HEAD or while `opts[:unverifiable_digest]` retires the one it has, base N > 0
  only while the HEAD is exactly at N.

  Mirroring the retirement rule here is load-bearing, not tidiness: this runs
  BEFORE the upload, so a pre-flight that ignored the report would 409 every
  promote that could retire a poisoned HEAD and the bump would never see one.

  This is an OPTIMIZATION, not a decision. It is racy by construction (another
  host can advance the HEAD between this read and the bump), so it may only ever
  let a caller skip work that `bump_head/6` would reject anyway — the
  compare-and-swap there stays the sole authority on what becomes HEAD. Anything
  it cannot evaluate reads as viable, so an odd input never suppresses a promote
  that would have been accepted.
  """
  def fast_forward_viable?(account_id, base_generation, volume_name \\ @reserved_tuist_cache, opts \\ [])

  def fast_forward_viable?(account_id, base_generation, volume_name, opts)
      when is_integer(account_id) and is_integer(base_generation) and base_generation >= 0 do
    case get_head(account_id, volume_name) do
      nil ->
        base_generation == 0

      %{generation: generation} = head ->
        generation == base_generation or
          (base_generation == 0 and retires_head?(head, Keyword.get(opts, :unverifiable_digest)))
    end
  end

  def fast_forward_viable?(_account_id, _base_generation, _volume_name, _opts), do: true
end
