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

  Fast-forward orders promotes by VERSION, though, not by CONTENT — a newer
  generation may carry strictly less. That gap is why the bump also refuses a
  promote that would drop the Xcode compilation cache (CAS) the current HEAD
  carries: a host that cannot write one (mid-rollout, rolled back, or deployed
  with the CAS off) would otherwise publish a CAS-less image as HEAD and every
  other host would converge to it and lose its compilation cache. Enforced here
  rather than only on the runner because this is the one point every client goes
  through, including clients too old to ever get a host-side fix.
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

  `opts` carries the promoted image's content declarations:

    * `:cas_present` — the image carries an Xcode compilation cache store.
    * `:cas_disabled` — the promoting host reports the CAS is deliberately off,
      so dropping the store is the intent rather than an accident. Only an
      explicit signal counts: a runner that simply never mentions the CAS reads
      as "no CAS, no intent", which is what protects against clients too old to
      report either.
    * `:volume_name` — defaults to the reserved Tuist cache volume.

  Returns `{:ok, new_generation}` on a successful fast-forward, `:conflict` when
  the base is stale, or `:cas_regression` when the promote would drop the
  compilation cache the current HEAD carries without declaring it intentional.
  Upserts on (account_id, volume_name).
  """
  def bump_head(account_id, node_name, tree_digest, base_generation, opts \\ [])

  def bump_head(account_id, node_name, tree_digest, 0, opts)
      when is_integer(account_id) and is_binary(tree_digest) and tree_digest != "" do
    # No HEAD yet means no content to regress from, so the CAS guard has nothing
    # to compare against — the insert either establishes the lineage or loses to
    # one that already exists.
    establish_first_head(account_id, node_name, tree_digest, opts)
  end

  def bump_head(account_id, node_name, tree_digest, base_generation, opts)
      when is_integer(account_id) and is_binary(tree_digest) and tree_digest != "" and is_integer(base_generation) and
             base_generation > 0 do
    fast_forward_head(account_id, node_name, tree_digest, base_generation, opts)
  end

  # No digest to record (empty/absent) or an invalid base: nothing to publish.
  def bump_head(_account_id, _node_name, _tree_digest, _base_generation, _opts), do: :conflict

  # Cold job: establish generation 1 iff no HEAD exists. A conflict (a HEAD is
  # already there) rejects — a cold branch must not clobber an existing lineage.
  defp establish_first_head(account_id, node_name, tree_digest, opts) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _} =
      Repo.insert_all(
        VolumeHead,
        [
          %{
            account_id: account_id,
            volume_name: volume_name(opts),
            node_name: node_name,
            tree_digest: tree_digest,
            generation: 1,
            cas_present: cas_present(opts),
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:account_id, :volume_name]
      )

    if count == 1, do: {:ok, 1}, else: :conflict
  end

  # Warm job: advance the HEAD only if it is still at the base the job built on
  # AND the promote does not silently drop the HEAD's compilation cache.
  defp fast_forward_head(account_id, node_name, tree_digest, base_generation, opts) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    volume_name = volume_name(opts)
    cas_present = cas_present(opts)
    # The guard applies only to a promote that both lacks a CAS and does not
    # claim to have dropped it on purpose. Everything else bumps as before.
    guard_cas = not cas_present and not truthy(Keyword.get(opts, :cas_disabled))

    base_query =
      from(h in VolumeHead,
        where:
          h.account_id == ^account_id and h.volume_name == ^volume_name and
            h.generation == ^base_generation
      )

    # Folded into the same UPDATE as the generation compare-and-swap rather than
    # checked first: a separate read would leave a window in which the HEAD gains
    # a CAS between the check and the write, and the CAS-less promote would still
    # land.
    query = if guard_cas, do: from(h in base_query, where: h.cas_present == false), else: base_query

    {count, _} =
      Repo.update_all(query,
        inc: [generation: 1],
        set: [tree_digest: tree_digest, node_name: node_name, cas_present: cas_present, updated_at: now]
      )

    cond do
      count == 1 -> {:ok, base_generation + 1}
      guard_cas -> classify_rejection(account_id, volume_name, base_generation)
      true -> :conflict
    end
  end

  # Which of the two guards rejected the bump, for the caller's response and
  # logs. Observational only — the write above already happened or didn't — so a
  # HEAD that moves again before this read just reports the ordinary conflict.
  defp classify_rejection(account_id, volume_name, base_generation) do
    head =
      Repo.one(
        from(h in VolumeHead,
          where: h.account_id == ^account_id and h.volume_name == ^volume_name,
          select: %{generation: h.generation, cas_present: h.cas_present}
        )
      )

    case head do
      %{generation: ^base_generation, cas_present: true} -> :cas_regression
      _ -> :conflict
    end
  end

  defp volume_name(opts), do: Keyword.get(opts, :volume_name) || @reserved_tuist_cache

  defp cas_present(opts), do: truthy(Keyword.get(opts, :cas_present))

  defp truthy(value), do: value == true

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
