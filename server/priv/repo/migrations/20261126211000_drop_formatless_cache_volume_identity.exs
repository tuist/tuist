defmodule Tuist.Repo.Migrations.DropFormatlessCacheVolumeIdentity do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Deploy only after every server pod uses the format-aware conflict target
  # (ScopeCacheVolumesByFormat): until this index is gone an ASIF volume cannot
  # sit beside the sparse volume of the same key, and older pods' inserts name
  # this index's columns.
  def up do
    drop_if_exists index(
                     :runner_cache_volumes,
                     [
                       :account_id,
                       :provider,
                       :provider_instance,
                       :scope_id,
                       :key,
                       :platform,
                       :architecture,
                       :uid
                     ],
                     name: :runner_cache_volumes_platform_identity,
                     concurrently: true
                   )
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM runner_cache_volumes WHERE format <> 'sparse') THEN
        RAISE EXCEPTION 'Delete ASIF cache volumes before restoring the format-less identity';
      END IF;
    END $$;
    """

    create_if_not_exists unique_index(
                           :runner_cache_volumes,
                           [
                             :account_id,
                             :provider,
                             :provider_instance,
                             :scope_id,
                             :key,
                             :platform,
                             :architecture,
                             :uid
                           ],
                           name: :runner_cache_volumes_platform_identity,
                           concurrently: true
                         )
  end
end
