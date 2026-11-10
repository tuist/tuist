defmodule Tuist.Runners.VolumeHeads do
  @moduledoc """
  The cache-volume HEAD: the API over `runner_volume_heads`, one row per
  (account, custom volume storage name).

  The HEAD is the single cross-host reference version of a custom volume's saved
  image. A publish advances it with a fast-forward compare-and-swap
  (`bump_head/6`), and hosts that are behind converge their local master toward
  it.

  The bump is fast-forward-only: a publish advances the HEAD only when the
  generation it built on is still the current HEAD. A job that built on a stale
  base (another host advanced the HEAD meanwhile) is rejected, so a slow or
  behind host can never clobber a newer image.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.VolumeHead

  @doc "Whether `name` is a custom volume storage name (`macos-<scope>` or `linux-<scope>`)."
  def valid_storage_volume_name?("macos-" <> scope), do: Regex.match?(~r/\A[0-9a-f]{64}\z/, scope)
  def valid_storage_volume_name?("linux-" <> scope), do: Regex.match?(~r/\A[0-9a-f]{64}\z/, scope)
  def valid_storage_volume_name?(_name), do: false

  @doc """
  Fast-forwards `account_id`'s HEAD of `volume_name` to `tree_digest` published
  from `node_name`, but ONLY when `base_generation` is still the current HEAD
  generation.

    * base 0 succeeds when the volume has NO HEAD yet, establishing generation 1.
    * base N > 0 succeeds only when the current HEAD is exactly generation N,
      advancing it to N+1.

  Returns `{:ok, new_generation}` on a successful fast-forward, or `:conflict`
  when the base is stale.
  """
  def bump_head(account_id, node_name, tree_digest, base_generation, volume_name, opts \\ [])

  def bump_head(account_id, node_name, tree_digest, 0, volume_name, opts)
      when is_integer(account_id) and is_binary(tree_digest) and tree_digest != "" do
    establish_first_head(account_id, node_name, tree_digest, volume_name, opts[:content_digest])
  end

  def bump_head(account_id, node_name, tree_digest, base_generation, volume_name, opts)
      when is_integer(account_id) and is_binary(tree_digest) and tree_digest != "" and is_integer(base_generation) and
             base_generation > 0 do
    fast_forward_head(account_id, node_name, tree_digest, base_generation, volume_name, opts[:content_digest])
  end

  def bump_head(_account_id, _node_name, _tree_digest, _base_generation, _volume_name, _opts), do: :conflict

  defp establish_first_head(account_id, node_name, tree_digest, volume_name, content_digest) do
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
            content_digest: content_digest,
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

  # content_digest is always written, nil included, so a value from the previous
  # HEAD never describes a different object.
  defp fast_forward_head(account_id, node_name, tree_digest, base_generation, volume_name, content_digest) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _} =
      Repo.update_all(
        from(h in VolumeHead,
          where:
            h.account_id == ^account_id and h.volume_name == ^volume_name and
              h.generation == ^base_generation
        ),
        inc: [generation: 1],
        set: [tree_digest: tree_digest, content_digest: content_digest, node_name: node_name, updated_at: now]
      )

    if count == 1, do: {:ok, base_generation + 1}, else: :conflict
  end

  @doc """
  The volume's current HEAD as `%{generation, tree_digest, content_digest}`, or
  `nil` when nothing has been published yet.
  """
  def get_head(account_id, volume_name) when is_integer(account_id) do
    Repo.one(
      from(h in VolumeHead,
        where: h.account_id == ^account_id and h.volume_name == ^volume_name,
        select: %{generation: h.generation, tree_digest: h.tree_digest, content_digest: h.content_digest}
      )
    )
  end

  def get_head(_account_id, _volume_name), do: nil

  def delete_head(account_id, volume_name) do
    Repo.delete_all(from(h in VolumeHead, where: h.account_id == ^account_id and h.volume_name == ^volume_name))
  end

  @doc """
  Whether a publish built on `base_generation` could still win the fast-forward,
  checked before the image upload. Advisory and racy: `bump_head/6` stays the
  sole authority, and anything this cannot evaluate reads as viable.
  """
  def fast_forward_viable?(account_id, base_generation, volume_name)
      when is_integer(account_id) and is_integer(base_generation) and base_generation >= 0 do
    case get_head(account_id, volume_name) do
      nil -> base_generation == 0
      %{generation: generation} -> generation == base_generation
    end
  end

  def fast_forward_viable?(_account_id, _base_generation, _volume_name), do: true
end
