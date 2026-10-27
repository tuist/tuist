defmodule Tuist.Repo.Migrations.CreateRunnerVolumeMasterOrphans do
  use Ecto.Migration

  # Cache-volume master objects a runner UPLOADED but whose fast-forward promote
  # the server REJECTED (a stale base another host had advanced past). The guest
  # uploads the content-addressed <digest>.image BEFORE the compare-and-swap
  # bump, so a rejected promote leaves an object no HEAD points at. Without a
  # record it lingers until account deletion — one multi-GB object per distinct
  # rejected inventory, which accumulates under contention.
  #
  # A rejected digest that never becomes HEAD has no download URL minted for it
  # (URLs are only ever minted for the current HEAD), so it is safe to reclaim.
  # A row is forgotten the moment the same digest is ACCEPTED as HEAD (a later
  # job re-produced and committed it) — its lifecycle then belongs to the
  # supersession prune. `PruneVolumeMasterOrphanWorker` reclaims rows that stay
  # orphaned past the presigned-URL TTL grace. Cascade-deleted with the account.
  def change do
    create table(:runner_volume_master_orphans) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :volume_name, :string, null: false, default: "tuist-cache"
      add :tree_digest, :string, null: false

      timestamps(type: :timestamptz)
    end

    # At most one orphan row per (account, volume, digest): a re-rejected digest
    # upserts rather than duplicating.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_volume_master_orphans, [:account_id, :volume_name, :tree_digest])
  end
end
