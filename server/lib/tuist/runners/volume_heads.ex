defmodule Tuist.Runners.VolumeHeads do
  @moduledoc """
  The per-account cache-volume HEAD: the API over `runner_volume_heads`.

  The HEAD is the single cross-host reference version of an account's warm
  set. A runner reports it on promote (`bump_head/4`, last-writer-wins), and
  dispatch hands it back to the next runner (`get_head/2`) so a host that is
  behind can converge its on-disk master toward it before materializing —
  turning "whatever this host last ran" into "the account's current warm set".
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.VolumeHead

  @reserved_tuist_cache "tuist-cache"

  @doc "The reserved volume name for the managed Tuist module cache."
  def reserved_tuist_cache, do: @reserved_tuist_cache

  @doc """
  Records that `node_name` promoted `account_id`'s volume to the warm set with
  inventory `tree_digest`, bumping the account's HEAD generation. Upserts on
  (account_id, volume_name); last-writer-wins, matching the volume's promote
  semantics. Called only for a successful, cache-changing job, so the digest
  always advances.
  """
  def bump_head(account_id, node_name, tree_digest, volume_name \\ @reserved_tuist_cache)

  def bump_head(account_id, node_name, tree_digest, volume_name)
      when is_integer(account_id) and is_binary(tree_digest) and tree_digest != "" do
    now = DateTime.truncate(DateTime.utc_now(), :second)

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
      on_conflict:
        from(h in VolumeHead,
          update: [
            inc: [generation: 1],
            set: [tree_digest: ^tree_digest, node_name: ^node_name, updated_at: ^now]
          ]
        ),
      conflict_target: [:account_id, :volume_name]
    )

    :ok
  end

  # No digest to record (empty/absent): nothing to publish.
  def bump_head(_account_id, _node_name, _tree_digest, _volume_name), do: :ok

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
