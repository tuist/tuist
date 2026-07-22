defmodule Tuist.Runners.VolumeMasterOrphans do
  @moduledoc """
  API over `runner_volume_master_orphans`: cache-volume master objects a runner
  uploaded but whose fast-forward promote was rejected.

  The guest uploads the content-addressed `<digest>.image` BEFORE the
  compare-and-swap bump, so a rejected promote leaves an object no HEAD points
  at. `record/2` remembers it on rejection; `forget/2` drops it the instant the
  same digest is accepted as HEAD (its lifecycle then belongs to the supersession
  prune). `exists?/2` gates the delayed reclaim so a digest that became the live
  master is never deleted.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.VolumeHeads
  alias Tuist.Runners.VolumeMasterOrphan

  @doc "Records `tree_digest` as an orphan (idempotent upsert on the unique key)."
  def record(account_id, tree_digest, volume_name \\ VolumeHeads.reserved_tuist_cache())
      when is_integer(account_id) and is_binary(tree_digest) and tree_digest != "" do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(
      VolumeMasterOrphan,
      [
        %{
          account_id: account_id,
          volume_name: volume_name,
          tree_digest: tree_digest,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:account_id, :volume_name, :tree_digest]
    )

    :ok
  end

  @doc "Forgets `tree_digest` — it was accepted as HEAD or already reclaimed."
  def forget(account_id, tree_digest, volume_name \\ VolumeHeads.reserved_tuist_cache())
      when is_integer(account_id) and is_binary(tree_digest) do
    Repo.delete_all(
      from(o in VolumeMasterOrphan,
        where:
          o.account_id == ^account_id and o.volume_name == ^volume_name and
            o.tree_digest == ^tree_digest
      )
    )

    :ok
  end

  @doc "Whether `tree_digest` is still recorded as an orphan (never accepted)."
  def exists?(account_id, tree_digest, volume_name \\ VolumeHeads.reserved_tuist_cache())
      when is_integer(account_id) and is_binary(tree_digest) do
    Repo.exists?(
      from(o in VolumeMasterOrphan,
        where:
          o.account_id == ^account_id and o.volume_name == ^volume_name and
            o.tree_digest == ^tree_digest
      )
    )
  end
end
