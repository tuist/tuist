defmodule Tuist.Repo.Migrations.ScopeCacheVolumesByPlatform do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    alter table(:runner_cache_volumes) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :platform, :text, null: false, default: "linux"
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
               :architecture,
               :uid
             ],
             name: :runner_cache_volumes_platform_identity,
             concurrently: true
           )

    drop index(
           :runner_cache_volumes,
           [:account_id, :provider, :provider_instance, :scope_id, :key, :architecture, :uid],
           name: :runner_cache_volumes_provider_identity,
           concurrently: true
         )
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM runner_cache_volumes WHERE platform <> 'linux') THEN
        RAISE EXCEPTION 'Drain and reclaim macOS cache data and metadata before removing platform';
      END IF;
    END $$;
    """

    create unique_index(
             :runner_cache_volumes,
             [:account_id, :provider, :provider_instance, :scope_id, :key, :architecture, :uid],
             name: :runner_cache_volumes_provider_identity,
             concurrently: true
           )

    drop index(
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

    alter table(:runner_cache_volumes) do
      remove :platform
    end
  end
end
