defmodule Tuist.Repo.Migrations.ScopeCacheVolumesByFormat do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # A macOS volume is kept either as an APFS sparse image in the VM's share
  # (`sparse`) or as an ASIF image the host hot-plugs as a USB disk (`asif`,
  # macOS 27 guests). Their saved images cannot stand in for each other, so
  # each format is its own lineage.
  def up do
    alter table(:runner_cache_volumes) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :format, :text, null: false, default: "sparse"
    end

    create unique_index(
             :runner_cache_volumes,
             [
               :account_id,
               :provider,
               :provider_instance,
               :scope_id,
               :key,
               :platform,
               :format,
               :architecture,
               :uid
             ],
             name: :runner_cache_volumes_format_identity,
             concurrently: true
           )

    # Keep the format-less index for old server pods and image rollback; every
    # row is `sparse` until a server that allocates `asif` runs. Drop it once
    # no server uses the format-less conflict target.
  end

  def down do
    # Read-only guard prevents collapsing ASIF lineages into sparse ones.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM runner_cache_volumes WHERE format <> 'sparse') THEN
        RAISE EXCEPTION 'Delete ASIF cache volumes before removing format';
      END IF;
    END $$;
    """

    drop index(
           :runner_cache_volumes,
           [
             :account_id,
             :provider,
             :provider_instance,
             :scope_id,
             :key,
             :platform,
             :format,
             :architecture,
             :uid
           ],
           name: :runner_cache_volumes_format_identity,
           concurrently: true
         )

    alter table(:runner_cache_volumes) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :format
    end
  end
end
