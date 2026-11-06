defmodule Tuist.Repo.Migrations.EnableMacosCacheVolumes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    drop_if_exists index(
                     :runner_cache_volumes,
                     [
                       :account_id,
                       :provider,
                       :provider_instance,
                       :scope_id,
                       :key,
                       :architecture,
                       :uid
                     ],
                     name: :runner_cache_volumes_provider_identity,
                     concurrently: true
                   )
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM runner_cache_volumes WHERE platform <> 'linux') THEN
        RAISE EXCEPTION 'Disable macOS allocations, drain jobs and reclaim macOS cache data and metadata before rollback';
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
                             :architecture,
                             :uid
                           ],
                           name: :runner_cache_volumes_provider_identity,
                           concurrently: true
                         )
  end
end
